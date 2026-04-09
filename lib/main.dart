import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/config/environment.dart';
import 'core/config/firebase_config.dart';
import 'core/errors/error_handler.dart';
import 'core/logging/app_logger.dart';
import 'di/providers.dart';

/// FCM background message handler.
/// Must be a top-level function (Flutter / isolate constraint)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be re-initialized in background isolates
  await FirebaseConfig.initialize();
  AppLogger.info(
    'FCM background message received',
    tag: 'FCM',
    metadata: {
      'messageId': message.messageId,
      'notificationType': message.data['notification_type'],
    },
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final firebaseReady = await FirebaseConfig.initialize();

  // Register the background handler before runApp so FCM can wire it up during app startup
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  ErrorHandler.init();
  ErrorHandler.setEnvironment(Environment.current.env.name);

  if (firebaseReady && !Environment.isDev) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  }

  AppLogger.info(
    'Juno starting',
    tag: 'main',
    metadata: {
      'env': Environment.current.env.name,
      'firebase_ready': firebaseReady,
    },
  );

  final prefs = await SharedPreferences.getInstance();
  runApp(MultiProvider(providers: buildProviders(prefs), child: const JunoApp()));
}
