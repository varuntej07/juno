import '../config/environment.dart';

class ApiEndpoints {
  ApiEndpoints._();

  static String get baseUrl => Environment.current.apiBaseUrl;

  // REST endpoints
  static String get chat => '$baseUrl/chat';
  static String get memories => '$baseUrl/memories';
  static String get reminders => '$baseUrl/reminders';
  static String get nutritionScan => '$baseUrl/nutrition/scan';
  static String get nutritionAnalyze => '$baseUrl/nutrition/analyze';
  static String get nutritionProfile => '$baseUrl/nutrition/profile';

  // Device / push notification token registration
  static String get deviceRegister => '$baseUrl/devices/register';

  // Voice session returns LiveKit room token for the Flutter client
  static String get voiceToken => '$baseUrl/voice/token';
}
