// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leopard_cat/data/clash/clash_to_singbox_transformer.dart';
import 'package:leopard_cat/data/clash/proxy_group.dart';
import 'package:leopard_cat/data/profiles/profile_repository.dart';
import 'package:leopard_cat/main.dart';

void main() {
  testWidgets('renders the dashboard shell', (WidgetTester tester) async {
    await tester.pumpWidget(const LeopardCatApp());

    expect(find.text('控制台'), findsOneWidget);
    expect(find.text('服务未连接'), findsOneWidget);
  });

  testWidgets('shows global static resources in settings',
      (WidgetTester tester) async {
    const resource = StaticResource(
      kind: StaticResourceKind.geoip,
      tag: 'geoip-cn',
      url:
          'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SettingsPage(staticResources: [resource])),
      ),
    );

    expect(find.text('静态资源'), findsOneWidget);
    expect(find.text('1 项'), findsOneWidget);
    await tester.tap(find.text('GEOIP'));
    await tester.pumpAndSettle();

    expect(find.text('geoip-cn'), findsOneWidget);
    expect(find.text(resource.url), findsOneWidget);
  });

  testWidgets('groups provider files into proxy and rule pages',
      (WidgetTester tester) async {
    final now = DateTime(2026);
    final providers = [
      ProviderFile(
        name: 'proxy-source',
        kind: ProviderFileKind.proxy,
        url: 'https://example.com/proxy.yaml',
        content: 'proxies: []',
        updatedAt: now,
      ),
      ProviderFile(
        name: 'rule-source',
        kind: ProviderFileKind.rule,
        url: 'https://example.com/rule.yaml',
        content: 'payload: []',
        updatedAt: now,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProxyPage(
            groups: const <ClashProxyGroup>[],
            isLoading: false,
            providerFiles: providers,
            isConnected: false,
            selectedOutbounds: const {},
            outboundDelays: const {},
            testingOutbounds: const {},
            onDelayTest: (_) async {},
            onSelectOutbound: (_, __) async {},
            onViewProvider: (_) async {},
            onRefreshProvider: (file) async => file,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('订阅文件'));
    await tester.pumpAndSettle();
    expect(find.text('代理提供者'), findsOneWidget);
    expect(find.text('自定义规则集'), findsOneWidget);

    await tester.tap(find.text('代理提供者'));
    await tester.pumpAndSettle();
    expect(find.text('全部更新'), findsOneWidget);
    expect(find.text('proxy-source'), findsOneWidget);
    expect(find.text('rule-source'), findsNothing);
  });
}
