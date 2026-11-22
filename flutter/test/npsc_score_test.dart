import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/models/food.dart';
import 'package:fittrack/models/health_score.dart';
import 'package:fittrack/models/nutrients.dart';
import 'package:fittrack/models/profile.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 25-food simulation the score was tuned on, per 100 g or ml, with fully known detail.
void main() {
  int score(
    String name,
    double kj, {
    double sat = 0,
    double sugar = 0,
    double sodium = 0,
    double protein = 0,
    double fibre = 0,
    double fat = 0,
    double carbs = 0,
    double fv = 0,
    FoodKind kind = FoodKind.food,
    WeightGoal goal = WeightGoal.maintain,
  }) => HealthScore.of(
    Nutrients(
      calories: kj / 4.184,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fibre,
      sugar: sugar,
      satFat: sat,
      sodium: sodium,
    ),
    grams: 100,
    goal: goal,
    detailChecked: true,
    fruitVeg: fv,
    kind: kind,
    name: name,
  )!.score;

  test('whole foods score high', () {
    expect(score('Broccoli', 141, sat: 0.1, sugar: 1.7, sodium: 33, protein: 2.8, fibre: 2.6, fv: 100, carbs: 7), 100);
    expect(score('Apple', 218, sugar: 10.4, sodium: 1, protein: 0.3, fibre: 2.4, fv: 100, carbs: 14), greaterThan(85));
    expect(score('Chicken breast', 690, sat: 1, sodium: 74, protein: 31, fat: 3.6), inInclusiveRange(78, 90));
    expect(
      score('Rolled oats', 1560, sat: 1.2, sugar: 1, sodium: 6, protein: 13, fibre: 10, carbs: 60),
      greaterThan(85),
    );
    expect(
      score('Almonds', 2440, sat: 3.8, sugar: 4.4, sodium: 1, protein: 21, fibre: 12.5, fv: 100, fat: 50, carbs: 22),
      greaterThan(85),
    );
  });

  test('flavoured rice cakes sit below plain ones (the salt) but above chips', () {
    final plain = score('Rice cakes', 1640, sat: 0.6, sugar: 0.9, sodium: 30, protein: 8, fibre: 3.5, carbs: 82);
    final flavoured = score('Rice cakes', 1700, sat: 1, sugar: 2, sodium: 450, protein: 8, fibre: 3, carbs: 82);
    final chips = score(
      'Potato chips',
      2240,
      sat: 3,
      sugar: 0.5,
      sodium: 520,
      protein: 6.6,
      fibre: 4.4,
      fat: 35,
      carbs: 53,
    );
    expect(plain, greaterThan(flavoured));
    expect(flavoured, greaterThan(chips));
    expect(chips, lessThan(50));
  });

  test('treats, salty cheese and sugary drinks score low', () {
    expect(
      score('Milk chocolate', 2240, sat: 18.6, sugar: 51, sodium: 80, protein: 7.7, fibre: 2, fat: 30, carbs: 59),
      0,
    );
    expect(
      score('Cheddar cheese', 1680, sat: 21, sodium: 650, protein: 25, fat: 33, kind: FoodKind.fatty),
      lessThan(25),
    );
    expect(score('Cola', 180, sugar: 10.6, sodium: 10, carbs: 10.6, kind: FoodKind.drink), lessThanOrEqualTo(20));
    expect(
      score(
        'Orange juice',
        190,
        sugar: 8.4,
        sodium: 1,
        protein: 0.7,
        fibre: 0.2,
        fv: 100,
        carbs: 10,
        kind: FoodKind.drink,
      ),
      lessThanOrEqualTo(20),
    ); // mostly free sugar
  });

  test('the goal tilts it: a gain is kinder to energy, a cut kinder to protein', () {
    double pizza(WeightGoal g) => score(
      'Pizza',
      1100,
      sat: 4.5,
      sugar: 3.6,
      sodium: 600,
      protein: 11,
      fibre: 2,
      fv: 10,
      fat: 10,
      carbs: 30,
      goal: g,
    ).toDouble();
    expect(pizza(WeightGoal.gain), greaterThanOrEqualTo(pizza(WeightGoal.lose)));
    final chickenCut = score('Chicken breast', 690, sat: 1, sodium: 74, protein: 31, fat: 3.6, goal: WeightGoal.lose);
    final chickenMaintain = score('Chicken breast', 690, sat: 1, sodium: 74, protein: 31, fat: 3.6);
    expect(chickenCut, greaterThanOrEqualTo(chickenMaintain));
  });

  test('the top factors say what mattered', () {
    final s = HealthScore.of(
      const Nutrients(calories: 255, protein: 11, carbs: 30, fat: 10, fiber: 2, sugar: 3.6, satFat: 4.5, sodium: 600),
      grams: 100,
      detailChecked: true,
      name: 'Pizza',
    )!;
    expect(s.factors.map((f) => f.label), contains('High sodium'));
    expect(s.factors.length, lessThanOrEqualTo(3));
  });

  test('kind and fruit/veg are guessed from simple names', () {
    expect(HealthScore.kindFromName('Coke Zero'), FoodKind.drink);
    expect(HealthScore.kindFromName('Flat white'), FoodKind.drink);
    expect(HealthScore.kindFromName('Milk chocolate'), FoodKind.food);
    expect(HealthScore.kindFromName('Extra virgin olive oil'), FoodKind.fatty);
    expect(HealthScore.kindFromName('Peanut butter'), FoodKind.food);
    expect(HealthScore.fruitVegFromName('Banana'), 100);
    expect(HealthScore.fruitVegFromName('Chicken Salad'), 0);
  });

  test('missing detail is estimated and flagged as partial', () {
    final s = HealthScore.of(const Nutrients(calories: 105, protein: 1.3, carbs: 27, fat: 0.4), name: 'Banana')!;
    expect(s.partial, isTrue);
    expect(s.score, greaterThan(60)); // a banana still reads as good with only macros
  });

  test('the score follows the goal in the profile', () async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    await s.load(seedSampleIfEmpty: true);
    s.updateProfileAndPlan((p) => p.goal = WeightGoal.gain);
    expect(HealthScore.goal, WeightGoal.gain);
    s.updateProfileAndPlan((p) => p.goal = WeightGoal.lose);
    expect(HealthScore.goal, WeightGoal.lose);
  });

  test('a day is weighted by calories', () {
    final good = HealthScore.of(
      const Nutrients(calories: 34, protein: 2.8, carbs: 7, fiber: 2.6, sugar: 1.7, sodium: 33),
      grams: 100,
      detailChecked: true,
      fruitVeg: 100,
    );
    final bad = HealthScore.of(
      const Nutrients(calories: 536, protein: 7, carbs: 59, fat: 30, fiber: 2, sugar: 51, satFat: 18.6, sodium: 80),
      grams: 100,
      detailChecked: true,
    );
    expect(HealthScore.average([(good, 34), (bad, 536)]), lessThan(20));
  });
}
