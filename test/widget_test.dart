// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leopard_cat/data/clash/clash_to_singbox_transformer.dart';
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
}
