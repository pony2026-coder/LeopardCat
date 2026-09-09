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
      () => service.importSubscription(
          name: '远程订阅', url: Uri.parse('https://example.com/sub.yaml')),
      throwsA(isA<SubscriptionException>()),
    );
  });

  test('decodes a Base64-encoded Clash subscription before validation',
      () async {
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

  test('downloads and expands proxy and rule providers', () async {
    final client = _RoutingSubscriptionClient({
      'https://example.com/sub.yaml': '''
proxy-providers:
  airport:
    type: http
    url: ./providers/airport.yaml
proxy-groups:
  - name: Proxy
    type: select
    use: [airport]
rule-providers:
  custom:
    type: http
    behavior: classical
    url: ./rules/custom.yaml
rules:
  - RULE-SET,custom,Proxy
  - MATCH,DIRECT
''',
      'https://example.com/providers/airport.yaml': '''
proxies:
  - name: Provider Node
    type: ss
    server: node.example.com
    port: 443
    cipher: aes-128-gcm
    password: secret
''',
      'https://example.com/rules/custom.yaml': '''
payload:
  - DOMAIN-SUFFIX,example.org
  - IP-CIDR,10.0.0.0/8,no-resolve
''',
    });
    final service = SubscriptionService(
      client: client,
      transformer: const ClashToSingboxTransformer(),
    );

    final profile = await service.importSubscription(
      name: 'Provider 订阅',
      url: Uri.parse('https://example.com/sub.yaml'),
    );
    final config =
        const ClashToSingboxTransformer().transformYaml(profile.content);
    final outbounds =
        (config['outbounds'] as List).cast<Map<String, dynamic>>();
    final route = config['route'] as Map<String, dynamic>;
    final rules = (route['rules'] as List).cast<Map<String, dynamic>>();

    expect(client.requestedUris, [
      Uri.parse('https://example.com/sub.yaml'),
      Uri.parse('https://example.com/providers/airport.yaml'),
      Uri.parse('https://example.com/rules/custom.yaml'),
    ]);
    expect(profile.providerFiles, hasLength(2));
    expect(profile.providerFiles.first.name, 'airport');
    expect(profile.providerFiles.first.kind, ProviderFileKind.proxy);
    expect(profile.providerFiles.first.content, contains('Provider Node'));
    expect(profile.providerFiles.last.name, 'custom');
    expect(profile.providerFiles.last.kind, ProviderFileKind.rule);
    expect(outbounds.any((outbound) => outbound['tag'] == 'Provider Node'),
        isTrue);
    expect(
      outbounds
          .firstWhere((outbound) => outbound['tag'] == 'Proxy')['outbounds'],
      ['Provider Node'],
    );
    expect(rules[1], {
      'domain_suffix': ['.example.org'],
      'domain': ['example.org'],
      'outbound': 'Proxy'
    });
    expect(rules[2], {
      'ip_cidr': ['10.0.0.0/8'],
      'outbound': 'Proxy'
    });
  });

  test('refreshes one provider file without downloading the others', () async {
    final client = _RoutingSubscriptionClient({
      'https://example.com/providers/airport.yaml': '''
proxies:
  - name: Refreshed Node
    type: ss
    server: refreshed.example.com
    port: 443
    cipher: aes-128-gcm
    password: secret
''',
    });
    final service = SubscriptionService(
      client: client,
      transformer: const ClashToSingboxTransformer(),
    );
    final profile = ProxyProfile(
      id: 'provider-profile',
      name: 'Provider 订阅',
      content: validContent,
      sourceContent: '''
proxy-providers:
  airport:
    type: http
    url: ./providers/airport.yaml
proxy-groups:
  - name: Proxy
    type: select
    use: [airport]
rules: []
''',
      providerFiles: [
        ProviderFile(
          name: 'airport',
          kind: ProviderFileKind.proxy,
          url: 'https://example.com/providers/airport.yaml',
          content: 'proxies: []',
          updatedAt: DateTime.utc(2026),
        ),
      ],
      updatedAt: DateTime.utc(2026),
      subscriptionUrl: 'https://example.com/sub.yaml',
    );

    final refreshed =
        await service.refreshProvider(profile, profile.providerFiles.single);

    expect(client.requestedUris, [
      Uri.parse('https://example.com/providers/airport.yaml'),
    ]);
    expect(refreshed.providerFiles.single.content, contains('Refreshed Node'));
    expect(refreshed.content, contains('Refreshed Node'));
  });

  test('rejects unsupported local providers', () async {
    const service = SubscriptionService(
      client: _FakeSubscriptionClient('''
proxy-providers:
  local:
    type: file
    path: ./local.yaml
proxy-groups:
  - name: Proxy
    type: select
    use: [local]
rules: []
'''),
      transformer: ClashToSingboxTransformer(),
    );

    expect(
      () => service.importSubscription(
        name: '本地 Provider',
        url: Uri.parse('https://example.com/sub.yaml'),
      ),
      throwsA(
        isA<SubscriptionException>().having(
          (error) => error.message,
          'message',
          '不支持的代理 provider：local',
        ),
      ),
    );
  });

  test('expands domain and ipcidr rule provider behavior', () async {
    final client = _RoutingSubscriptionClient({
      'https://example.com/sub.yaml': '''
proxies: []
proxy-groups: []
rule-providers:
  domains:
    type: http
    behavior: domain
    url: ./domains.yaml
  networks:
    type: http
    behavior: ipcidr
    url: ./networks.yaml
rules:
  - RULE-SET,domains,DIRECT
  - RULE-SET,networks,REJECT
''',
      'https://example.com/domains.yaml': '''
payload:
  - +.example.com
  - exact.example.org
''',
      'https://example.com/networks.yaml': '''
payload:
  - 192.0.2.0/24
  - 2001:db8::/32
''',
    });
    final service = SubscriptionService(
      client: client,
      transformer: const ClashToSingboxTransformer(),
    );

    final profile = await service.importSubscription(
      name: '规则 Provider',
      url: Uri.parse('https://example.com/sub.yaml'),
    );
    final route = const ClashToSingboxTransformer()
        .transformYaml(profile.content)['route'] as Map<String, dynamic>;
    final rules = (route['rules'] as List).cast<Map<String, dynamic>>();

    expect(rules[1]['domain_suffix'], ['.example.com']);
    expect(rules[2]['domain'], ['exact.example.org']);
    expect(rules[3]['ip_cidr'], ['192.0.2.0/24']);
    expect(rules[4]['ip_cidr'], ['2001:db8::/32']);
  });
}

const base64EncodedContent =
    'cHJveGllczogW10KcHJveHktZ3JvdXBzOiBbXQpydWxlczogW10=';

class _FakeSubscriptionClient implements SubscriptionClient {
  const _FakeSubscriptionClient(this.content);

  final String content;

  @override
  Future<String> fetch(Uri uri) async => content;
}

class _RoutingSubscriptionClient implements SubscriptionClient {
  _RoutingSubscriptionClient(this.responses);

  final Map<String, String> responses;
  final List<Uri> requestedUris = [];

  @override
  Future<String> fetch(Uri uri) async {
    requestedUris.add(uri);
    return responses[uri.toString()] ??
        (throw SubscriptionException('没有响应：$uri'));
  }
}
