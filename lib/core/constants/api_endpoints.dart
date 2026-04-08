import '../config/environment.dart';

class ApiEndpoints {
  ApiEndpoints._();

  static String get baseUrl => Environment.current.apiBaseUrl;
  static String get wsBaseUrl => Environment.current.wsBaseUrl;

  // REST endpoints
  static String get chat => '$baseUrl/chat';
  static String get memories => '$baseUrl/memories';
  static String get reminders => '$baseUrl/reminders';
  static String get nutritionAnalyze => '$baseUrl/nutrition/analyze';

  // Device / push notification token registration
  static String get deviceRegister => '$baseUrl/devices/register';

  // WebSocket
  static String get voiceStream => '$wsBaseUrl/voice/stream';
}
