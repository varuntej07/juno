import 'app_logger.dart';

class LatencyTracker {
  LatencyTracker._();

  static Future<T> track<T>(
    String operationName,
    Future<T> Function() operation,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await operation();
      stopwatch.stop();
      AppLogger.info(
        '$operationName completed',
        tag: 'Latency',
        metadata: {'duration_ms': stopwatch.elapsedMilliseconds},
      );
      return result;
    } catch (e) {
      stopwatch.stop();
      AppLogger.error(
        '$operationName failed after ${stopwatch.elapsedMilliseconds}ms',
        error: e,
        tag: 'Latency',
      );
      rethrow;
    }
  }
}
