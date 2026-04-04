import 'package:firebase_core/firebase_core.dart';
import '../logging/app_logger.dart';

class FirebaseConfig {
  FirebaseConfig._();

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      AppLogger.info('Firebase initialized', tag: 'FirebaseConfig');
    } catch (e, st) {
      AppLogger.error('Firebase initialization failed', error: e, stackTrace: st, tag: 'FirebaseConfig');
      rethrow;
    }
  }

  static bool get isInitialized {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }
}
