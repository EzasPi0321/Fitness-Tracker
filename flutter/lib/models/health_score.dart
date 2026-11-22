import 'dart:math' as math;

import 'food.dart';
import 'nutrients.dart';
import 'profile.dart';

/// One thing that moved the score, in plain words ("High sodium", "Good protein"). The sheet
/// shows the two or three that mattered most.
class ScoreFactor {
  const ScoreFactor(this.label, {required this.good, required this.weight});
  final String label;
  final bool good;

  /// How much it moved the score, for ordering.
  final double weight;
}

enum ScoreBand {
  excellent('Excellent'),
  good('Good'),
  fair('Fair'),
  poor('Poor');

  const ScoreBand(this.label);
  final String label;

  static ScoreBand of(int score) => score >= 80
      ? excellent
      : score >= 60
      ? good
      : score >= 40
      ? fair
      : poor;
}

/// A 0-100 food quality score built on FSANZ's Nutrient Profiling Scoring Criterion (NPSC,
/// Food Standards Code Schedule 5), the system behind Australian health claims.
///
/// NPSC, per 100 g or ml:
/// - Baseline points (bad): energy (0-10, every 335 kJ), saturated fat (0-10, every 1 g;
///   up to 30 for cheeses and oils), total sugars (0-10, from 5 g to 45 g), sodium (0-10,
///   every 90 mg; up to 30 for cheeses and oils).
/// - Modifying points (good): fruit, vegetables, nuts and legumes (1 at 40%, 2 at 60%, 5 at
///   80%), protein (0-5, every 1.6 g), fibre (0-5, from 0.9 g to 4.7 g). Protein doesn't
///   count once the baseline reaches 13, unless the food is mostly fruit or vegetables.
/// - Final = baseline - modifying. A food can make health claims below 4 (drinks below 1,
///   cheeses and oils below 28).
///
/// FitTrack's adjustments, tested on 25 common foods:
/// - One 0-100 scale: each kind's health-claim cut-off lands at 60, and every point of
///   NPSC is 3.5 points here (broccoli 100, chicken 84, chips about 40, chocolate 0).
/// - Drinks are judged per typical serve (energy points x3) and their sugar weighs 4x.
/// - Foods that are mostly free sugar with little fibre (soft drinks, juice, lollies) are
///   capped at 20.
/// - The goal tilts it: a cut weighs energy x1.2 and protein x1.3; a gain weighs energy x0.8
///   and protein x1.4.
class HealthScore {
  HealthScore._(this.score, this.factors, {this.partial = false});
  final int score;

  /// Most important first.
  final List<ScoreFactor> factors;

  /// Some values weren't recorded and were estimated or left out.
  final bool partial;

  ScoreBand get band => ScoreBand.of(score);

  /// The goal the score is weighted for. AppState keeps it in step with the profile, so
  /// every score on screen (food rows, sheets, the day) uses the same weights.
  static WeightGoal goal = WeightGoal.maintain;

  static int _pts(double v, List<double> steps) => steps.where((s) => v > s).length;

  static final _energy = [for (var i = 1; i <= 10; i++) 335.0 * i];
  static final _sat = [for (var i = 1; i <= 10; i++) i.toDouble()];
  static final _satFatty = [for (var i = 1; i <= 30; i++) i.toDouble()];
  static const _sugar = <double>[5, 9, 13.5, 18, 22.5, 27, 31, 36, 40, 45];
  static final _sodium = [for (var i = 1; i <= 10; i++) 90.0 * i];
  static final _sodiumFatty = [for (var i = 1; i <= 30; i++) 90.0 * i];
  static const _protein = <double>[1.6, 3.2, 4.8, 6.4, 8.0];
  static const _fibre = <double>[0.9, 1.9, 2.8, 3.7, 4.7];

  /// Null when there's nothing to judge (no calories).
  ///
  /// [detailChecked]: fibre, sugar, saturated fat and sodium were filled in or confirmed, so
  /// a 0 is a real 0 (a soft drink has no fibre), not missing data. [name] lets the kind and
  /// fruit/vegetable share be guessed when they weren't recorded.
  static HealthScore? of(
    Nutrients n, {
    double? grams,
    WeightGoal? goal,
    bool detailChecked = false,
    double? fruitVeg,
    FoodKind? kind,
    String name = '',
  }) {
    if (n.calories < 1) return null;
    var partial = false;
    final k = kind ?? kindFromName(name);

    // Everything per 100 g (or ml). With no weight, assume a typical 2 kcal per gram.
    var g = grams;
    if (g == null || g <= 0) {
      g = n.calories / 2;
      partial = true;
    }
    final per = 100 / g;
    final kj = n.calories * 4.184 * per;
    final protein = n.protein * per;

    // Missing values: an unknown fibre counts as half its points, unknown saturated fat is
    // estimated as a third of the fat, and unknown sugar or sodium simply earn nothing.
    final fibreSugarUnknown = !detailChecked && n.fiber == 0 && n.sugar == 0 && n.carbs >= 5;
    final satUnknown = !detailChecked && n.satFat == 0 && n.fat >= 3;
    final sodiumUnknown = !detailChecked && n.sodium == 0 && n.calories >= 50;
    if (fibreSugarUnknown || satUnknown || sodiumUnknown) partial = true;
    final sat = (satUnknown ? n.fat / 3 : n.satFat) * per;
    final sugar = n.sugar * per;
    final sodium = n.sodium * per;
    final fibre = n.fiber * per;

    var e = _pts(kj, _energy).toDouble();
    final s = _pts(sat, k == FoodKind.fatty ? _satFatty : _sat).toDouble();
    var su = _pts(sugar, _sugar).toDouble();
    final na = _pts(sodium, k == FoodKind.fatty ? _sodiumFatty : _sodium).toDouble();
    if (k == FoodKind.drink) {
      e = math.min(10, e * 3);
      su = math.min(10, su * 4);
    }
    final fv = fruitVeg ?? fruitVegFromName(name);
    final v = fv >= 80
        ? 5.0
        : fv >= 60
        ? 2.0
        : fv >= 40
        ? 1.0
        : 0.0;
    var p = _pts(protein, _protein).toDouble();
    final f = fibreSugarUnknown ? 2.5 : _pts(fibre, _fibre).toDouble();
    if (e + s + su + na >= 13 && v < 5) p = 0; // NPSC: protein can't offset a poor baseline

    final (ew, pw) = switch (goal ?? HealthScore.goal) {
      WeightGoal.lose => (1.2, 1.3),
      WeightGoal.maintain => (1.0, 1.0),
      WeightGoal.gain => (0.8, 1.4),
    };
    final npsc = e * ew + s + su + na - v - p * pw - f;
    // Each kind's health-claim cut-off (drinks < 1, foods < 4, cheeses and oils < 28) maps to
    // 60. Cheeses and oils only get part of their looser cut-off, or oil would rank with fruit.
    final shift = switch (k) {
      FoodKind.drink => -3.0,
      FoodKind.food => 0.0,
      FoodKind.fatty => 24 * 0.6,
    };
    var score = (60 + (4 - (npsc - shift)) * 3.5).clamp(0, 100).round();

    final factors = <ScoreFactor>[];
    // Mostly free sugar with little fibre: soft drinks, juice, lollies.
    final sugarShare = n.sugar * 4 / n.calories;
    final fibrePer100kcal = n.fiber * 100 / n.calories;
    if (sugarShare >= 0.5 && fibrePer100kcal < 1.5) {
      score = math.min(score, 20);
      factors.add(const ScoreFactor('Mostly sugar', good: false, weight: 20));
    } else if (su >= 4) {
      factors.add(ScoreFactor('High sugar', good: false, weight: su));
    }
    if (na >= 5) factors.add(ScoreFactor('High sodium', good: false, weight: na));
    if (s >= 4) factors.add(ScoreFactor('High saturated fat', good: false, weight: s));
    if (e >= 6) factors.add(ScoreFactor('Energy-dense', good: false, weight: e * ew));
    if (v >= 2)
      factors.add(ScoreFactor(fv >= 80 ? 'Whole fruit, veg or nuts' : 'Some fruit or veg', good: true, weight: v));
    if (p >= 4) factors.add(ScoreFactor('Good protein', good: true, weight: p * pw));
    if (!fibreSugarUnknown && f >= 3) factors.add(ScoreFactor('Good fibre', good: true, weight: f));
    if (e == 0 && k != FoodKind.drink) factors.add(const ScoreFactor('Light', good: true, weight: 2));
    if (factors.isEmpty) {
      factors.add(const ScoreFactor('Nothing stands out', good: true, weight: 0));
    }
    factors.sort((a, b) => b.weight.compareTo(a.weight));
    return HealthScore._(score, factors.take(3).toList(), partial: partial);
  }

  /// A guess at the kind from the name, when it wasn't recorded.
  static FoodKind kindFromName(String name) {
    final s = name.toLowerCase();
    bool has(String pattern) => RegExp(pattern).hasMatch(s);
    if (has(r'\b(peanut|almond|nut|cashew) butter\b|\bcottage cheese\b|\bricotta\b')) return FoodKind.food;
    if (has(r'\b(oil|butter|margarine|ghee|lard|cheese|cheddar|parmesan|mozzarella|brie|camembert|feta|halloumi)\b')) {
      return FoodKind.fatty;
    }
    if (has(r'\b(chocolate|bar|cake|biscuit|cookie|cereal|powder|bread|pudding|ice cream)\b')) return FoodKind.food;
    if (has(
      r'\b(juice|cola|coke|soda|soft drink|lemonade|energy drink|sports drink|iced tea|kombucha|smoothie|'
      r'milkshake|shake|coffee|latte|cappuccino|flat white|long black|espresso|tea|beer|wine|cider|cordial|water|'
      r'milk|drink)\b',
    )) {
      return FoodKind.drink;
    }
    return FoodKind.food;
  }

  /// A guess at the fruit, vegetable, nut and legume share for simple whole foods named on
  /// their own ("Apple", "Almonds", "Steamed broccoli"). Mixed dishes get 0 until filled in.
  static double fruitVegFromName(String name) {
    final words = name.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || words.length > 2) return 0;
    const whole = {
      'apple',
      'apples',
      'banana',
      'bananas',
      'orange',
      'oranges',
      'pear',
      'pears',
      'grapes',
      'mango',
      'kiwi',
      'berries',
      'strawberries',
      'blueberries',
      'raspberries',
      'watermelon',
      'melon',
      'pineapple',
      'peach',
      'plum',
      'broccoli',
      'carrot',
      'carrots',
      'spinach',
      'kale',
      'tomato',
      'tomatoes',
      'cucumber',
      'lettuce',
      'capsicum',
      'zucchini',
      'peas',
      'beans',
      'lentils',
      'chickpeas',
      'cauliflower',
      'avocado',
      'mushrooms',
      'pumpkin',
      'almonds',
      'walnuts',
      'cashews',
      'peanuts',
      'pistachios',
      'nuts',
      'edamame',
    };
    return words.any(whole.contains) ? 100 : 0;
  }

  /// A meal or a day: each food's score weighted by its calories, so a big plate counts for
  /// more than a cup of tea.
  static int? average(Iterable<(HealthScore?, double)> scored) {
    var total = 0.0, weight = 0.0;
    for (final (s, kcal) in scored) {
      if (s == null || kcal <= 0) continue;
      total += s.score * kcal;
      weight += kcal;
    }
    return weight == 0 ? null : (total / weight).round();
  }
}
