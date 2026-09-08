import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leopard_cat/data/clash/clash_to_singbox_transformer.dart';

void main() {
  const source = '''
proxies:
  - name: Secure Node
    type: vless
    server: hk.gateway.net
    port: 443
    uuid: 23a65b91-1b77-4c4f-9e23-74b9710f44f2
    tls: true
    servername: hk.gateway.net
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Secure Node
      - DIRECT
    proxy: Proxy
rules:
  - DOMAIN,google.com,Proxy
  - DOMAIN-SUFFIX,apple.com,DIRECT
  - IP-CIDR,1.1.1.1/32,REJECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
''';

  test('maps Clash nodes and injects TLS fragment settings', () {
    final config = const ClashToSingboxTransformer().transformYaml(source);
    final outbounds = (config['outbounds'] as List).cast<Map<String, dynamic>>();
    final node = outbounds.firstWhere((item) => item['tag'] == 'Secure Node');

    expect(node['type'], 'vless');
    expect(node['server_port'], 443);
    expect(node['tls']['fragment']['enabled'], isTrue);
    expect(node['tls']['fragment']['size'], '10-35');
  });

  test('maps Clash groups and routing rules', () {
    final config = const ClashToSingboxTransformer().transformYaml(source);
    final outbounds = (config['outbounds'] as List).cast<Map<String, dynamic>>();
    final route = config['route'] as Map<String, dynamic>;
    final rules = (route['rules'] as List).cast<Map<String, dynamic>>();
    final group = outbounds.firstWhere((item) => item['tag'] == 'Proxy');

    expect(group['type'], 'selector');
    expect(route['final'], 'Proxy');
    expect(group['outbounds'], ['Secure Node', 'DIRECT']);
    expect(rules[0], {'domain': ['google.com'], 'outbound': 'Proxy'});
    expect(rules[1]['domain_suffix'], ['.apple.com']);
    expect(rules[2]['ip_cidr'], ['1.1.1.1/32']);
    expect(rules[3]['rule_set'], 'geoip-cn');
    expect(rules[4]['outbound'], 'Proxy');
  });

  test('produces valid JSON and mobile TUN defaults', () {
    final json = const ClashToSingboxTransformer().transformYamlToJson(source);
    final config = jsonDecode(json) as Map<String, dynamic>;
    final inbound = (config['inbounds'] as List).single as Map<String, dynamic>;

    expect(inbound['type'], 'tun');
    expect(inbound['stack'], 'gvisor');
    expect(inbound['sniff'], isTrue);
    expect(config['outbounds'], isNotEmpty);
  });
}
