import 'dart:isolate';

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
  return parseClashProxyGroupsFromDocument(loadYaml(source));
}

List<ClashProxyGroup> parseClashProxyGroupsFromDocument(Object? document) {
  if (document is! Map || document['proxy-groups'] is! Iterable) {
    return const [];
  }

  final groups = document['proxy-groups'] as Iterable;
  return groups
      .whereType<Map>()
      .map<ClashProxyGroup>((group) {
        final proxies = (group['proxies'] as Iterable?)
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

Future<List<ClashProxyGroup>> parseClashProxyGroupsInBackground(
  String source,
) async {
  final groups = await Isolate.run(() {
    return parseClashProxyGroups(source)
        .map(
          (group) => <String, Object>{
            'name': group.name,
            'type': group.type,
            'proxies': group.proxies,
            'selectedProxy': group.selectedProxy,
          },
        )
        .toList(growable: false);
  });
  return groups
      .map(
        (group) => ClashProxyGroup(
          name: group['name']! as String,
          type: group['type']! as String,
          proxies: (group['proxies']! as List<Object>).cast<String>(),
          selectedProxy: group['selectedProxy']! as String,
        ),
      )
      .toList(growable: false);
}