import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../clash/clash_to_singbox_transformer.dart';
import '../profiles/profile_repository.dart';
import 'subscription_client.dart';

class SubscriptionService {
  const SubscriptionService({
    required SubscriptionClient client,
    required ClashToSingboxTransformer transformer,
  })  : _client = client,
        _transformer = transformer;

  final SubscriptionClient _client;
  final ClashToSingboxTransformer _transformer;

  Future<ProxyProfile> importSubscription(
      {required String name, required Uri url}) async {
    final resolved = await _fetchValidatedContent(url);
    return ProxyProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      content: resolved.content,
      updatedAt: DateTime.now(),
      subscriptionUrl: url.toString(),
      sourceContent: resolved.sourceContent,
      providerFiles: resolved.providerFiles,
    );
  }

  Future<ProxyProfile> refresh(ProxyProfile profile) async {
    final url = profile.subscriptionUrl;
    if (url == null) throw const SubscriptionException('当前配置不是订阅配置');
    return updateSubscriptionUrl(profile, Uri.parse(url));
  }

  Future<ProxyProfile> rebuildCachedProviders(ProxyProfile profile) async {
    final sourceContent = profile.sourceContent;
    final subscriptionUrl = profile.subscriptionUrl;
    if (sourceContent == null || subscriptionUrl == null) return profile;
    final resolved = await _expandProviders(
      sourceContent,
      Uri.parse(subscriptionUrl),
      cachedProviderFiles: profile.providerFiles,
    );
    _validateRuleProviders(resolved.providerFiles);
    return profile.copyWith(
      content: resolved.content,
      updatedAt: DateTime.now(),
      providerFiles: resolved.providerFiles,
    );
  }

  Future<ProxyProfile> updateSubscriptionUrl(
    ProxyProfile profile,
    Uri url,
  ) async {
    final resolved = await _fetchValidatedContent(url);
    return profile.copyWith(
      content: resolved.content,
      updatedAt: DateTime.now(),
      subscriptionUrl: url.toString(),
      sourceContent: resolved.sourceContent,
      providerFiles: resolved.providerFiles,
    );
  }

  Future<ProxyProfile> refreshProvider(
    ProxyProfile profile,
    ProviderFile providerFile,
  ) async {
    final sourceContent = profile.sourceContent;
    final subscriptionUrl = profile.subscriptionUrl;
    if (sourceContent == null || subscriptionUrl == null) {
      throw const SubscriptionException('当前配置没有可刷新的 provider 源文件');
    }
    try {
      final refreshedContent = _decodeSubscriptionContent(
        await _client.fetch(Uri.parse(providerFile.url)),
      );
      final refreshedFiles = [
        for (final file in profile.providerFiles)
          if (_providerFileKey(file) == _providerFileKey(providerFile))
            file.copyWith(
              content: refreshedContent,
              updatedAt: DateTime.now(),
            )
          else
            file,
      ];
      final resolved = await _expandProviders(
        sourceContent,
        Uri.parse(subscriptionUrl),
        cachedProviderFiles: refreshedFiles,
      );
      _transformer.transformYamlToJson(resolved.content);
      return profile.copyWith(
        content: resolved.content,
        updatedAt: DateTime.now(),
        providerFiles: resolved.providerFiles,
      );
    } on FormatException {
      throw const SubscriptionException('provider 内容不是有效的 Clash YAML');
    }
  }

  Future<_ResolvedSubscription> _fetchValidatedContent(Uri url) async {
    try {
      final downloaded = _decodeSubscriptionContent(await _client.fetch(url));
      final resolved = await _expandProviders(downloaded, url);
      _validateRuleProviders(resolved.providerFiles);
      _transformer.transformYamlToJson(resolved.content);
      return resolved;
    } on FormatException {
      throw const SubscriptionException('订阅内容不是有效的 Clash YAML');
    }
  }

  String _decodeSubscriptionContent(String content) {
    final trimmed = content.trim();
    if (trimmed.contains(':') || trimmed.startsWith('---')) return content;
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(trimmed)));
      return decoded.contains(':') ? decoded : content;
    } on FormatException {
      return content;
    }
  }

  void _validateRuleProviders(List<ProviderFile> files) {
    for (final file in files.where((file) => file.kind == ProviderFileKind.rule)) {
      _transformer.ruleProviderSource(
        file.content,
        behavior: file.behavior ?? 'classical',
      );
    }
  }

  Future<_ResolvedSubscription> _expandProviders(
    String content,
    Uri subscriptionUrl, {
    List<ProviderFile>? cachedProviderFiles,
  }) async {
    final document = loadYaml(content);
    if (document is! YamlMap) {
      return _ResolvedSubscription(content: content, sourceContent: content);
    }
    final config = _plainMap(document);
    final proxyProviders = _plainMap(config['proxy-providers']);
    final ruleProviders = _plainMap(config['rule-providers']);
    if (proxyProviders.isEmpty && ruleProviders.isEmpty) {
      return _ResolvedSubscription(content: content, sourceContent: content);
    }
    final proxies = _plainList(config['proxies']);
    final providerNodes = <String, List<String>>{};
    final providerFiles = <ProviderFile>[];
    final cachedFiles = {
      for (final file in cachedProviderFiles ?? const <ProviderFile>[])
        _providerFileKey(file): file,
    };

    for (final entry in proxyProviders.entries) {
      final provider = _plainMap(entry.value);
      if (_providerType(provider) != 'http') {
        throw SubscriptionException('不支持的代理 provider：${entry.key}');
      }
      final providerUrl =
          _providerUrl(subscriptionUrl, provider, '代理 provider');
      final cachedFile =
          cachedFiles[_providerKey(ProviderFileKind.proxy, entry.key)];
      final providerContent = cachedFile?.content ??
          _decodeSubscriptionContent(await _client.fetch(providerUrl));
      final providerDocument = loadYaml(providerContent);
      final nodes = _plainList(
        providerDocument is YamlMap ? providerDocument['proxies'] : null,
      );
      if (nodes.isEmpty) {
        throw SubscriptionException('代理 provider ${entry.key} 没有可用节点');
      }
      proxies.addAll(nodes);
      providerFiles.add(ProviderFile(
        name: entry.key,
        kind: ProviderFileKind.proxy,
        url: providerUrl.toString(),
        content: providerContent,
        updatedAt: cachedFile?.updatedAt ?? DateTime.now(),
      ));
      providerNodes[entry.key] = [
        for (final node in nodes)
          if (_plainMap(node)['name'] case final name?) '$name',
      ];
    }

    final groups = <Object?>[];
    for (final groupValue in _plainList(config['proxy-groups'])) {
      final group = Map<String, dynamic>.from(_plainMap(groupValue));
      final groupProxies = _plainList(group['proxies']);
      for (final providerName
          in _plainList(group['use']).map((value) => '$value')) {
        groupProxies.addAll(providerNodes[providerName] ?? const <String>[]);
      }
      group['proxies'] = groupProxies;
      group.remove('use');
      groups.add(group);
    }

    final rules = _plainList(config['rules']);
    for (final entry in ruleProviders.entries) {
      final provider = _plainMap(entry.value);
      if (_providerType(provider) != 'http') {
        throw SubscriptionException('不支持的规则 provider：${entry.key}');
      }
      final providerUrl =
          _providerUrl(subscriptionUrl, provider, '规则 provider');
      final cachedFile =
          cachedFiles[_providerKey(ProviderFileKind.rule, entry.key)];
      final providerContent = cachedFile?.content ??
          _decodeSubscriptionContent(await _client.fetch(providerUrl));
      final providerDocument = loadYaml(providerContent);
      final payload = _plainList(
        providerDocument is YamlMap ? providerDocument['payload'] : null,
      );
      if (payload.isEmpty) {
        throw SubscriptionException('规则 provider ${entry.key} 没有可用规则');
      }
      providerFiles.add(ProviderFile(
        name: entry.key,
        kind: ProviderFileKind.rule,
        url: providerUrl.toString(),
        content: providerContent,
        updatedAt: cachedFile?.updatedAt ?? DateTime.now(),
        behavior: '${provider['behavior'] ?? 'classical'}'.toLowerCase(),
      ));
    }

    config['proxies'] = proxies;
    config['proxy-groups'] = groups;
    config['rules'] = rules;
    config.remove('proxy-providers');
    config.remove('rule-providers');
    return _ResolvedSubscription(
      content: jsonEncode(config),
      sourceContent: content,
      providerFiles: providerFiles,
    );
  }

  String _providerFileKey(ProviderFile file) =>
      _providerKey(file.kind, file.name);

  String _providerKey(ProviderFileKind kind, String name) =>
      '${kind.name}:$name';

  String _providerType(Map<String, dynamic> provider) =>
      '${provider['type'] ?? ''}'.toLowerCase();

  Uri _providerUrl(
    Uri subscriptionUrl,
    Map<String, dynamic> provider,
    String label,
  ) {
    final rawUrl = '${provider['url'] ?? ''}'.trim();
    final uri = rawUrl.isEmpty ? null : subscriptionUrl.resolve(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw SubscriptionException('$label 地址必须使用 HTTP 或 HTTPS');
    }
    return uri;
  }

  Map<String, dynamic> _plainMap(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': _plainValue(entry.value),
      };
    }
    return <String, dynamic>{};
  }

  List<Object?> _plainList(Object? value) {
    if (value is Iterable) return value.map(_plainValue).toList();
    return <Object?>[];
  }

  Object? _plainValue(Object? value) {
    if (value is Map) return _plainMap(value);
    if (value is Iterable && value is! String) return _plainList(value);
    return value;
  }
}

class _ResolvedSubscription {
  const _ResolvedSubscription({
    required this.content,
    required this.sourceContent,
    this.providerFiles = const [],
  });

  final String content;
  final String sourceContent;
  final List<ProviderFile> providerFiles;
}
