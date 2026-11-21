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
  lose('Lose Weight', 'About 0.5 kg (1 lb) per week', -500),
  maintain('Maintain Weight', 'Stay where you are', 0),
  gain('Build Muscle', 'Lean surplus of ~300 kcal', 300);

  const WeightGoal(this.title, this.detail, this.calorieAdjustment);
  final String title;
  final String detail;
  final double calorieAdjustment;
}

/// How daily calories are split between protein, carbs and fat (shares of energy),
/// in the style of common macro calculators.
enum DietStyle {
  balanced('Balanced', 'Protein 25% · Carbs 45% · Fat 30%', 0.25, 0.45, 0.30),
  lowFat('Low fat', 'Protein 25% · Carbs 55% · Fat 20%', 0.25, 0.55, 0.20),
  lowCarb('Low carb', 'Protein 30% · Carbs 25% · Fat 45%', 0.30, 0.25, 0.45),
  highProtein('High protein', 'Protein 35% · Carbs 40% · Fat 25%', 0.35, 0.40, 0.25);

  const DietStyle(this.title, this.detail, this.protein, this.carbs, this.fat);
  final String title;
  final String detail;
  final double protein;
  final double carbs;
  final double fat;
}

/// A recommended range of grams for one macro.
class MacroRange {
  const MacroRange(this.low, this.high);
  final double low;
  final double high;
  bool contains(double g) => g >= low && g <= high;
}

class EnergyPlan {
  const EnergyPlan({required this.bmr, required this.tdee, required this.targets});
  final double bmr;
  final double tdee;
  final Nutrients targets;
}

const poundsPerKilogram = 2.20462262;
const centimetersPerInch = 2.54;

/// Mifflin–St Jeor BMR × activity, goal adjustment and safe minimums; macros split by the
/// chosen [DietStyle].
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
    DietStyle diet = DietStyle.balanced,
  }) {
    final resting = bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age);
    final tdee = NutritionCalculator.tdee(resting, activity);
    final minimum = sex == BiologicalSex.male ? 1500.0 : 1200.0;
    final calories = _round(_max(minimum, tdee + goal.calorieAdjustment) / 10) * 10;

    final protein = _round(calories * diet.protein / 4);
    final fat = _round(calories * diet.fat / 9);
    final carbs = _round(_max(0, (calories - protein * 4 - fat * 9) / 4));
    return EnergyPlan(
      bmr: resting,
      tdee: tdee,
      targets: Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat),
    );
  }

  /// Recommended ranges for a day's [calories] (the Acceptable Macronutrient Distribution
  /// Ranges): protein 10–35 %, carbs 45–65 %, fat 20–35 % of energy.
  static Map<Macro, MacroRange> ranges(double calories) => {
    Macro.protein: MacroRange(_round(calories * 0.10 / 4), _round(calories * 0.35 / 4)),
    Macro.carbs: MacroRange(_round(calories * 0.45 / 4), _round(calories * 0.65 / 4)),
    Macro.fat: MacroRange(_round(calories * 0.20 / 9), _round(calories * 0.35 / 9)),
  };

  // Swift's .rounded() rounds half away from zero; Dart's round() does the same.
  static double _round(double v) => v.roundToDouble();
  static double _max(double a, double b) => a > b ? a : b;
}

class UserProfile {
  UserProfile({
    this.name = '',
    this.sex = BiologicalSex.female,
    DateTime? birthDate,
    this.heightCm = 170,
    this.weightKg = 70,
    this.activity = ActivityLevel.moderate,
    this.goal = WeightGoal.maintain,
    this.diet = DietStyle.balanced,
    this.usesMetric = true,
    this.targets = const Nutrients(calories: 2000, protein: 140, carbs: 220, fat: 65),
  }) : birthDate = birthDate ?? DateTime(DateTime.now().year - 30, 1, 1);

  /// What to call the user. Optional; empty means no name.
  String name;
  BiologicalSex sex;
  DateTime birthDate;
  double heightCm;
  double weightKg;
  ActivityLevel activity;
  WeightGoal goal;
  DietStyle diet;
  bool usesMetric;
  Nutrients targets;

  /// First word of the name, for the line above Today ("Daniel · Sat 21 Nov").
  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  /// Up to two initials for the avatar.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

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
    diet: diet,
  );

  bool get isBodyValid =>
      age >= 13 && age <= 110 && heightCm >= 100 && heightCm <= 250 && weightKg >= 30 && weightKg <= 350;

  UserProfile copy() => UserProfile(
    name: name,
    sex: sex,
    birthDate: birthDate,
    heightCm: heightCm,
    weightKg: weightKg,
    activity: activity,
    goal: goal,
    diet: diet,
    usesMetric: usesMetric,
    targets: targets,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'sex': sex.name,
    'birth': birthDate.millisecondsSinceEpoch,
    'height': heightCm,
    'weight': weightKg,
    'activity': activity.name,
    'goal': goal.name,
    'diet': diet.name,
    'metric': usesMetric,
    'targets': targets.toJson(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    name: (j['name'] as String?) ?? '',
    sex: BiologicalSex.values.firstWhere((v) => v.name == j['sex'], orElse: () => BiologicalSex.female),
    birthDate: DateTime.fromMillisecondsSinceEpoch(((j['birth'] as num?) ?? 631152000000).toInt()),
    heightCm: ((j['height'] as num?) ?? 170).toDouble(),
    weightKg: ((j['weight'] as num?) ?? 70).toDouble(),
    activity: ActivityLevel.values.firstWhere((v) => v.name == j['activity'], orElse: () => ActivityLevel.moderate),
    goal: WeightGoal.values.firstWhere((v) => v.name == j['goal'], orElse: () => WeightGoal.maintain),
    diet: DietStyle.values.firstWhere((v) => v.name == j['diet'], orElse: () => DietStyle.balanced),
    usesMetric: (j['metric'] as bool?) ?? true,
    targets: j['targets'] is Map
        ? Nutrients.fromJson((j['targets'] as Map).cast<String, dynamic>())
        : const Nutrients(calories: 2000, protein: 140, carbs: 220, fat: 65),
  );
}
