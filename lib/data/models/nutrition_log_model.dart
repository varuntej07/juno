class NutritionLogModel {
  final String id;
  final String ocrText;
  final String? occasion;
  final int? quantity;
  final bool? isCheatMeal;
  final String analysis;
  final String recommendation; // eat, skip, moderate
  final DateTime timestamp;

  const NutritionLogModel({
    required this.id,
    required this.ocrText,
    this.occasion,
    this.quantity,
    this.isCheatMeal,
    required this.analysis,
    required this.recommendation,
    required this.timestamp,
  });

  factory NutritionLogModel.fromJson(Map<String, dynamic> json) {
    return NutritionLogModel(
      id: json['id'] as String,
      ocrText: json['ocr_text'] as String,
      occasion: json['occasion'] as String?,
      quantity: json['quantity'] as int?,
      isCheatMeal: json['is_cheat_meal'] as bool?,
      analysis: json['analysis'] as String,
      recommendation: json['recommendation'] as String? ?? 'moderate',
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ocr_text': ocrText,
        'occasion': occasion,
        'quantity': quantity,
        'is_cheat_meal': isCheatMeal,
        'analysis': analysis,
        'recommendation': recommendation,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };
}
