enum ReminderStatus { pending, fired, dismissed, snoozed }

enum ReminderPriority { low, normal, urgent }

class ReminderModel {
  final String id;
  final String message;
  final DateTime triggerAt;
  final ReminderStatus status;
  final ReminderPriority priority;
  final String createdVia; // voice, text, notification_reply
  final int snoozeCount;
  final DateTime createdAt;
  final DateTime? firedAt;
  final DateTime? dismissedAt;

  const ReminderModel({
    required this.id,
    required this.message,
    required this.triggerAt,
    required this.status,
    required this.priority,
    required this.createdVia,
    required this.snoozeCount,
    required this.createdAt,
    this.firedAt,
    this.dismissedAt,
  });

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      id: json['id'] as String,
      message: json['message'] as String,
      triggerAt: DateTime.parse(json['trigger_at'] as String),
      status: ReminderStatus.values.byName(
        json['status'] as String? ?? 'pending',
      ),
      priority: ReminderPriority.values.byName(
        json['priority'] as String? ?? 'normal',
      ),
      createdVia: json['created_via'] as String? ?? 'text',
      snoozeCount: json['snooze_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      firedAt: json['fired_at'] != null
          ? DateTime.parse(json['fired_at'] as String)
          : null,
      dismissedAt: json['dismissed_at'] != null
          ? DateTime.parse(json['dismissed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'message': message,
        'trigger_at': triggerAt.toUtc().toIso8601String(),
        'status': status.name,
        'priority': priority.name,
        'created_via': createdVia,
        'snooze_count': snoozeCount,
        'created_at': createdAt.toUtc().toIso8601String(),
        'fired_at': firedAt?.toUtc().toIso8601String(),
        'dismissed_at': dismissedAt?.toUtc().toIso8601String(),
      };
}
