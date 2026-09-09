abstract interface class CoreController {
  String? get lastError;

  Future<CoreStatus> start({String? configJson});
  Future<CoreStatus> reload(String configJson);
  Future<CoreStatus> stop();
  Future<CoreStatus> status();
  Future<String> coreVersion();
  Future<TrafficSnapshot> queryTraffic();
  Future<int?> delayTest(String outbound);
  Future<bool> selectOutbound(String group, String outbound);
}

class TrafficSnapshot {
  const TrafficSnapshot({required this.uplinkBytes, required this.downlinkBytes});

  final int uplinkBytes;
  final int downlinkBytes;
}

enum CoreStatus {
  stopped,
  starting,
  running,
  permissionRequired,
  unavailable,
}
