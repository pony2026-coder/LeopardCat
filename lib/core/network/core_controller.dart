abstract interface class CoreController {
  Future<CoreStatus> start();
  Future<CoreStatus> stop();
  Future<CoreStatus> status();
}

enum CoreStatus {
  stopped,
  starting,
  running,
  permissionRequired,
  unavailable,
}
