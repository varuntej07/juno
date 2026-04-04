enum Env { dev, staging, prod }

class EnvironmentConfig {
  final Env env;
  final String apiBaseUrl;
  final String wsBaseUrl;
  final String firebaseProjectId;

  const EnvironmentConfig({
    required this.env,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.firebaseProjectId,
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
          apiBaseUrl: 'https://PLACEHOLDER_PROD.execute-api.us-east-1.amazonaws.com/prod',
          wsBaseUrl: 'wss://PLACEHOLDER_PROD.execute-api.us-east-1.amazonaws.com/prod',
          firebaseProjectId: 'juno-prod',
        );
      case Env.staging:
        return const EnvironmentConfig(
          env: Env.staging,
          apiBaseUrl: 'https://PLACEHOLDER_STAGING.execute-api.us-east-1.amazonaws.com/staging',
          wsBaseUrl: 'wss://PLACEHOLDER_STAGING.execute-api.us-east-1.amazonaws.com/staging',
          firebaseProjectId: 'juno-staging',
        );
      case Env.dev:
        return const EnvironmentConfig(
          env: Env.dev,
          apiBaseUrl: 'https://PLACEHOLDER_DEV.execute-api.us-east-1.amazonaws.com/dev',
          wsBaseUrl: 'wss://PLACEHOLDER_DEV.execute-api.us-east-1.amazonaws.com/dev',
          firebaseProjectId: 'juno-dev',
        );
    }
  }

  static bool get isDev => _env == Env.dev;
  static bool get isProd => _env == Env.prod;
}
