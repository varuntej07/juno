import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error, network }

class AppLogger {
  AppLogger._();

  static void info(
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    _log(LogLevel.info, message, tag: tag, metadata: metadata);
  }

  static void warning(
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    _log(LogLevel.warning, message, tag: tag, metadata: metadata);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    _log(LogLevel.error, message, tag: tag, metadata: metadata);
    if (kDebugMode) {
      if (error != null) debugPrint('  Error: $error');
      if (stackTrace != null) debugPrint('  Stack: $stackTrace');
    } else {
      if (error != null) {
        FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: message);
      }
    }
  }

  static void network(
    String method,
    String url,
    int statusCode,
    Duration latency,
  ) {
    _log(
      LogLevel.network,
      '$method $url → $statusCode (${latency.inMilliseconds}ms)',
      tag: 'Network',
    );
  }

  static void _log(
    LogLevel level,
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    if (!kDebugMode) return;

    final timestamp = DateTime.now().toIso8601String();
    final tagStr = tag != null ? '[$tag]' : '';
    final levelStr = '[${level.name.toUpperCase()}]';
    final metaStr = metadata != null && metadata.isNotEmpty
        ? ' | ${metadata.entries.map((e) => '${e.key}=${e.value}').join(', ')}'
        : '';

    debugPrint('$timestamp $levelStr$tagStr $message$metaStr');
  }
}
