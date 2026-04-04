import 'package:firebase_core/firebase_core.dart';
import '../logging/app_logger.dart';
import 'firebase_runtime.dart';

class FirebaseConfig {
  FirebaseConfig._();

  static Object? _lastInitializationError;

  static Future<bool> initialize() async {
    if (FirebaseRuntime.hasApp) {
      return true;
    }

    try {
      await Firebase.initializeApp();
      _lastInitializationError = null;
      AppLogger.info('Firebase initialized', tag: 'FirebaseConfig');
      return true;
    } catch (e, st) {
      _lastInitializationError = e;
      if (_isMissingConfigurationError(e)) {
        AppLogger.warning(
          'Firebase config is missing; continuing without Firebase services',
          tag: 'FirebaseConfig',
        );
      } else {
        AppLogger.warning(
          'Firebase unavailable; continuing without Firebase services',
          tag: 'FirebaseConfig',
          metadata: {'error': e.toString()},
        );
        AppLogger.error(
          'Firebase initialization failed',
          error: e,
          stackTrace: st,
          tag: 'FirebaseConfig',
        );
      }
      return false;
    }
  }

  static bool get isInitialized => FirebaseRuntime.hasApp;

  static Object? get lastInitializationError => _lastInitializationError;

  static bool _isMissingConfigurationError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('failed to load firebaseoptions from resource') ||
        message.contains('google-services.json') ||
        message.contains('google-service-info.plist');
  }
}
