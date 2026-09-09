import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leopard_cat/core/network/android_core_controller.dart';
import 'package:leopard_cat/core/network/core_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('leopard_cat/test-core');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'queryTraffic' => <String, Object?>{
            'uplink_bytes': 128,
            'downlink_bytes': 512,
          },
        'delayTest' => 86,
        'selectOutbound' => true,
        'coreVersion' => '1.14.0',
        _ => 'stopped',
      };
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('sends config through start and reload', () async {
    final controller = AndroidCoreController(channel: channel);

    await controller.start(configJson: '{"outbounds":[]}');
    await controller.reload('{"outbounds":[{"tag":"DIRECT"}]}');

    expect(calls.map((call) => call.method), ['start', 'reload']);
    expect((calls[0].arguments as Map)['config'], '{"outbounds":[]}');
  });

  test('decodes traffic and delay test results', () async {
    final controller = AndroidCoreController(channel: channel);

    final traffic = await controller.queryTraffic();
    final delay = await controller.delayTest('Proxy');

    expect(traffic.uplinkBytes, 128);
    expect(traffic.downlinkBytes, 512);
    expect(delay, 86);
    expect(calls.last.arguments, {'outbound': 'Proxy'});
  });

  test('reads the native sing-box version', () async {
    final controller = AndroidCoreController(channel: channel);

    expect(await controller.coreVersion(), '1.14.0');
    expect(calls.single.method, 'coreVersion');
  });

  test('selects an outbound in a proxy group', () async {
    final controller = AndroidCoreController(channel: channel);

    expect(await controller.selectOutbound('Global', 'Tokyo'), isTrue);
    expect(calls.single.method, 'selectOutbound');
    expect(calls.single.arguments, {'group': 'Global', 'outbound': 'Tokyo'});
  });

  test('decodes native status errors', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') {
        return <String, Object?>{
          'status': 'unavailable',
          'error': 'start or reload service failed',
        };
      }
      return 'stopped';
    });
    final controller = AndroidCoreController(channel: channel);

    expect(await controller.status(), CoreStatus.unavailable);
    expect(controller.lastError, 'start or reload service failed');
  });
}
