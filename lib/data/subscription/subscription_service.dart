import 'dart:convert';

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

  Future<ProxyProfile> importSubscription({required String name, required Uri url}) async {
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
    final content = _decodeSubscriptionContent(await _client.fetch(url));
    try {
      _transformer.transformYamlToJson(content);
    } on FormatException {
      throw const SubscriptionException('订阅内容不是有效的 Clash YAML');
    }
    return content;
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
}