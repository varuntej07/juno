import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_response.dart';

// SSE stream events

sealed class ChatStreamEvent {}

class TextDeltaEvent extends ChatStreamEvent {
  final String delta;
  TextDeltaEvent(this.delta);
}

class ToolThinkingEvent extends ChatStreamEvent {
  final String message;
  ToolThinkingEvent(this.message);
}

class ClarificationUiEvent extends ChatStreamEvent {
  final String clarificationId;
  final String question;
  final List<String> options;
  final bool multiSelect;
  ClarificationUiEvent({
    required this.clarificationId,
    required this.question,
    required this.options,
    required this.multiSelect,
  });
}

class DoneEvent extends ChatStreamEvent {
  final Map<String, dynamic>? metadata;
  final bool awaitingClarification;
  DoneEvent({this.metadata, this.awaitingClarification = false});
}

class ErrorStreamEvent extends ChatStreamEvent {
  final String message;
  ErrorStreamEvent(this.message);
}

/// Structured data returned by the backend when a set_reminder tool call
/// succeeds. Used to render the inline ReminderCard in chat.
class ReminderPayload {
  final String reminderId;
  final String message;
  final DateTime triggerAt;
  final String status;
  final String priority;

  const ReminderPayload({
    required this.reminderId,
    required this.message,
    required this.triggerAt,
    required this.status,
    required this.priority,
  });

  factory ReminderPayload.fromJson(Map<String, dynamic> json) {
    return ReminderPayload(
      reminderId: json['reminder_id'] as String? ?? '',
      message: json['message'] as String? ?? '',
      triggerAt: DateTime.parse(json['trigger_at'] as String),
      status: json['status'] as String? ?? 'pending',
      priority: json['priority'] as String? ?? 'normal',
    );
  }

  Map<String, dynamic> toJson() => {
        'reminder_id': reminderId,
        'message': message,
        'trigger_at': triggerAt.toUtc().toIso8601String(),
        'status': status,
        'priority': priority,
      };

  String toJsonString() => jsonEncode(toJson());

  static ReminderPayload? tryFromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return ReminderPayload.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

class ChatResponse {
  final String text;
  final String? intent;
  final Map<String, dynamic>? metadata;

  /// Non-null when the assistant called the set_reminder tool this turn.
  final ReminderPayload? reminderPayload;

  const ChatResponse({
    required this.text,
    this.intent,
    this.metadata,
    this.reminderPayload,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'] as Map<String, dynamic>?;
    final reminderJson = meta?['reminder'] as Map<String, dynamic>?;
    return ChatResponse(
      text: json['text'] as String? ?? '',
      intent: json['intent'] as String?,
      metadata: meta,
      reminderPayload:
          reminderJson != null ? ReminderPayload.fromJson(reminderJson) : null,
    );
  }

  factory ChatResponse.stub(String message) {
    return ChatResponse(
      text: message,
      intent: 'stub',
    );
  }
}

class LambdaApiService {
  final ApiClient? _apiClient;
  final bool _useStub;

  LambdaApiService({ApiClient? apiClient, bool useStub = false})
      : _apiClient = apiClient,
        _useStub = useStub;

  Future<Result<ChatResponse>> sendMessage(
    String message,
    String userId, {
    List<Map<String, String>> history = const [],
    String? sessionId,
    // Passed as the Firestore doc ID for the query log — makes retries idempotent
    // (same UUID → upsert instead of new insert, no duplicate log entries).
    String? clientMessageId,
  }) async {
    if (_useStub || _apiClient == null) {
      AppLogger.info(
        'LambdaApiService stub: sendMessage',
        tag: 'LambdaApiService',
        metadata: {
          'message': message,
          'history_len': history.length,
          'sessionId': sessionId,
        },
      );
      await Future.delayed(const Duration(milliseconds: 800));
      return Result.success(
        ChatResponse.stub(
          'Not connected — Lambda endpoint not configured yet. '
          'Your message: "$message"',
        ),
      );
    }

    return _apiClient.post(
      '/chat',
      {
        'message': message,
        'user_id': userId,
        if (sessionId != null) 'session_id': sessionId,
        if (history.isNotEmpty) 'history': history,
        if (clientMessageId != null) 'client_message_id': clientMessageId,
      },
      ChatResponse.fromJson,
      timeout: AppConstants.chatRequestTimeout,
    );
  }

  /// Streams a chat message via SSE. Yields [ChatStreamEvent] objects as they
  /// arrive; the stream completes after a [DoneEvent] or [ErrorStreamEvent].
  Stream<ChatStreamEvent> sendMessageStream(
    String message,
    String userId, {
    List<Map<String, String>> history = const [],
    String? sessionId,
    String? clientMessageId,
  }) async* {
    if (_useStub || _apiClient == null) {
      await Future.delayed(const Duration(milliseconds: 600));
      const words = ['This ', 'is ', 'a ', 'stub ', 'response.'];
      for (final w in words) {
        yield TextDeltaEvent(w);
        await Future.delayed(const Duration(milliseconds: 120));
      }
      yield DoneEvent(metadata: const {'tool_names': []});
      return;
    }

    try {
      await for (final line in _apiClient.streamPost('/chat', {
        'message': message,
        'user_id': userId,
        if (sessionId != null) 'session_id': sessionId,
        if (history.isNotEmpty) 'history': history,
        if (clientMessageId != null) 'client_message_id': clientMessageId,
      })) {
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final event = _parseStreamEvent(json);
          if (event != null) yield event;
        } catch (e) {
          AppLogger.warning('SSE parse error: $e', tag: 'LambdaApiService');
        }
      }
    } catch (e, st) {
      AppLogger.error('SSE stream error', error: e, stackTrace: st, tag: 'LambdaApiService');
      yield ErrorStreamEvent(AppException.unexpected(e.toString()).message);
    }
  }

  static ChatStreamEvent? _parseStreamEvent(Map<String, dynamic> json) {
    switch (json['type'] as String?) {
      case 'text_delta':
        return TextDeltaEvent(json['delta'] as String? ?? '');
      case 'tool_thinking':
        return ToolThinkingEvent(json['message'] as String? ?? '');
      case 'clarification_ui':
        return ClarificationUiEvent(
          clarificationId: json['clarification_id'] as String? ?? '',
          question: json['question'] as String? ?? '',
          options: (json['options'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
          multiSelect: json['multi_select'] as bool? ?? false,
        );
      case 'done':
        final meta = json['metadata'] as Map<String, dynamic>?;
        return DoneEvent(
          metadata: meta,
          awaitingClarification: meta?['awaiting_clarification'] as bool? ?? false,
        );
      case 'error':
        return ErrorStreamEvent(json['message'] as String? ?? 'Unknown error');
      default:
        return null;
    }
  }

  /// Called when the user taps an engagement notification.
  /// Marks the engagement as responded on the backend so pending re-engagement
  /// Cloud Tasks are cancelled. Fire-and-forget — failures are logged, not thrown.
  Future<void> markEngagementResponded(String engagementId) async {
    if (_useStub || _apiClient == null) return;
    final result = await _apiClient.post(
      '/internal/engage/responded',
      {'engagement_id': engagementId},
      (json) => json,
    );
    result.when(
      success: (_) => AppLogger.info(
        'Engagement responded acknowledged',
        tag: 'LambdaApiService',
        metadata: {'engagementId': engagementId},
      ),
      failure: (e) => AppLogger.warning(
        'Failed to mark engagement responded',
        tag: 'LambdaApiService',
        metadata: {'engagementId': engagementId, 'error': e.message},
      ),
    );
  }

  Future<Result<Map<String, dynamic>>> analyzeNutrition(
    String ocrText,
    String userId,
  ) async {
    if (_useStub || _apiClient == null) {
      AppLogger.info('LambdaApiService stub: analyzeNutrition', tag: 'LambdaApiService');
      return Result.failure(
        AppException(
          code: ErrorCode.unexpected,
          message: 'Nutrition analysis not yet available.',
        ),
      );
    }

    return _apiClient.post(
      '/nutrition/analyze',
      {'ocr_text': ocrText, 'user_id': userId},
      (json) => json,
    );
  }
}
