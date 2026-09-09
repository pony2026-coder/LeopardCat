import 'package:flutter_test/flutter_test.dart';
import 'package:leopard_cat/data/clash/proxy_group.dart';

void main() {
  test('parses selectable and automatic Clash proxy groups', () {
    const source = '''
proxy-groups:
  - name: Global
    type: select
    proxies: [Tokyo, DIRECT]
  - name: Auto
    type: url-test
    proxy: Tokyo
    proxies: [Tokyo, Seoul]
''';

    final groups = parseClashProxyGroups(source);

    expect(groups, hasLength(2));
    expect(groups.first.selectedProxy, 'Tokyo');
    expect(groups.first.isSelectable, isTrue);
    expect(groups.last.isSelectable, isFalse);
    expect(groups.last.proxies, ['Tokyo', 'Seoul']);
  });
}