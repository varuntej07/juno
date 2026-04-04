enum MemoryCategory { preferences, facts, habits, health, routines }

class MemoryModel {
  final String id;
  final String key;
  final String value;
  final MemoryCategory category;
  final String source; // voice, text, nutrition_scan, system
  final DateTime createdAt;
  final DateTime updatedAt;

  const MemoryModel({
    required this.id,
    required this.key,
    required this.value,
    required this.category,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MemoryModel.fromJson(Map<String, dynamic> json) {
    return MemoryModel(
      id: json['id'] as String,
      key: json['key'] as String,
      value: json['value'] as String,
      category: MemoryCategory.values.byName(
        json['category'] as String? ?? 'facts',
      ),
      source: json['source'] as String? ?? 'system',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'value': value,
        'category': category.name,
        'source': source,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
