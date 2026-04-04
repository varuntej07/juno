class AppConstants {
  AppConstants._();

  // Timeouts
  static const apiConnectTimeout = Duration(seconds: 10);
  static const apiReadTimeout = Duration(seconds: 30);
  static const apiWriteTimeout = Duration(seconds: 30);
  static const webSocketPingInterval = Duration(seconds: 15);
  static const webSocketReconnectDelay = Duration(seconds: 3);
  static const voiceSessionTimeout = Duration(minutes: 8);
  static const silenceDetectionTimeout = Duration(seconds: 3);

  // Retries
  static const maxApiRetries = 3;
  static const retryBaseDelay = Duration(seconds: 1);

  // UI
  static const animationDuration = Duration(milliseconds: 300);
  static const micButtonSize = 72.0;
  static const maxResponseHistoryItems = 50;

  // Firestore collections
  static const memoriesCollection = 'memories';
  static const remindersCollection = 'reminders';
  static const nutritionLogsCollection = 'nutrition_logs';
  static const calendarCacheCollection = 'calendar_cache';
  static const usersCollection = 'users';
}
