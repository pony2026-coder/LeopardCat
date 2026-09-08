import 'package:flutter/services.dart';

import 'core_controller.dart';

class AndroidCoreController implements CoreController {
  AndroidCoreController({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('leopard_cat/core');

  final MethodChannel _channel;

  @override
  Future<CoreStatus> start({String? configJson}) async {
    final result = await _channel.invokeMethod<String>(
      'start',
      configJson == null ? null : {'config': configJson},
    );
    return _statusFromValue(result);
  }

  @override
  Future<CoreStatus> reload(String configJson) async {
    final result = await _channel.invokeMethod<String>(
      'reload',
      {'config': configJson},
    );
    return _statusFromValue(result);
  }

  @override
  Future<CoreStatus> stop() async {
    final result = await _channel.invokeMethod<String>('stop');
    return _statusFromValue(result);
  }

  @override
  Future<CoreStatus> status() async {
    final result = await _channel.invokeMethod<String>('status');
    return _statusFromValue(result);
  }

  @override
  Future<TrafficSnapshot> queryTraffic() async {
    final result = await _channel.invokeMapMethod<String, Object?>('queryTraffic');
    return TrafficSnapshot(
      uplinkBytes: _intValue(result?['uplink_bytes']),
      downlinkBytes: _intValue(result?['downlink_bytes']),
    );
  }

  @override
  Future<int?> delayTest(String outbound) async {
    return _channel.invokeMethod<int>('delayTest', {'outbound': outbound});
  }

  CoreStatus _statusFromValue(String? value) {
    return switch (value) {
      'starting' => CoreStatus.starting,
      'running' => CoreStatus.running,
      'permission_required' => CoreStatus.permissionRequired,
      'unavailable' => CoreStatus.unavailable,
      _ => CoreStatus.stopped,
    };
  }

  int _intValue(Object? value) {
    return value is int ? value : int.tryParse('$value') ?? 0;
  }
}
