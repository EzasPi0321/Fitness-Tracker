import 'dart:math' as math;

import 'nutrients.dart';
import 'profile.dart';

/// How a part of the score was earned, for the breakdown sheet.
class ScorePart {
  const ScorePart({required this.label, required this.points, required this.max, required this.detail});
  final String label;
  final double points;
  final double max;

  /// Plain words with the number behind it, e.g. "0.9 kcal per gram: low".
  final String detail;

  /// False when the data to judge it wasn't there (left out, not scored as zero).
  bool get counted => max > 0;
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

/// How many of the 100 points each part is worth, by the goal in the profile. Protein leads
/// for every goal (it keeps muscle on a cut and builds it on a gain); calorie density counts
/// most on a cut, where filling, light food helps, and least on a gain, where dense food
/// helps eat enough.
class ScoreWeights {
  const ScoreWeights({required this.protein, required this.density, required this.fibre, required this.sugarFat});
  final double protein;
  final double density;
  final double fibre;
  final double sugarFat;

  static ScoreWeights of(WeightGoal goal) => switch (goal) {
    WeightGoal.lose => const ScoreWeights(protein: 35, density: 30, fibre: 20, sugarFat: 15),
    WeightGoal.maintain => const ScoreWeights(protein: 35, density: 25, fibre: 25, sugarFat: 15),
    WeightGoal.gain => const ScoreWeights(protein: 40, density: 15, fibre: 25, sugarFat: 20),
  };
}

/// A 0–100 score for how much nutrition a food gives for its calories, weighted for the
/// profile's goal ([ScoreWeights]).
///
/// - Calorie density: kcal per gram. Under 0.6 (vegetables, most fruit) scores full; 5 and
///   up (crisps, chocolate, oils) scores nothing, so dry foods like crackers, rice cakes and
///   oats still get some credit. Needs the weight. Mostly-sugar foods without fibre (soft
///   drinks, lollies) don't get this credit.
/// - Protein: grams per 100 kcal. 8 g or more scores full (lean meat, fish, Greek yogurt,
///   tofu).
/// - Fibre: grams per 100 kcal. 3 g or more scores full (vegetables, fruit, legumes, whole
///   grains).
/// - Sugar and fat balance: loses points as sugar passes 20% of the energy (unless the food
///   also brings fibre, as whole fruit does) or fat passes 40% (less so when the fat comes
///   with fibre or protein, as in nuts and fish).
///
/// A part whose data is missing is left out and the rest are scaled to 100, so an unknown
/// never reads as a bad result.
class HealthScore {
  HealthScore._(this.score, this.parts);
  final int score;
  final List<ScorePart> parts;

  ScoreBand get band => ScoreBand.of(score);

  /// The goal the score is weighted for. AppState keeps it in step with the profile, so
  /// every score on screen (food rows, sheets, the day) uses the same weights.
  static WeightGoal goal = WeightGoal.maintain;

  /// Null when there's nothing to judge (no calories).
  static HealthScore? of(Nutrients n, {double? grams, WeightGoal? goal}) {
    if (n.calories < 1) return null;
    final w = ScoreWeights.of(goal ?? HealthScore.goal);
    final per100kcal = 100 / n.calories;
    double lerp(double v, double best, double worst) => ((v - worst) / (best - worst)).clamp(0.0, 1.0);

    final parts = <ScorePart>[];
    final fiber = n.fiber * per100kcal;
    final sugarShare = n.sugar * 4 / n.calories;
    final fatShare = n.fat * 9 / n.calories;
    final wholeFood = fiber >= 2; // fruit-style sugar comes with fibre
    final sugarScore = wholeFood ? 1.0 : lerp(sugarShare, 0.2, 0.6);

    // Calorie density. Sugary drinks are light per gram but mostly free sugar, so they
    // don't get density credit: it's scaled by the sugar score.
    if (grams != null && grams > 0) {
      final ed = n.calories / grams;
      final word = ed < 0.6
          ? 'very low'
          : ed < 1.5
          ? 'low'
          : ed < 4
          ? 'medium'
          : ed < 5
          ? 'high'
          : 'very high';
      parts.add(
        ScorePart(
          label: 'Calorie density',
          points: w.density * lerp(ed, 0.6, 5.0) * sugarScore,
          max: w.density,
          detail: '${_one(ed)} kcal per gram: $word',
        ),
      );
    } else {
      parts.add(const ScorePart(label: 'Calorie density', points: 0, max: 0, detail: 'Not counted: no weight'));
    }

    // Protein.
    final protein = n.protein * per100kcal;
    parts.add(
      ScorePart(
        label: 'Protein',
        points: w.protein * lerp(protein, 8, 0),
        max: w.protein,
        detail: '${_one(protein)} g per 100 kcal',
      ),
    );

    // Fibre: credit only, so an unknown 0 simply earns nothing.
    parts.add(
      ScorePart(
        label: 'Fibre',
        points: w.fibre * lerp(fiber, 3, 0),
        max: w.fibre,
        detail: n.fiber > 0 ? '${_one(fiber)} g per 100 kcal' : 'None listed',
      ),
    );

    // Sugar and fat balance.
    // Fat that comes with fibre (nuts, seeds) or lots of protein (fish, eggs) is judged
    // less harshly than fat in crisps or pastry: there's no saturated-fat figure to go on.
    final fatScore = wholeFood
        ? 1.0
        : protein >= 8
        ? math.max(lerp(fatShare, 0.4, 0.7), 0.8)
        : lerp(fatShare, 0.4, 0.7);
    final notes = <String>[
      if (n.sugar > 0)
        '${(sugarShare * 100).round()}% of energy from sugar${wholeFood && sugarShare > 0.2 ? ', with fibre' : ''}',
      '${(fatShare * 100).round()}% from fat',
    ];
    parts.add(
      ScorePart(
        label: 'Sugar and fat',
        points: w.sugarFat * math.min(sugarScore, fatScore),
        max: w.sugarFat,
        detail: notes.join(' · '),
      ),
    );

    final max = parts.fold<double>(0, (a, p) => a + p.max);
    final got = parts.fold<double>(0, (a, p) => a + p.points);
    return HealthScore._((got / max * 100).round().clamp(0, 100), parts);
  }

  /// A meal or a day: each food's score weighted by its calories, so a big plate counts for
  /// more than a cup of tea.
  static int? average(Iterable<(Nutrients, double?)> foods, {WeightGoal? goal}) {
    var total = 0.0, weight = 0.0;
    for (final (n, g) in foods) {
      final s = HealthScore.of(n, grams: g, goal: goal);
      if (s == null) continue;
      total += s.score * n.calories;
      weight += n.calories;
    }
    return weight == 0 ? null : (total / weight).round();
  }

  static String _one(double v) => v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
}
