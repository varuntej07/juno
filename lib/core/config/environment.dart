import 'dev_targets.dart';

enum Env { dev, staging, prod }

class EnvironmentConfig {
  final Env env;
  final String apiBaseUrl;
  final String wsBaseUrl;
  final String firebaseProjectId;
  final String googleServerClientId;

  const EnvironmentConfig({
    required this.env,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.firebaseProjectId,
    required this.googleServerClientId,
  });
}

class Environment {
  Environment._();

  static const String _envValue = String.fromEnvironment('ENV', defaultValue: 'dev');

  static Env get _env {
    switch (_envValue) {
      case 'prod':
        return Env.prod;
      case 'staging':
        return Env.staging;
      default:
        return Env.dev;
    }
  }

  static EnvironmentConfig get current {
    switch (_env) {
      case Env.prod:
        return const EnvironmentConfig(
          env: Env.prod,
          // Set after first Cloud Run deploy — copy the URL printed by deploy.sh
          apiBaseUrl: 'https://juno-backend-wo3gl4yhlq-uc.a.run.app',
          wsBaseUrl: 'wss://juno-backend-wo3gl4yhlq-uc.a.run.app',
          firebaseProjectId: 'juno-prod',
          googleServerClientId: '620715294422-15h8gdqn7ii0b419ksfrf8u7fgghltoi.apps.googleusercontent.com',
        );
      case Env.staging:
        return const EnvironmentConfig(
          env: Env.staging,
          apiBaseUrl: 'https://staging.api.juno-app.com',
          wsBaseUrl: 'wss://staging.api.juno-app.com',
          firebaseProjectId: 'juno-staging',
          googleServerClientId: '620715294422-15h8gdqn7ii0b419ksfrf8u7fgghltoi.apps.googleusercontent.com',
        );
      case Env.dev:
        // Controlled by lib/core/config/dev_targets.dart
        // Flip isPhysicalDeviceTest / isEmulatorTest there to switch targets
        return EnvironmentConfig(
          env: Env.dev,
          apiBaseUrl: DevTargets.devApiBaseUrl,
          wsBaseUrl: DevTargets.devWsBaseUrl,
          firebaseProjectId: 'juno-dev',
          googleServerClientId: '620715294422-15h8gdqn7ii0b419ksfrf8u7fgghltoi.apps.googleusercontent.com',
        );
    }
  }

  static bool get isDev => _env == Env.dev;
  static bool get isProd => _env == Env.prod;

  static bool get hasConfiguredApi =>
      !current.apiBaseUrl.contains('PLACEHOLDER_');

  static bool get hasConfiguredVoiceGateway =>
      !current.wsBaseUrl.contains('PLACEHOLDER_');
}
