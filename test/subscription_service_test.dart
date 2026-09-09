import 'package:flutter_test/flutter_test.dart';
import 'package:leopard_cat/data/clash/clash_to_singbox_transformer.dart';
import 'package:leopard_cat/data/profiles/profile_repository.dart';
import 'package:leopard_cat/data/subscription/subscription_client.dart';
import 'package:leopard_cat/data/subscription/subscription_service.dart';

const validContent = 'proxies: []\nproxy-groups: []\nrules: []';

void main() {
  test('imports validated content with its subscription source', () async {
    const service = SubscriptionService(
      client: _FakeSubscriptionClient(validContent),
      transformer: ClashToSingboxTransformer(),
    );

    final profile = await service.importSubscription(
      name: '远程订阅',
      url: Uri.parse('https://example.com/sub.yaml'),
    );

    expect(profile.name, '远程订阅');
    expect(profile.content, validContent);
    expect(profile.subscriptionUrl, 'https://example.com/sub.yaml');
  });

  test('does not accept invalid downloaded YAML', () async {
    const service = SubscriptionService(
      client: _FakeSubscriptionClient('invalid: [yaml'),
      transformer: ClashToSingboxTransformer(),
    );

    expect(
      () => service.importSubscription(name: '远程订阅', url: Uri.parse('https://example.com/sub.yaml')),
      throwsA(isA<SubscriptionException>()),
    );
  });

  test('decodes a Base64-encoded Clash subscription before validation', () async {
    const service = SubscriptionService(
      client: _FakeSubscriptionClient(base64EncodedContent),
      transformer: ClashToSingboxTransformer(),
    );

    final profile = await service.importSubscription(
      name: 'Base64 订阅',
      url: Uri.parse('https://example.com/sub'),
    );

    expect(profile.content, validContent);
  });

  test('refreshes an existing subscription profile', () async {
    const service = SubscriptionService(
      client: _FakeSubscriptionClient(validContent),
      transformer: ClashToSingboxTransformer(),
    );
    final profile = ProxyProfile(
      id: 'remote',
      name: '远程订阅',
      content: 'proxies: []',
      updatedAt: DateTime.utc(2026),
      subscriptionUrl: 'https://example.com/sub.yaml',
    );

    final refreshed = await service.refresh(profile);

    expect(refreshed.id, profile.id);
    expect(refreshed.content, validContent);
  });
}

const base64EncodedContent = 'cHJveGllczogW10KcHJveHktZ3JvdXBzOiBbXQpydWxlczogW10=';

class _FakeSubscriptionClient implements SubscriptionClient {
  const _FakeSubscriptionClient(this.content);

  final String content;

  @override
  Future<String> fetch(Uri uri) async => content;
}