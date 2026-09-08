abstract interface class CoreController {
  Future<CoreStatus> start({String? configJson});
  Future<CoreStatus> reload(String configJson);
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
