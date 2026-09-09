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
    expect(rules[0]['action'], 'sniff');
    expect(rules[1], {'domain': ['google.com'], 'outbound': 'Proxy'});
    expect(rules[2]['domain_suffix'], ['.apple.com']);
    expect(rules[3]['ip_cidr'], ['1.1.1.1/32']);
    expect(rules[4]['rule_set'], 'geoip-cn');
    expect(rules[5]['outbound'], 'Proxy');
  });

  test('produces valid JSON and sing-box v1.14 mobile defaults', () {
    final json = const ClashToSingboxTransformer().transformYamlToJson(source);
    final config = jsonDecode(json) as Map<String, dynamic>;
    final inbound = (config['inbounds'] as List).single as Map<String, dynamic>;
    final dnsServers = (config['dns']['servers'] as List).cast<Map<String, dynamic>>();

    expect(inbound['type'], 'tun');
    expect(inbound['stack'], 'gvisor');
    expect(inbound.containsKey('sniff'), isFalse);
    expect(dnsServers.first['type'], 'local');
    expect(dnsServers[1]['type'], 'https');
    expect(config['route']['rules'].first['action'], 'sniff');
    expect(config['outbounds'], isNotEmpty);
  });

  test('maps common Clash transport, Reality, UDP, and plugin options', () {
    const compatibilitySource = '''
proxies:
  - name: Reality WS
    type: vless
    server: example.com
    port: 443
    uuid: 23a65b91-1b77-4c4f-9e23-74b9710f44f2
    tls: true
    udp: true
    client-fingerprint: firefox
    reality-opts:
      public-key: test-public-key
      short-id: abcd
    network: ws
    ws-opts:
      path: /vless
      headers:
        Host: edge.example.com
  - name: Grpc Node
    type: trojan
    server: example.com
    port: 443
    password: secret
    tls: true
    network: grpc
    grpc-opts:
      grpc-service-name: tunnel
  - name: Plugin SS
    type: ss
    server: example.com
    port: 443
    cipher: aes-128-gcm
    password: secret
    plugin: obfs-local
    plugin-opts: obfs=http;obfs-host=example.com
proxy-groups: []
rules: []
''';
    final outbounds = (const ClashToSingboxTransformer()
            .transformYaml(compatibilitySource)['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    final reality = outbounds.firstWhere((item) => item['tag'] == 'Reality WS');
    final grpc = outbounds.firstWhere((item) => item['tag'] == 'Grpc Node');
    final shadowsocks = outbounds.firstWhere((item) => item['tag'] == 'Plugin SS');

    expect(reality['network'], ['tcp', 'udp']);
    expect(reality['tls']['reality']['public_key'], 'test-public-key');
    expect(reality['tls']['utls']['fingerprint'], 'firefox');
    expect(reality['transport']['headers'], {'Host': 'edge.example.com'});
    expect(grpc['transport'], {'type': 'grpc', 'service_name': 'tunnel'});
    expect(shadowsocks['plugin'], 'obfs-local');
    expect(shadowsocks['plugin_opts'], 'obfs=http;obfs-host=example.com');
  });
}
