import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leopard_cat/data/clash/rule_provider_store.dart';
import 'package:leopard_cat/data/profiles/profile_repository.dart';

void main() {
  test('writes each rule provider as a compact local source rule set', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'leopard_cat_rule_provider_test_',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final profile = ProxyProfile(
      id: 'large-rules',
      name: 'Large rules',
      content: 'proxies: []\nproxy-groups: []\nrules: []',
      updatedAt: DateTime.utc(2026),
      providerFiles: [
        ProviderFile(
          name: 'domains',
          kind: ProviderFileKind.rule,
          url: 'https://example.com/domains.yaml',
          behavior: 'domain',
          content: 'payload:\n  - +.example.com\n  - exact.example.org',
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );

    final references = await RuleProviderStore(
      applicationSupportDirectory: () async => temporaryDirectory,
    ).writeForProfile(profile);

    expect(references, hasLength(1));
    expect(references.single.name, 'domains');
    expect(references.single.tag, 'provider-large-rules-domains');
    final content = jsonDecode(
      await File(references.single.path).readAsString(),
    );
    expect(content, {
      'version': 1,
      'rules': [
        {'domain_suffix': ['example.com']},
        {'domain': ['exact.example.org']},
      ],
    });
  });
}