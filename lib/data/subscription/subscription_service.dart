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
    final content = await _fetchValidatedContent(url);
    return ProxyProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      content: content,
      updatedAt: DateTime.now(),
      subscriptionUrl: url.toString(),
    );
  }

  Future<ProxyProfile> refresh(ProxyProfile profile) async {
    final url = profile.subscriptionUrl;
    if (url == null) throw const SubscriptionException('当前配置不是订阅配置');
    final content = await _fetchValidatedContent(Uri.parse(url));
    return profile.copyWith(content: content, updatedAt: DateTime.now());
  }

  Future<String> _fetchValidatedContent(Uri url) async {
    try {
      final downloaded = _decodeSubscriptionContent(await _client.fetch(url));
      final content = await _expandProviders(downloaded, url);
      _transformer.transformYamlToJson(content);
      return content;
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

  Future<String> _expandProviders(String content, Uri subscriptionUrl) async {
    final document = loadYaml(content);
    if (document is! YamlMap) return content;
    final config = _plainMap(document);
    final proxyProviders = _plainMap(config['proxy-providers']);
    final ruleProviders = _plainMap(config['rule-providers']);
    if (proxyProviders.isEmpty && ruleProviders.isEmpty) return content;
    final proxies = _plainList(config['proxies']);
    final providerNodes = <String, List<String>>{};

    for (final entry in proxyProviders.entries) {
      final provider = _plainMap(entry.value);
      if (_providerType(provider) != 'http') {
        throw SubscriptionException('不支持的代理 provider：${entry.key}');
      }
      final providerUrl =
          _providerUrl(subscriptionUrl, provider, '代理 provider');
      final providerContent =
          _decodeSubscriptionContent(await _client.fetch(providerUrl));
      final providerDocument = loadYaml(providerContent);
      final nodes = _plainList(
        providerDocument is YamlMap ? providerDocument['proxies'] : null,
      );
      if (nodes.isEmpty) {
        throw SubscriptionException('代理 provider ${entry.key} 没有可用节点');
      }
      proxies.addAll(nodes);
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
    final expandedRules = <Object?>[];
    final ruleProviderPayloads = <String, List<Object?>>{};
    for (final ruleValue in rules) {
      final fields =
          '$ruleValue'.split(',').map((field) => field.trim()).toList();
      if (fields.length < 3 || fields.first.toUpperCase() != 'RULE-SET') {
        expandedRules.add(ruleValue);
        continue;
      }
      final provider = _plainMap(ruleProviders[fields[1]]);
      if (_providerType(provider) != 'http') {
        throw SubscriptionException('不支持的规则 provider：${fields[1]}');
      }
      final payload = ruleProviderPayloads[fields[1]] ??
          await _downloadRuleProvider(subscriptionUrl, fields[1], provider);
      ruleProviderPayloads[fields[1]] = payload;
      if (payload.isEmpty) {
        throw SubscriptionException('规则 provider ${fields[1]} 没有可用规则');
      }
      for (final payloadRule in payload) {
        final providerFields = _providerRuleFields(provider, payloadRule);
        expandedRules.add([...providerFields, fields.last].join(','));
      }
    }

    config['proxies'] = proxies;
    config['proxy-groups'] = groups;
    config['rules'] = expandedRules;
    config.remove('proxy-providers');
    config.remove('rule-providers');
    return jsonEncode(config);
  }

  Future<List<Object?>> _downloadRuleProvider(
    Uri subscriptionUrl,
    String providerName,
    Map<String, dynamic> provider,
  ) async {
    final providerUrl = _providerUrl(subscriptionUrl, provider, '规则 provider');
    final providerContent =
        _decodeSubscriptionContent(await _client.fetch(providerUrl));
    final providerDocument = loadYaml(providerContent);
    final payload = _plainList(
      providerDocument is YamlMap ? providerDocument['payload'] : null,
    );
    if (payload.isEmpty) {
      throw SubscriptionException('规则 provider $providerName 没有可用规则');
    }
    return payload;
  }

  List<String> _providerRuleFields(
    Map<String, dynamic> provider,
    Object? payloadRule,
  ) {
    final value = '$payloadRule'.trim();
    return switch ('${provider['behavior'] ?? 'classical'}'.toLowerCase()) {
      'classical' => value.split(',').map((field) => field.trim()).toList(),
      'domain' => [
          if (value.startsWith('+.')) 'DOMAIN-SUFFIX' else 'DOMAIN',
          value.startsWith('+.') ? value.substring(2) : value,
        ],
      'ipcidr' => [value.contains(':') ? 'IP-CIDR6' : 'IP-CIDR', value],
      final behavior => throw SubscriptionException(
          '不支持的规则 provider behavior：$behavior',
        ),
    };
  }

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
