class UserSettings {
  final bool wakeWordEnabled;
  final bool ttsEnabled;
  final int defaultReminderLeadMinutes;

  const UserSettings({
    required this.wakeWordEnabled,
    required this.ttsEnabled,
    required this.defaultReminderLeadMinutes,
  });

  factory UserSettings.defaults() {
    return const UserSettings(
      wakeWordEnabled: false,
      ttsEnabled: true,
      defaultReminderLeadMinutes: 10,
    );
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      wakeWordEnabled: json['wake_word_enabled'] as bool? ?? false,
      ttsEnabled: json['tts_enabled'] as bool? ?? true,
      defaultReminderLeadMinutes: json['default_reminder_lead_minutes'] as int? ?? 10,
    );
  }

  Map<String, dynamic> toJson() => {
        'wake_word_enabled': wakeWordEnabled,
        'tts_enabled': ttsEnabled,
        'default_reminder_lead_minutes': defaultReminderLeadMinutes,
      };

  UserSettings copyWith({
    bool? wakeWordEnabled,
    bool? ttsEnabled,
    int? defaultReminderLeadMinutes,
  }) {
    return UserSettings(
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      defaultReminderLeadMinutes:
          defaultReminderLeadMinutes ?? this.defaultReminderLeadMinutes,
    );
  }
}

class UserModel {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final UserSettings settings;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final String? timezone;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.settings,
    required this.createdAt,
    required this.lastActiveAt,
    this.timezone,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String,
      displayName: json['display_name'] as String,
      email: json['email'] as String,
      photoUrl: json['photo_url'] as String?,
      settings: UserSettings.fromJson(
        json['settings'] as Map<String, dynamic>? ?? {},
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      lastActiveAt: DateTime.parse(json['last_active_at'] as String),
      timezone: json['timezone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'display_name': displayName,
        'email': email,
        'photo_url': photoUrl,
        'settings': settings.toJson(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'last_active_at': lastActiveAt.toUtc().toIso8601String(),
        'timezone': timezone,
      };

  UserModel copyWith({
    String? displayName,
    String? email,
    String? photoUrl,
    UserSettings? settings,
    DateTime? lastActiveAt,
    String? timezone,
  }) {
    return UserModel(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      settings: settings ?? this.settings,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      timezone: timezone ?? this.timezone,
    );
  }
}
