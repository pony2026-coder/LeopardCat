import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../profiles/profile_repository.dart';
import 'clash_to_singbox_transformer.dart';

class RuleProviderStore {
  RuleProviderStore({
    Future<Directory> Function()? applicationSupportDirectory,
    ClashToSingboxTransformer transformer =
        const ClashToSingboxTransformer(),
  })  : _applicationSupportDirectory =
            applicationSupportDirectory ?? getApplicationSupportDirectory,
        _transformer = transformer;

  final Future<Directory> Function() _applicationSupportDirectory;
  final ClashToSingboxTransformer _transformer;

  Future<List<RuleProviderReference>> writeForProfile(
    ProxyProfile profile,
  ) async {
    final providers = profile.providerFiles
        .where((file) => file.kind == ProviderFileKind.rule)
        .toList(growable: false);
    if (providers.isEmpty) return const [];

    final root = await _applicationSupportDirectory();
    final directory = Directory('${root.path}/rule-providers/${profile.id}');
    await directory.create(recursive: true);
    final references = <RuleProviderReference>[];
    for (final provider in providers) {
      final tag = 'provider-${_safeIdentifier(profile.id)}-${_safeIdentifier(provider.name)}';
      final file = File('${directory.path}/${_safeIdentifier(provider.name)}.json');
      final source = _transformer.ruleProviderSource(
        provider.content,
        behavior: provider.behavior ?? 'classical',
      );
      await file.writeAsString(jsonEncode(source), flush: true);
      references.add(RuleProviderReference(
        name: provider.name,
        tag: tag,
        path: file.path,
      ));
    }
    return references;
  }

  String _safeIdentifier(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}