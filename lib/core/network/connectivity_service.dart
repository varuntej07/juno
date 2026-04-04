import 'package:connectivity_plus/connectivity_plus.dart';
import '../logging/app_logger.dart';

enum ConnectivityStatus { connected, disconnected }

class ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  Stream<ConnectivityStatus> get statusStream => _connectivity.onConnectivityChanged
      .map((results) => _mapResults(results));

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    final connected = results.any((r) => r != ConnectivityResult.none);
    AppLogger.info(
      'Connectivity check: ${connected ? 'connected' : 'disconnected'}',
      tag: 'ConnectivityService',
    );
    return connected;
  }

  ConnectivityStatus _mapResults(List<ConnectivityResult> results) {
    final status = results.any((r) => r != ConnectivityResult.none)
        ? ConnectivityStatus.connected
        : ConnectivityStatus.disconnected;
    AppLogger.info('Connectivity changed: ${status.name}', tag: 'ConnectivityService');
    return status;
  }
}
