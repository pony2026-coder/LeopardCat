import 'dart:convert';

import 'package:yaml/yaml.dart';

class FragmentOptions {
  const FragmentOptions({
    this.enabled = true,
  });

  final bool enabled;
}

enum StaticResourceKind { geoip, geosite }

class StaticResource {
  const StaticResource({
    required this.kind,
    required this.tag,
    required this.url,
  });

  final StaticResourceKind kind;
  final String tag;
  final String url;

  Map<String, dynamic> toRuleSet() => {
        'type': 'remote',
        'tag': tag,
        'format': 'binary',
        'url': url,
      };
}

class RuleProviderReference {
  const RuleProviderReference({
    required this.name,
    required this.tag,
    required this.path,
  });

  final String name;
  final String tag;
  final String path;

  Map<String, String> toRuleSet() => {
        'type': 'local',
        'tag': tag,
        'format': 'source',
        'path': path,
      };
}

class ClashToSingboxTransformer {
  const ClashToSingboxTransformer({this.fragment = const FragmentOptions()});

  final FragmentOptions fragment;

  Map<String, dynamic> transformYaml(
    String source, {
    Iterable<RuleProviderReference> ruleProviders = const [],
  }) {
    final document = loadYaml(source);
    return transform(document, ruleProviders: ruleProviders);
  }

  String transformYamlToJson(
    String source, {
    Iterable<RuleProviderReference> ruleProviders = const [],
  }) {
    return const JsonEncoder.withIndent('  ')
        .convert(transformYaml(source, ruleProviders: ruleProviders));
  }

  List<StaticResource> staticResources(String source) {
    final document = loadYaml(source);
    return _staticResources(_map(document)['rules']);
  }

  Map<String, dynamic> transform(
    Object? source, {
    Iterable<RuleProviderReference> ruleProviders = const [],
  }) {
    final config = _map(source);
    final proxies = _list(config['proxies']);
    final proxyGroups = _list(config['proxy-groups']);
    final resources = _staticResources(config['rules']);
    final ruleProviderReferences = {
      for (final provider in ruleProviders) provider.name: provider,
    };
    final outbounds = <Map<String, dynamic>>[
      ...proxies.map(_proxyToOutbound),
      ...proxyGroups.map(_groupToOutbound),
      {'type': 'direct', 'tag': 'DIRECT'},
      {'type': 'block', 'tag': 'REJECT'},
    ];

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
        if (resources.isNotEmpty || ruleProviderReferences.isNotEmpty)
          'rule_set': [
            ...resources.map((resource) => resource.toRuleSet()),
            ...ruleProviderReferences.values.map((provider) => provider.toRuleSet()),
          ],
        'rules': [
          {'action': 'sniff'},
          ..._rulesToSingbox(config['rules'], ruleProviderReferences),
        ],
      },
      'experimental': {
        'cache_file': {
          'enabled': true,
          'cache_id': 'leopard-cat-global',
        },
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
        tls['fragment'] = true;
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

  List<Map<String, dynamic>> _rulesToSingbox(
    Object? value,
    Map<String, RuleProviderReference> ruleProviders,
  ) {
    final rules = <Map<String, dynamic>>[];
    for (final entry in _list(value)) {
      final fields = _stringList(entry);
      if (fields.length < 2) continue;
      final kind = fields.first.toUpperCase();
      final target = fields.last;
      final rule = <String, dynamic>{};
      switch (kind) {
        case 'RULE-SET':
          final provider = ruleProviders[fields[1]];
          if (provider == null) continue;
          rule['rule_set'] = provider.tag;
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
          final country = fields[1].toLowerCase();
          if (country == 'lan' || country == 'private') {
            rule['ip_is_private'] = true;
          } else {
            rule['rule_set'] = 'geoip-$country';
          }
        case 'GEOSITE':
          rule['rule_set'] = 'geosite-${fields[1].toLowerCase()}';
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

  Map<String, dynamic> ruleProviderSource(
    String content, {
    required String behavior,
  }) {
    final document = loadYaml(content);
    final payload = _list(_map(document)['payload']);
    if (payload.isEmpty) {
      throw const FormatException('Rule provider has no payload');
    }
    final rules = <Map<String, dynamic>>[];
    for (final entry in payload) {
      final rule = _providerEntryToRule(_string(entry), behavior);
      if (rule != null) rules.add(rule);
    }
    if (rules.isEmpty) {
      throw const FormatException('Rule provider has no supported rules');
    }
    return {'version': 1, 'rules': rules};
  }

  Map<String, dynamic>? _providerEntryToRule(String value, String behavior) {
    final normalizedBehavior = behavior.toLowerCase();
    if (normalizedBehavior == 'domain') {
      return value.startsWith('+.')
          ? {'domain_suffix': [value.substring(2)]}
          : {'domain': [value]};
    }
    if (normalizedBehavior == 'ipcidr') {
      return {'ip_cidr': [value]};
    }
    if (normalizedBehavior != 'classical') return null;
    final fields = value.split(',').map((item) => item.trim()).toList();
    if (fields.length < 2) return null;
    return switch (fields.first.toUpperCase()) {
      'DOMAIN' => {'domain': [fields[1]]},
      'DOMAIN-SUFFIX' => {'domain_suffix': [fields[1].replaceFirst(RegExp(r'^\\.'), '')]},
      'DOMAIN-KEYWORD' => {'domain_keyword': [fields[1]]},
      'IP-CIDR' || 'IP-CIDR6' => {'ip_cidr': [fields[1]]},
      _ => null,
    };
  }

  List<StaticResource> _staticResources(Object? value) {
    final resources = <String, StaticResource>{};
    for (final entry in _list(value)) {
      final fields = _stringList(entry);
      if (fields.length < 2) continue;
      final name = fields[1].toLowerCase();
      switch (fields.first.toUpperCase()) {
        case 'GEOIP' when name != 'lan' && name != 'private':
          final tag = 'geoip-$name';
          resources.putIfAbsent(
            tag,
            () => StaticResource(
              kind: StaticResourceKind.geoip,
              tag: tag,
              url: 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/$tag.srs',
            ),
          );
        case 'GEOSITE':
          final tag = 'geosite-$name';
          resources.putIfAbsent(
            tag,
            () => StaticResource(
              kind: StaticResourceKind.geosite,
              tag: tag,
              url: 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/$tag.srs',
            ),
          );
      }
    }
    return resources.values.toList(growable: false);
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
