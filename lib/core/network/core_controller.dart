abstract interface class CoreController {
  Future<CoreStatus> start({String? configJson});
  Future<CoreStatus> reload(String configJson);
  Future<CoreStatus> stop();
  Future<CoreStatus> status();
  Future<TrafficSnapshot> queryTraffic();
  Future<int?> delayTest(String outbound);
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
