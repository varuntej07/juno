enum VoiceSessionStatus {
  disconnected,
  connecting,
  ready,
  listening,
  processing,
  speaking,
  ended,
  error,
}

class VoiceServerEvent {
  final String type;
  final String? sessionId;
  final String? message;
  final String? text;
  final String? audioBase64;
  final String? mimeType;
  final int? sampleRateHertz;
  final String? toolName;
  final Map<String, dynamic>? payload;

  const VoiceServerEvent({
    required this.type,
    this.sessionId,
    this.message,
    this.text,
    this.audioBase64,
    this.mimeType,
    this.sampleRateHertz,
    this.toolName,
    this.payload,
  });

  factory VoiceServerEvent.fromJson(Map<String, dynamic> json) {
    return VoiceServerEvent(
      type: json['type'] as String? ?? 'unknown',
      sessionId: json['sessionId'] as String?,
      message: json['message'] as String?,
      text: json['text'] as String?,
      audioBase64: json['audioBase64'] as String?,
      mimeType: json['mimeType'] as String?,
      sampleRateHertz: json['sampleRateHertz'] as int?,
      toolName: json['toolName'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }
}

class VoiceSessionConfig {
  final String userId;
  final String? locale;
  final String? voiceId;
  final String? systemPrompt;

  const VoiceSessionConfig({
    required this.userId,
    this.locale,
    this.voiceId,
    this.systemPrompt,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        if (locale != null) 'locale': locale,
        if (voiceId != null) 'voiceId': voiceId,
        if (systemPrompt != null) 'systemPrompt': systemPrompt,
      };
}
