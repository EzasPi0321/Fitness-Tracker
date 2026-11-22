import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/models/health_score.dart';
import 'package:fittrack/models/nutrients.dart';
import 'package:fittrack/models/profile.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Sour cream & chives rice cakes, per 100 g: dry, low in protein and fibre, low fat.
  const riceCakes = Nutrients(calories: 410, protein: 8, carbs: 84, fat: 4, fiber: 3, sugar: 1.5);
  const chicken = Nutrients(calories: 165, protein: 31, carbs: 0, fat: 3.6);
  const crisps = Nutrients(calories: 536, protein: 7, carbs: 53, fat: 35, fiber: 4.4, sugar: 0.5);
  int score(Nutrients n, WeightGoal g) => HealthScore.of(n, grams: 100, goal: g)!.score;

  test('every goal adds up to 100 and protein leads', () {
    for (final g in WeightGoal.values) {
      final w = ScoreWeights.of(g);
      expect(w.protein + w.density + w.fibre + w.sugarFat, 100);
      expect(w.protein, greaterThan(w.density));
      expect(w.protein, greaterThan(w.fibre));
    }
  });

  test('rice cakes get some density credit and score higher on a gain', () {
    final cut = score(riceCakes, WeightGoal.lose);
    final gain = score(riceCakes, WeightGoal.gain);
    expect(cut, inInclusiveRange(32, 38));
    expect(gain, inInclusiveRange(37, 44));
    final parts = HealthScore.of(riceCakes, grams: 100, goal: WeightGoal.lose)!.parts;
    expect(parts.first.points, greaterThan(0)); // 4.1 kcal/g no longer scores nothing
  });

  test('crisps stay low and chicken stays high on every goal', () {
    for (final g in WeightGoal.values) {
      expect(score(crisps, g), lessThan(30), reason: '$g');
      expect(score(chicken, g), greaterThanOrEqualTo(65), reason: '$g'); // no fibre, so not perfect
    }
  });

  test('the score follows the goal in the profile', () async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    await s.load(seedSampleIfEmpty: true);
    s.updateProfileAndPlan((p) => p.goal = WeightGoal.gain);
    expect(HealthScore.goal, WeightGoal.gain);
    expect(HealthScore.of(riceCakes, grams: 100)!.score, score(riceCakes, WeightGoal.gain));
    s.updateProfileAndPlan((p) => p.goal = WeightGoal.lose);
    expect(HealthScore.goal, WeightGoal.lose);
  });
}
