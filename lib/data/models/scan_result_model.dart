class ScanQuestion {
  final String id;
  final String text;
  final String inputType; // "select" | "text" | "number" | "boolean"
  final List<String> options;

  const ScanQuestion({
    required this.id,
    required this.text,
    required this.inputType,
    this.options = const [],
  });

  factory ScanQuestion.fromMap(Map<String, dynamic> map) {
    return ScanQuestion(
      id: map['id'] as String,
      text: map['text'] as String,
      inputType: map['input_type'] as String? ?? 'text',
      options: List<String>.from(map['options'] as List? ?? []),
    );
  }
}

class ScanResultModel {
  final String scanId;
  final String detectedType;
  final List<String> detectedItems;
  final double confidence;
  final bool needsClarification;
  final List<ScanQuestion> clarifyingQuestions;

  const ScanResultModel({
    required this.scanId,
    required this.detectedType,
    required this.detectedItems,
    required this.confidence,
    required this.needsClarification,
    required this.clarifyingQuestions,
  });

  factory ScanResultModel.fromMap(Map<String, dynamic> map) {
    return ScanResultModel(
      scanId: map['scan_id'] as String,
      detectedType: map['detected_type'] as String? ?? 'unknown',
      detectedItems: List<String>.from(map['detected_items'] as List? ?? []),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      needsClarification: map['needs_clarification'] as bool? ?? true,
      clarifyingQuestions: (map['clarifying_questions'] as List? ?? [])
          .map((q) => ScanQuestion.fromMap(q as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NutritionAnalysisModel {
  final String nutritionLogId;
  final String foodName;
  final Map<String, double> macros;
  final String recommendation; // "eat" | "moderate" | "skip"
  final String verdictReason;
  final List<String> concerns;

  const NutritionAnalysisModel({
    required this.nutritionLogId,
    required this.foodName,
    required this.macros,
    required this.recommendation,
    required this.verdictReason,
    required this.concerns,
  });

  factory NutritionAnalysisModel.fromMap(Map<String, dynamic> map) {
    final rawMacros = map['macros'] as Map<String, dynamic>? ?? {};
    return NutritionAnalysisModel(
      nutritionLogId: map['nutrition_log_id'] as String? ?? '',
      foodName: map['food_name'] as String? ?? 'Unknown Food',
      macros: rawMacros.map((k, v) => MapEntry(k, (v as num).toDouble())),
      recommendation: map['recommendation'] as String? ?? 'moderate',
      verdictReason: map['verdict_reason'] as String? ?? '',
      concerns: List<String>.from(map['concerns'] as List? ?? []),
    );
  }
}
