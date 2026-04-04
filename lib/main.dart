import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/config/environment.dart';
import 'core/config/firebase_config.dart';
import 'core/errors/error_handler.dart';
import 'core/logging/app_logger.dart';
import 'di/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final firebaseReady = await FirebaseConfig.initialize();

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

  runApp(MultiProvider(providers: buildProviders(), child: const JunoApp()));
}
