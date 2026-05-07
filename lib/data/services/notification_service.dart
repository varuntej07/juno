import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/api_client.dart';

/// Payload emitted when the user taps an engagement notification.
class EngagementTapPayload {
  final String engagementId;
  final String initialMessage;
  final String agentContext;

  const EngagementTapPayload({
    required this.engagementId,
    required this.initialMessage,
    required this.agentContext,
  });
}

/// Payload emitted when the user taps a scheduled agent nudge notification.
class AgentNudgeTapPayload {
  final String agentId;
  final String chatOpener;

  const AgentNudgeTapPayload({
    required this.agentId,
    required this.chatOpener,
  });
}

const _tag = 'NotificationService';

/// Android notification channel used for all Aura notifications.
/// Must match the `channel_id` sent by the backend (`aura_default`).
const _kAndroidChannelId = 'aura_default';
const _kAndroidChannelName = 'Aura Notifications';

/// Centralized FCM notification service.
///
/// Call [initialize] once after the user authenticates.  It:
/// 1. Requests OS notification permission (iOS 14+ / Android 13+).
/// 2. Retrieves the FCM token and registers it with the backend.
/// 3. Listens for token refreshes and re-registers automatically.
/// 4. Handles foreground messages (shows a local system notification).
/// 5. Handles background → foreground tap navigation.
/// 6. Creates the Android notification channel on first launch.
///
/// The service is idempotent — calling [initialize] more than once is safe.
class NotificationService {
  final ApiClient _apiClient;

  NotificationService({required ApiClient apiClient})
      : _apiClient = apiClient;

  // ── State ─────────────────────────────────────────────────────────────────

  bool _initialized = false;
  String? _userId;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  final _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  final _engagementTapController =
      StreamController<EngagementTapPayload>.broadcast();
  final _agentNudgeTapController =
      StreamController<AgentNudgeTapPayload>.broadcast();

  /// Emits when the user taps an engagement notification.
  Stream<EngagementTapPayload> get engagementTapStream =>
      _engagementTapController.stream;

  /// Emits when the user taps a scheduled agent nudge notification.
  Stream<AgentNudgeTapPayload> get agentNudgeTapStream =>
      _agentNudgeTapController.stream;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Initialize FCM for the signed-in [userId].
  ///
  /// Safe to call multiple times; subsequent calls update the stored [userId]
  /// in case the account changed (unlikely but handled).
  Future<void> initialize(String userId) async {
    _userId = userId;

    if (_initialized) {
      // Already running — just ensure the current token is registered in
      // case the user signed in with a different account.
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) unawaited(_registerToken(token));
      return;
    }
    _initialized = true;

    // ── 1. Request OS permission ──────────────────────────────────────────
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      AppLogger.warning(
        'Notification permission denied — FCM will not deliver alerts',
        tag: _tag,
        metadata: {'userId': userId},
      );
      return;
    }

    AppLogger.info(
      'Notification permission granted',
      tag: _tag,
      metadata: {
        'status': settings.authorizationStatus.name,
        'userId': userId,
      },
    );

    // ── 2. Create Android notification channel ───────────────────────────
    await _createAndroidChannel();

    // ── 3. Get current token and register with backend ───────────────────
    final token = await FirebaseMessaging.instance.getToken();
    AppLogger.info(
      'FCM token retrieved',
      tag: _tag,
      metadata: {'tokenPreview': token?.substring(0, 20)},
    );
    if (token != null) unawaited(_registerToken(token));

    // ── 4. Auto-register on token refresh ────────────────────────────────
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((newToken) {
      AppLogger.info(
        'FCM token refreshed — re-registering',
        tag: _tag,
        metadata: {'tokenPreview': newToken.substring(0, 20)},
      );
      unawaited(_registerToken(newToken));
    });

    // ── 5. Foreground messages → show local notification ─────────────────
    await _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );

    // ── 6. App opened from background via notification tap ───────────────
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // ── 7. App opened from terminated state via notification tap ─────────
    final initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// Call on sign-out to clean up listeners.
  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    _userId = null;
    _initialized = false;
    await _engagementTapController.close();
    await _agentNudgeTapController.close();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _registerToken(String token) async {
    final uid = _userId;
    if (uid == null) return;

    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'web';

    final result = await _apiClient.post(
      '/devices/register',
      {'token': token, 'platform': platform},
      (json) => json,
    );

    result.when(
      success: (_) => AppLogger.info(
        'FCM token registered with backend',
        tag: _tag,
        metadata: {'platform': platform, 'tokenPreview': token.substring(0, 20)},
      ),
      failure: (error) => AppLogger.error(
        'Failed to register FCM token',
        error: error,
        tag: _tag,
      ),
    );
  }

  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      _kAndroidChannelId,
      _kAndroidChannelName,
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    AppLogger.debug(
      'Android notification channel created',
      tag: _tag,
      metadata: {'channelId': _kAndroidChannelId},
    );
  }

  /// Show a system notification while the app is in the foreground.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    AppLogger.info(
      'FCM foreground message received',
      tag: _tag,
      metadata: {
        'messageId': message.messageId,
        'title': notification.title,
        'notificationType': message.data['notification_type'],
      },
    );

    // Let FCM render the native OS banner even while the app is foregrounded.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// Handle notification tap (from background or terminated state).
  void _handleNotificationTap(RemoteMessage message) {
    final notificationType = message.data['notification_type'] as String?;
    AppLogger.info(
      'Notification tapped',
      tag: _tag,
      metadata: {
        'messageId': message.messageId,
        'notificationType': notificationType,
        'reminderId': message.data['reminder_id'],
      },
    );

    if (notificationType == 'engagement') {
      final engagementId = message.data['engagement_id'] as String? ?? '';
      final initialMessage = message.data['initial_message'] as String? ?? '';
      final agentContext = message.data['agent_context'] as String? ?? '';

      if (engagementId.isNotEmpty && initialMessage.isNotEmpty) {
        _engagementTapController.add(EngagementTapPayload(
          engagementId: engagementId,
          initialMessage: initialMessage,
          agentContext: agentContext,
        ));
      }
    } else if (notificationType == 'agent_nudge') {
      final agentId = message.data['agent_id'] as String? ?? '';
      final chatOpener = message.data['chat_opener'] as String? ?? '';

      if (agentId.isNotEmpty) {
        _agentNudgeTapController.add(AgentNudgeTapPayload(
          agentId: agentId,
          chatOpener: chatOpener,
        ));
      }
    }
  }

  /// Convenience accessor used for testing / debug screens.
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();
}
