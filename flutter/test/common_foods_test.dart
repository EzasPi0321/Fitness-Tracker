import 'package:fittrack/data/common_foods.dart';
import 'package:fittrack/models/food.dart';
import 'package:fittrack/services/open_food_facts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('banana finds the banana first', () {
    final r = searchCommonFoods('banana');
    expect(r.first.name, 'Banana');
    expect(r.first.perServing!.calories, closeTo(105, 1)); // a medium banana
  });

  test('plurals, other names and partial words find their food', () {
    expect(searchCommonFoods('bananas').first.name, 'Banana');
    expect(searchCommonFoods('shrimp').first.name, 'Prawns, cooked');
    expect(searchCommonFoods('rice').map((p) => p.name), containsAll(['White rice, cooked', 'Brown rice, cooked']));
    expect(searchCommonFoods('eggs').first.name, 'Egg');
    expect(searchCommonFoods('rice').first.name, 'White rice, cooked');
    expect(searchCommonFoods('chick').map((p) => p.name), contains('Chicken breast, cooked'));
    expect(searchCommonFoods('x'), isEmpty);
    expect(searchCommonFoods('quokka'), isEmpty);
  });

  test('every built-in food has energy that matches its macros', () {
    const alcohol = {'Beer', 'Red wine', 'White wine', 'Cider', 'Spirits'}; // alcohol carries energy the macros don't
    for (final p in allCommonFoods) {
      if (alcohol.contains(p.name)) continue;
      final n = p.per100g!;
      final fromMacros = n.protein * 4 + n.carbs * 4 + n.fat * 9;
      expect(
        (fromMacros - n.calories).abs(),
        lessThanOrEqualTo(n.calories * 0.15 + 12),
        reason: '${p.name}: ${n.calories} kcal vs ${fromMacros.round()} from macros',
      );
      expect(n.sugar, lessThanOrEqualTo(n.carbs + 0.01), reason: p.name);
      expect(n.satFat, lessThanOrEqualTo(n.fat + 0.01), reason: p.name);
      expect(p.servingGrams, greaterThan(0), reason: p.name);
    }
  });

  test('packaged results named after the search come first', () {
    FoodProduct p(String name) => FoodProduct(barcode: name, name: name);
    final ranked = OpenFoodFactsService.rankByName([p('Smoothie mango'), p('Banana chips'), p('Bananas')], 'banana');
    expect(ranked.map((e) => e.name), ['Banana chips', 'Bananas', 'Smoothie mango']);
  });
}
