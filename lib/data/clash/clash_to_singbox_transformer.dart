import 'dart:convert';

import 'package:yaml/yaml.dart';

class FragmentOptions {
  const FragmentOptions({
    this.enabled = true,
    this.proxySize = '10-35',
    this.proxySleep = '10-25',
    this.directSize = '15-40',
    this.directSleep = '10-20',
  });

  final bool enabled;
  final String proxySize;
  final String proxySleep;
  final String directSize;
  final String directSleep;
}

class ClashToSingboxTransformer {
  const ClashToSingboxTransformer({this.fragment = const FragmentOptions()});

  final FragmentOptions fragment;

  Map<String, dynamic> transformYaml(String source) {
    final document = loadYaml(source);
    return transform(document);
  }

  String transformYamlToJson(String source) {
    return const JsonEncoder.withIndent('  ').convert(transformYaml(source));
  }

  Map<String, dynamic> transform(Object? source) {
    final config = _map(source);
    final proxies = _list(config['proxies']);
    final proxyGroups = _list(config['proxy-groups']);
    final outbounds = <Map<String, dynamic>>[
      ...proxies.map(_proxyToOutbound),
      ...proxyGroups.map(_groupToOutbound),
      {'type': 'direct', 'tag': 'DIRECT'},
      {'type': 'block', 'tag': 'REJECT'},
    ];

    if (fragment.enabled) {
      outbounds.add(_fragmentDirectOutbound());
    }

    return {
      'log': {'level': 'info', 'timestamp': true},
      'dns': {
        'servers': [
          {'tag': 'local', 'type': 'local'},
          {'tag': 'remote', 'type': 'https', 'server': '1.1.1.1', 'path': '/dns-query'},
        ],
        'final': 'remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'leopardcat0',
          'address': ['172.19.0.1/30'],
          'auto_route': true,
          'strict_route': true,
          'stack': 'gvisor',
        },
      ],
      'outbounds': outbounds,
      'route': {
        'auto_detect_interface': true,
        'final': _finalOutbound(config, proxyGroups),
        'rules': [
          {'action': 'sniff'},
          ..._rulesToSingbox(config['rules']),
        ],
      },
    };
  }

  Map<String, dynamic> _proxyToOutbound(Object? value) {
    final proxy = _map(value);
    final type = _string(proxy['type']).toLowerCase();
    final outbound = <String, dynamic>{
      'type': _outboundType(type),
      'tag': _string(proxy['name'], fallback: 'proxy-${proxy.hashCode}'),
      'server': _string(proxy['server']),
      'server_port': _int(proxy['port']),
    };

    switch (type) {
      case 'ss':
      case 'shadowsocks':
        outbound['method'] = _string(proxy['cipher']);
        outbound['password'] = _string(proxy['password']);
        if (_string(proxy['plugin']).isNotEmpty) {
          outbound['plugin'] = _string(proxy['plugin']);
          outbound['plugin_opts'] = _string(proxy['plugin-opts']);
        }
      case 'vmess':
        outbound['uuid'] = _string(proxy['uuid']);
        outbound['security'] = _string(proxy['cipher'], fallback: 'auto');
        outbound['alter_id'] = _int(proxy['alterId'] ?? proxy['alter-id'], fallback: 0);
      case 'vless':
        outbound['uuid'] = _string(proxy['uuid']);
        if (_string(proxy['flow']).isNotEmpty) outbound['flow'] = _string(proxy['flow']);
      case 'trojan':
        outbound['password'] = _string(proxy['password']);
      case 'hysteria2':
        outbound['password'] = _string(proxy['password']);
        if (_map(proxy['obfs']).isNotEmpty) outbound['obfs'] = _map(proxy['obfs']);
    }

    if (_bool(proxy['udp'])) outbound['network'] = ['tcp', 'udp'];

    if (_bool(proxy['tls']) || proxy['servername'] != null || proxy['sni'] != null) {
      final tls = <String, dynamic>{
        'enabled': true,
        'server_name': _string(proxy['servername'] ?? proxy['sni'], fallback: _string(proxy['server'])),
        'insecure': _bool(proxy['skip-cert-verify']),
      };
      if (fragment.enabled) {
        tls['fragment'] = {
          'enabled': true,
          'size': fragment.proxySize,
          'sleep': fragment.proxySleep,
        };
      }
      final realityOptions = _map(proxy['reality-opts']);
      if (realityOptions.isNotEmpty) {
        tls['reality'] = {
          'enabled': true,
          'public_key': _string(realityOptions['public-key']),
          'short_id': _string(realityOptions['short-id']),
        };
        tls['utls'] = {
          'enabled': true,
          'fingerprint': _string(proxy['client-fingerprint'], fallback: 'chrome'),
        };
      }
      outbound['tls'] = tls;
    }

    final network = _string(proxy['network']);
    if (network.isNotEmpty) {
      outbound['transport'] = _transport(network, proxy);
    }
    return outbound;
  }

  Map<String, dynamic> _transport(String network, Map<String, dynamic> proxy) {
    return switch (network) {
      'ws' => {
          'type': 'ws',
          'path': _string(_map(proxy['ws-opts'])['path'], fallback: '/'),
          if (_map(_map(proxy['ws-opts'])['headers']).isNotEmpty)
            'headers': _map(_map(proxy['ws-opts'])['headers']),
        },
      'grpc' => {
          'type': 'grpc',
          'service_name': _string(_map(proxy['grpc-opts'])['grpc-service-name']),
        },
      'http' => {
          'type': 'http',
          'host': _stringList(_map(proxy['http-opts'])['host']),
          'path': _string(_map(proxy['http-opts'])['path'], fallback: '/'),
        },
      'httpupgrade' => {
          'type': 'httpupgrade',
          'host': _string(_map(proxy['http-opts'])['host']),
          'path': _string(_map(proxy['http-opts'])['path'], fallback: '/'),
        },
      _ => {'type': network},
    };
  }

  Map<String, dynamic> _groupToOutbound(Object? value) {
    final group = _map(value);
    final type = _string(group['type']).toLowerCase();
    final tags = _list(group['proxies']).map((item) => _string(item)).where((item) => item.isNotEmpty).toList();
    final tag = _string(group['name'], fallback: 'group-${group.hashCode}');

    if (type == 'url-test' || type == 'fallback') {
      return {
        'type': 'urltest',
        'tag': tag,
        'outbounds': tags,
        if (group['url'] != null) 'url': _string(group['url']),
        if (group['interval'] != null) 'interval': _string(group['interval']),
      };
    }
    return {'type': 'selector', 'tag': tag, 'outbounds': tags};
  }

  Map<String, dynamic> _fragmentDirectOutbound() {
    return {
      'type': 'direct',
      'tag': 'DIRECT-FRAGMENT',
      'tls': {
        'enabled': true,
        'fragment': {
          'enabled': true,
          'size': fragment.directSize,
          'sleep': fragment.directSleep,
        },
      },
    };
  }

  List<Map<String, dynamic>> _rulesToSingbox(Object? value) {
    final rules = <Map<String, dynamic>>[];
    for (final entry in _list(value)) {
      final fields = _stringList(entry);
      if (fields.length < 2) continue;
      final kind = fields.first.toUpperCase();
      final target = fields.last;
      final rule = <String, dynamic>{};
      switch (kind) {
        case 'DOMAIN':
          rule['domain'] = [fields[1]];
        case 'DOMAIN-SUFFIX':
          rule['domain_suffix'] = [fields[1].startsWith('.') ? fields[1] : '.${fields[1]}'];
          rule['domain'] = [fields[1]];
        case 'DOMAIN-KEYWORD':
          rule['domain_keyword'] = [fields[1]];
        case 'IP-CIDR':
        case 'IP-CIDR6':
          rule['ip_cidr'] = [fields[1]];
        case 'GEOIP':
          rule['rule_set'] = 'geoip-${fields[1].toLowerCase()}';
        case 'MATCH':
          rule['outbound'] = target;
        default:
          continue;
      }
      if (kind != 'MATCH') rule['outbound'] = target;
      rules.add(rule);
    }
    return rules;
  }

  String _finalOutbound(Map<String, dynamic> config, List<Object?> groups) {
    final proxy = _string(config['proxy']);
    if (proxy.isNotEmpty) return proxy;
    if (groups.isNotEmpty) return _string(_map(groups.first)['name'], fallback: 'DIRECT');
    return 'DIRECT';
  }

  String _outboundType(String type) {
    return switch (type) {
      'ss' || 'shadowsocks' => 'shadowsocks',
      'vmess' => 'vmess',
      'vless' => 'vless',
      'trojan' => 'trojan',
      'hysteria2' => 'hysteria2',
      _ => type.isEmpty ? 'direct' : type,
    };
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is YamlMap) return value.map((key, value) => MapEntry('$key', value));
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    return <String, dynamic>{};
  }

  List<Object?> _list(Object? value) {
    if (value is YamlList) return value.cast<Object?>();
    if (value is List) return value.cast<Object?>();
    if (value is Iterable) return value.cast<Object?>().toList();
    return const <Object?>[];
  }

  List<String> _stringList(Object? value) {
    if (value is String) return value.split(',').map((item) => item.trim()).toList();
    return _list(value).map((item) => _string(item)).toList();
  }

  String _string(Object? value, {String fallback = ''}) {
    final result = value?.toString() ?? '';
    return result.isEmpty ? fallback : result;
  }

  int _int(Object? value, {int fallback = 0}) {
    return int.tryParse(_string(value)) ?? fallback;
  }

  bool _bool(Object? value) {
    return value == true || _string(value).toLowerCase() == 'true';
  }
}
