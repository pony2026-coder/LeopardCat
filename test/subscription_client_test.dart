import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leopard_cat/data/subscription/subscription_client.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => server.close(force: true));

  test('downloads a successful HTTP subscription response', () async {
    unawaited(server.forEach((request) async {
      request.response.write('proxies: []');
      await request.response.close();
    }));
    final client = HttpSubscriptionClient(timeout: const Duration(seconds: 1));

    final content = await client.fetch(Uri.parse('http://${server.address.address}:${server.port}/sub'));

    expect(content, 'proxies: []');
  });

  test('reports a timeout when the subscription response stalls', () async {
    unawaited(server.forEach((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      request.response.write('proxies: []');
      await request.response.close();
    }));
    final client = HttpSubscriptionClient(timeout: const Duration(milliseconds: 10));

    expect(
      () => client.fetch(Uri.parse('http://${server.address.address}:${server.port}/sub')),
      throwsA(
        isA<SubscriptionException>().having((error) => error.message, 'message', '下载订阅超时'),
      ),
    );
  });

  test('rejects non-HTTP subscription URLs', () async {
    final client = HttpSubscriptionClient();

    expect(
      () => client.fetch(Uri.parse('file:///tmp/sub.yaml')),
      throwsA(isA<SubscriptionException>()),
    );
  });
}