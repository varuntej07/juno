import '../services/lambda_api_service.dart';

enum ChatMessageChannel { text, voice }

enum MessageFeedback { liked, disliked }

enum MessageStatus { sent, error }

class ChatMessageModel {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final ChatMessageChannel channel;
  final MessageStatus status;
  final MessageFeedback? feedback;
  final String? errorReason;

  /// Null until the message is persisted to a SQLite session.
  final String? sessionId;

  /// Set when this message was pre-inserted from an FCM engagement tap.
  final String? engagementId;
  final String? engagementAgent;

  /// Non-null when this assistant message was produced by a set_reminder call.
  /// Drives the inline ReminderCard widget in chat.
  final ReminderPayload? reminderPayload;

  const ChatMessageModel({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    required this.channel,
    this.status = MessageStatus.sent,
    this.feedback,
    this.errorReason,
    this.sessionId,
    this.engagementId,
    this.engagementAgent,
    this.reminderPayload,
  });

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory ChatMessageModel.fromMap(Map<String, dynamic> map) {
    return ChatMessageModel(
      id: map['id'] as String,
      text: map['text'] as String,
      isUser: map['is_user'] as bool,
      timestamp: DateTime.parse(map['timestamp'] as String),
      channel: ChatMessageChannel.values.firstWhere(
        (c) => c.name == map['channel'],
        orElse: () => ChatMessageChannel.text,
      ),
      status: MessageStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => MessageStatus.sent,
      ),
      feedback: map['feedback'] == null
          ? null
          : MessageFeedback.values.firstWhere(
              (f) => f.name == map['feedback'],
              orElse: () => MessageFeedback.liked,
            ),
      errorReason: map['error_reason'] as String?,
      sessionId: map['session_id'] as String?,
      engagementId: map['engagement_id'] as String?,
      engagementAgent: map['engagement_agent'] as String?,
      reminderPayload: ReminderPayload.tryFromJsonString(
        map['reminder_json'] as String?,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'is_user': isUser,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'channel': channel.name,
        'status': status.name,
        if (feedback != null) 'feedback': feedback!.name,
        if (errorReason != null) 'error_reason': errorReason,
        if (sessionId != null) 'session_id': sessionId,
        if (engagementId != null) 'engagement_id': engagementId,
        if (engagementAgent != null) 'engagement_agent': engagementAgent,
        if (reminderPayload != null) 'reminder_json': reminderPayload!.toJsonString(),
      };

  /// Serialises to the `{role, content}` shape expected by the Claude /chat
  /// history parameter. Voice and text messages are both treated as plain
  /// conversational turns.
  Map<String, String> toHistoryTurn() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };

  // ── Value equality ────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  // ── copyWith ──────────────────────────────────────────────────────────────

  ChatMessageModel copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    ChatMessageChannel? channel,
    MessageStatus? status,
    MessageFeedback? Function()? feedback,
    String? Function()? errorReason,
    String? sessionId,
    String? engagementId,
    String? engagementAgent,
    ReminderPayload? Function()? reminderPayload,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      channel: channel ?? this.channel,
      status: status ?? this.status,
      feedback: feedback != null ? feedback() : this.feedback,
      errorReason: errorReason != null ? errorReason() : this.errorReason,
      sessionId: sessionId ?? this.sessionId,
      engagementId: engagementId ?? this.engagementId,
      engagementAgent: engagementAgent ?? this.engagementAgent,
      reminderPayload:
          reminderPayload != null ? reminderPayload() : this.reminderPayload,
    );
  }

  @override
  String toString() =>
      'ChatMessageModel(id: $id, isUser: $isUser, channel: ${channel.name}, status: ${status.name})';
}
