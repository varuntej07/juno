import 'dart:convert';

class ClarificationPayload {
  final String clarificationId;
  final String question;
  final List<String> options;
  final bool multiSelect;

  /// Null = unanswered (chips are tappable). Non-null = answered (read-only).
  final List<String>? selectedOptions;

  const ClarificationPayload({
    required this.clarificationId,
    required this.question,
    required this.options,
    this.multiSelect = false,
    this.selectedOptions,
  });

  bool get isAnswered => selectedOptions != null;

  factory ClarificationPayload.fromJson(Map<String, dynamic> json) {
    return ClarificationPayload(
      clarificationId: json['clarification_id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      multiSelect: json['multi_select'] as bool? ?? false,
      selectedOptions: (json['selected_options'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'clarification_id': clarificationId,
        'question': question,
        'options': options,
        'multi_select': multiSelect,
        if (selectedOptions != null) 'selected_options': selectedOptions,
      };

  String toJsonString() => jsonEncode(toJson());

  static ClarificationPayload? tryFromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return ClarificationPayload.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  ClarificationPayload copyWith({
    String? clarificationId,
    String? question,
    List<String>? options,
    bool? multiSelect,
    List<String>? Function()? selectedOptions,
  }) {
    return ClarificationPayload(
      clarificationId: clarificationId ?? this.clarificationId,
      question: question ?? this.question,
      options: options ?? this.options,
      multiSelect: multiSelect ?? this.multiSelect,
      selectedOptions:
          selectedOptions != null ? selectedOptions() : this.selectedOptions,
    );
  }
}
