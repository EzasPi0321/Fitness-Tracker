import 'package:fittrack/models/food.dart';
import 'package:fittrack/models/health_score.dart';
import 'package:fittrack/models/nutrients.dart';
import 'package:fittrack/models/profile.dart';
import 'package:fittrack/services/ai_vision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A banana saved with only calories and macros: no weight, fibre or sugar.
  const bareBanana = Nutrients(calories: 105, protein: 1.3, carbs: 27, fat: 0.4);
  const cola = Nutrients(calories: 140, carbs: 39, sugar: 39);

  FoodEntry entry(Nutrients n, {double? grams, bool checked = false}) => FoodEntry(
    id: 'x',
    name: 'Banana',
    meal: MealType.breakfast,
    source: EntrySource.manual,
    consumedAt: DateTime(2026, 11, 22, 8),
    quantity: 1,
    unit: 'serving',
    grams: grams,
    nutrients: n,
    detailChecked: checked,
  );

  test('missing fibre and sugar counts as half, not zero', () {
    final s = HealthScore.of(bareBanana, goal: WeightGoal.maintain)!;
    final fibre = s.parts.firstWhere((p) => p.label == 'Fibre');
    expect(fibre.detail, contains('Not listed'));
    expect(fibre.points, fibre.max / 2);
    expect(s.score, inInclusiveRange(38, 50)); // was 27 with fibre counted as 0 / 25
  });

  test('a soft drink with sugar listed still has its real 0 fibre counted', () {
    final s = HealthScore.of(cola, grams: 330, goal: WeightGoal.maintain)!;
    expect(s.parts.firstWhere((p) => p.label == 'Fibre').counted, isTrue);
    expect(s.score, lessThan(35));
  });

  test('once checked, a 0 is a real 0', () {
    const riceCake = Nutrients(calories: 35, protein: 0.7, carbs: 7.5, fat: 0.3);
    final unknown = HealthScore.of(riceCake, grams: 9)!;
    final checked = HealthScore.of(riceCake, grams: 9, detailChecked: true)!;
    expect(unknown.parts.firstWhere((p) => p.label == 'Fibre').detail, contains('Not listed'));
    expect(checked.parts.firstWhere((p) => p.label == 'Fibre').points, 0); // confirmed: really none
  });

  test('filled in, the banana scores like a banana', () {
    const filled = Nutrients(calories: 105, protein: 1.3, carbs: 27, fat: 0.4, fiber: 3.1, sugar: 14);
    final s = HealthScore.of(filled, grams: 118, goal: WeightGoal.maintain, detailChecked: true)!;
    expect(s.score, inInclusiveRange(60, 80));
  });

  test('which entries need filling in', () {
    expect(entry(bareBanana).missingDetail, isTrue); // no weight, no fibre or sugar
    expect(entry(cola, grams: 330).missingDetail, isTrue); // fibre never recorded: ask once
    expect(entry(cola, grams: 330, checked: true).missingDetail, isFalse); // asked already
    expect(entry(const Nutrients(calories: 0, carbs: 0), grams: 600).missingDetail, isFalse); // water
  });

  test('the checked flag survives saving', () {
    final e = entry(bareBanana, checked: true);
    expect(FoodEntry.fromJson(e.toJson()).detailChecked, isTrue);
    expect(FoodEntry.fromJson(entry(bareBanana).toJson()).detailChecked, isFalse);
  });

  test('AI answers are kept within the carbs and a believable weight', () {
    final d = AIVisionService.decodeDetail(
      '{"grams": 118, "fiber_g": 3.1, "sugar_g": 14.4, "confidence": 0.9}',
      bareBanana,
    );
    expect(d.grams, 118);
    expect(d.fiber, 3.1);
    expect(d.sugar, 14.4);
    final silly = AIVisionService.decodeDetail(
      '{"grams": 2, "fiber_g": 50, "sugar_g": 0, "confidence": 0.5}',
      bareBanana,
    );
    expect(silly.grams, isNull); // 105 kcal in 2 g is impossible
    expect(silly.fiber, 27); // no more fibre than carbohydrate
    expect(silly.sugar, 0); // a real zero is kept
  });
}
