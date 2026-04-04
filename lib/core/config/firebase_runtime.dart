import 'package:firebase_core/firebase_core.dart';

class FirebaseRuntime {
  FirebaseRuntime._();

  static bool get hasApp {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
