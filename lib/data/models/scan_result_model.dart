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
  final String foodCategory; // "fast food" | "grain" | "snack" | "protein" | etc.
  final double confidence;
  final bool needsClarification;
  final List<ScanQuestion> clarifyingQuestions;

  const ScanResultModel({
    required this.scanId,
    required this.detectedType,
    required this.detectedItems,
    required this.foodCategory,
    required this.confidence,
    required this.needsClarification,
    required this.clarifyingQuestions,
  });

  factory ScanResultModel.fromMap(Map<String, dynamic> map) {
    return ScanResultModel(
      scanId: map['scan_id'] as String,
      detectedType: map['detected_type'] as String? ?? 'unknown',
      detectedItems: List<String>.from(map['detected_items'] as List? ?? []),
      foodCategory: map['food_category'] as String? ?? '',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      needsClarification: map['needs_clarification'] as bool? ?? true,
      clarifyingQuestions: (map['clarifying_questions'] as List? ?? [])
          .map((q) => ScanQuestion.fromMap(q as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A single nutrient highlighted by Buddy — only the ones that matter for this
/// food + this user's goal. 2–4 per analysis, never all 7 macros blindly.
class KeyNutrient {
  final String name;       // "Protein" | "Calories" | "Sodium" | etc.
  final String value;      // "28g" | "820mg" | "420 kcal"
  final String context;    // "solid muscle recovery fuel" — plain English
  final String sentiment;  // "good" | "neutral" | "watch"

  const KeyNutrient({
    required this.name,
    required this.value,
    required this.context,
    required this.sentiment,
  });

  factory KeyNutrient.fromMap(Map<String, dynamic> map) {
    return KeyNutrient(
      name: map['name'] as String? ?? '',
      value: map['value'] as String? ?? '',
      context: map['context'] as String? ?? '',
      sentiment: map['sentiment'] as String? ?? 'neutral',
    );
  }
}

class NutritionAnalysisModel {
  final String nutritionLogId;
  final String foodName;
  final String headline;         // Buddy's immediate gut reaction (friend-voice one-liner)
  final Map<String, double> macros;
  final List<KeyNutrient> keyNutrients; // curated nutrients that matter for this food + goal
  final String recommendation;   // "eat" | "moderate" | "skip"
  final String verdictReason;
  final List<String> concerns;
  final List<String> pros;
  final List<String> cons;

  const NutritionAnalysisModel({
    required this.nutritionLogId,
    required this.foodName,
    required this.headline,
    required this.macros,
    required this.keyNutrients,
    required this.recommendation,
    required this.verdictReason,
    required this.concerns,
    required this.pros,
    required this.cons,
  });

  factory NutritionAnalysisModel.fromMap(Map<String, dynamic> map) {
    final rawMacros = map['macros'] as Map<String, dynamic>? ?? {};
    return NutritionAnalysisModel(
      nutritionLogId: map['nutrition_log_id'] as String? ?? '',
      foodName: map['food_name'] as String? ?? 'Unknown Food',
      headline: map['headline'] as String? ?? '',
      macros: rawMacros.map((k, v) => MapEntry(k, (v as num).toDouble())),
      keyNutrients: (map['key_nutrients'] as List? ?? [])
          .map((n) => KeyNutrient.fromMap(n as Map<String, dynamic>))
          .toList(),
      recommendation: map['recommendation'] as String? ?? 'moderate',
      verdictReason: map['verdict_reason'] as String? ?? '',
      concerns: List<String>.from(map['concerns'] as List? ?? []),
      pros: List<String>.from(map['pros'] as List? ?? []),
      cons: List<String>.from(map['cons'] as List? ?? []),
    );
  }
}
