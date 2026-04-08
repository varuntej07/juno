class DietaryProfileModel {
  final int? age;
  final String? gender;
  final double? heightCm;
  final double? weightKg;
  final String? goal;
  final String? activityLevel;
  final int? workoutMinPerDay;
  final List<String> restrictions;
  final List<String> allergies;
  final double? fatPct;

  const DietaryProfileModel({
    this.age,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.goal,
    this.activityLevel,
    this.workoutMinPerDay,
    this.restrictions = const [],
    this.allergies = const [],
    this.fatPct,
  });

  factory DietaryProfileModel.fromMap(Map<String, dynamic> map) {
    return DietaryProfileModel(
      age: (map['age'] as num?)?.toInt(),
      gender: map['gender'] as String?,
      heightCm: (map['height_cm'] as num?)?.toDouble(),
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      goal: map['goal'] as String?,
      activityLevel: map['activity_level'] as String?,
      workoutMinPerDay: (map['workout_min_per_day'] as num?)?.toInt(),
      restrictions: List<String>.from(map['restrictions'] as List? ?? []),
      allergies: List<String>.from(map['allergies'] as List? ?? []),
      fatPct: (map['fat_pct'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        if (heightCm != null) 'height_cm': heightCm,
        if (weightKg != null) 'weight_kg': weightKg,
        if (goal != null) 'goal': goal,
        if (activityLevel != null) 'activity_level': activityLevel,
        if (workoutMinPerDay != null) 'workout_min_per_day': workoutMinPerDay,
        'restrictions': restrictions,
        'allergies': allergies,
        if (fatPct != null) 'fat_pct': fatPct,
      };

  DietaryProfileModel copyWith({
    int? age,
    String? gender,
    double? heightCm,
    double? weightKg,
    String? goal,
    String? activityLevel,
    int? workoutMinPerDay,
    List<String>? restrictions,
    List<String>? allergies,
    double? fatPct,
  }) {
    return DietaryProfileModel(
      age: age ?? this.age,
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      goal: goal ?? this.goal,
      activityLevel: activityLevel ?? this.activityLevel,
      workoutMinPerDay: workoutMinPerDay ?? this.workoutMinPerDay,
      restrictions: restrictions ?? this.restrictions,
      allergies: allergies ?? this.allergies,
      fatPct: fatPct ?? this.fatPct,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DietaryProfileModel &&
          age == other.age &&
          gender == other.gender &&
          heightCm == other.heightCm &&
          weightKg == other.weightKg &&
          goal == other.goal &&
          activityLevel == other.activityLevel &&
          workoutMinPerDay == other.workoutMinPerDay &&
          fatPct == other.fatPct;

  @override
  int get hashCode => Object.hash(
        age,
        gender,
        heightCm,
        weightKg,
        goal,
        activityLevel,
        workoutMinPerDay,
        fatPct,
      );
}
