import 'package:yaml/yaml.dart';

class ClashProxyGroup {
  const ClashProxyGroup({
    required this.name,
    required this.type,
    required this.proxies,
    required this.selectedProxy,
  });

  final String name;
  final String type;
  final List<String> proxies;
  final String selectedProxy;

  bool get isSelectable => type != 'url-test' && type != 'fallback';
}

List<ClashProxyGroup> parseClashProxyGroups(String source) {
  final document = loadYaml(source);
  if (document is! YamlMap || document['proxy-groups'] is! YamlList) return const [];

    final groups = document['proxy-groups'] as YamlList;
    return groups
      .whereType<YamlMap>()
      .map<ClashProxyGroup>((group) {
        final proxies = (group['proxies'] as YamlList?)
                ?.map((proxy) => '$proxy'.trim())
                .where((proxy) => proxy.isNotEmpty)
                .toList() ??
            const <String>[];
        return ClashProxyGroup(
          name: '${group['name'] ?? ''}'.trim(),
          type: '${group['type'] ?? 'select'}'.trim().toLowerCase(),
          proxies: proxies,
          selectedProxy: '${group['proxy'] ?? (proxies.isEmpty ? '' : proxies.first)}'.trim(),
        );
      })
      .where((group) => group.name.isNotEmpty && group.proxies.isNotEmpty)
      .toList(growable: false);
}