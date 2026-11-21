import 'nutrients.dart';

enum BiologicalSex {
  female('Female'),
  male('Male');

  const BiologicalSex(this.title);
  final String title;
}

enum ActivityLevel {
  sedentary('Sedentary', 'Little or no exercise', 1.2),
  light('Lightly active', 'Exercise 1 to 3 days a week', 1.375),
  moderate('Moderately active', 'Exercise 3 to 5 days a week', 1.55),
  active('Active', 'Exercise 6 to 7 days a week', 1.725),
  veryActive('Very active', 'Hard exercise 6 to 7 days a week', 1.9);

  const ActivityLevel(this.title, this.detail, this.multiplier);
  final String title;
  final String detail;
  final double multiplier;
}

enum WeightGoal {
  lose('Lose Weight', 'About 0.5 kg (1 lb) per week', -500, 2.0),
  maintain('Maintain Weight', 'Stay where you are', 0, 1.6),
  gain('Build Muscle', 'Lean surplus of ~300 kcal', 300, 1.8);

  const WeightGoal(this.title, this.detail, this.calorieAdjustment, this.proteinPerKg);
  final String title;
  final String detail;
  final double calorieAdjustment;
  final double proteinPerKg;
}

class EnergyPlan {
  const EnergyPlan({required this.bmr, required this.tdee, required this.targets});
  final double bmr;
  final double tdee;
  final Nutrients targets;
}

const poundsPerKilogram = 2.20462262;
const centimetersPerInch = 2.54;

/// Same rules as the iOS NutritionCalculator: Mifflin–St Jeor BMR × activity, goal adjustment,
/// safe minimums, protein by body weight, fat at 25 % of energy, carbs fill the rest.
class NutritionCalculator {
  static double bmr({
    required BiologicalSex sex,
    required double weightKg,
    required double heightCm,
    required int age,
  }) {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    return sex == BiologicalSex.male ? base + 5 : base - 161;
  }

  /// Total daily energy expenditure: Mifflin–St Jeor BMR, cut to whole kcal the way common TDEE
  /// calculators do, times the activity factor, rounded.
  static double tdee(double bmr, ActivityLevel activity) => _round(bmr.floorToDouble() * activity.multiplier);

  static EnergyPlan plan({
    required BiologicalSex sex,
    required int age,
    required double heightCm,
    required double weightKg,
    required ActivityLevel activity,
    required WeightGoal goal,
  }) {
    final resting = bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age);
    final tdee = NutritionCalculator.tdee(resting, activity);
    final minimum = sex == BiologicalSex.male ? 1500.0 : 1200.0;
    final calories = _round(_max(minimum, tdee + goal.calorieAdjustment) / 10) * 10;

    var protein = _round(weightKg * goal.proteinPerKg);
    var fat = _round(_max(calories * 0.25 / 9, weightKg * 0.6));
    if (protein * 4 + fat * 9 > calories) {
      final scale = calories * 0.9 / (protein * 4 + fat * 9);
      protein = _round(protein * scale);
      fat = _round(fat * scale);
    }
    final carbs = _round(_max(0, (calories - protein * 4 - fat * 9) / 4));
    return EnergyPlan(
      bmr: resting,
      tdee: tdee,
      targets: Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat),
    );
  }

  // Swift's .rounded() rounds half away from zero; Dart's round() does the same.
  static double _round(double v) => v.roundToDouble();
  static double _max(double a, double b) => a > b ? a : b;
}

class UserProfile {
  UserProfile({
    this.sex = BiologicalSex.female,
    DateTime? birthDate,
    this.heightCm = 170,
    this.weightKg = 70,
    this.activity = ActivityLevel.moderate,
    this.goal = WeightGoal.maintain,
    this.usesMetric = true,
    this.targets = const Nutrients(calories: 2000, protein: 140, carbs: 220, fat: 65),
  }) : birthDate = birthDate ?? DateTime(DateTime.now().year - 30, 1, 1);

  BiologicalSex sex;
  DateTime birthDate;
  double heightCm;
  double weightKg;
  ActivityLevel activity;
  WeightGoal goal;
  bool usesMetric;
  Nutrients targets;

  int get age {
    final now = DateTime.now();
    var years = now.year - birthDate.year;
    if (now.month < birthDate.month || (now.month == birthDate.month && now.day < birthDate.day)) years--;
    return years < 0 ? 0 : years;
  }

  EnergyPlan get plan => NutritionCalculator.plan(
    sex: sex,
    age: age,
    heightCm: heightCm,
    weightKg: weightKg,
    activity: activity,
    goal: goal,
  );

  bool get isBodyValid =>
      age >= 13 && age <= 110 && heightCm >= 100 && heightCm <= 250 && weightKg >= 30 && weightKg <= 350;

  UserProfile copy() => UserProfile(
    sex: sex,
    birthDate: birthDate,
    heightCm: heightCm,
    weightKg: weightKg,
    activity: activity,
    goal: goal,
    usesMetric: usesMetric,
    targets: targets,
  );

  Map<String, dynamic> toJson() => {
    'sex': sex.name,
    'birth': birthDate.millisecondsSinceEpoch,
    'height': heightCm,
    'weight': weightKg,
    'activity': activity.name,
    'goal': goal.name,
    'metric': usesMetric,
    'targets': targets.toJson(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    sex: BiologicalSex.values.firstWhere((v) => v.name == j['sex'], orElse: () => BiologicalSex.female),
    birthDate: DateTime.fromMillisecondsSinceEpoch(((j['birth'] as num?) ?? 631152000000).toInt()),
    heightCm: ((j['height'] as num?) ?? 170).toDouble(),
    weightKg: ((j['weight'] as num?) ?? 70).toDouble(),
    activity: ActivityLevel.values.firstWhere((v) => v.name == j['activity'], orElse: () => ActivityLevel.moderate),
    goal: WeightGoal.values.firstWhere((v) => v.name == j['goal'], orElse: () => WeightGoal.maintain),
    usesMetric: (j['metric'] as bool?) ?? true,
    targets: j['targets'] is Map
        ? Nutrients.fromJson((j['targets'] as Map).cast<String, dynamic>())
        : const Nutrients(calories: 2000, protein: 140, carbs: 220, fat: 65),
  );
}
