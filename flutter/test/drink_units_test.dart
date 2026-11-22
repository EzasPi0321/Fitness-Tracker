import 'package:fittrack/data/common_foods.dart';
import 'package:fittrack/models/food.dart';
import 'package:fittrack/models/nutrients.dart';
import 'package:fittrack/services/open_food_facts.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> product(Map<String, dynamic> fields) => {
  'status': 1,
  'product': {
    'product_name': 'Passionfruit drink',
    'nutriments': {'energy-kcal_100g': 40, 'carbohydrates_100g': 10, 'sugars_100g': 9.5},
    ...fields,
  },
};

void main() {
  test('a drink with no serving size uses the bottle, in ml', () {
    final p = OpenFoodFactsService.parseProduct(
      '9300000000001',
      product({'quantity': '375 ml', 'product_quantity': 375, 'product_quantity_unit': 'ml'}),
    )!;
    expect(p.liquid, isTrue);
    expect(p.amountUnit, 'ml');
    expect(p.servingGrams, 375);
    expect(p.servingLabel, 'bottle (375 ml)');
    expect(p.perServing!.calories, 150);
  });

  test('a listed serving wins over the pack', () {
    final p = OpenFoodFactsService.parseProduct(
      '9300000000002',
      product({'quantity': '1.25 L', 'product_quantity': 1250, 'serving_size': '250 ml', 'serving_quantity': 250}),
    )!;
    expect(p.liquid, isTrue);
    expect(p.servingGrams, 250);
    expect(p.servingLabel, '250 ml');
  });

  test('a big pack is not one serving', () {
    final p = OpenFoodFactsService.parseProduct(
      '9300000000003',
      product({'quantity': '2 L', 'product_quantity': 2000, 'product_quantity_unit': 'ml'}),
    )!;
    expect(p.liquid, isTrue);
    expect(p.servingGrams, isNull);
  });

  test('food stays in grams, and a single-serve pack becomes its serving', () {
    final p = OpenFoodFactsService.parseProduct(
      '9300000000004',
      product({'quantity': '40 g', 'product_quantity': 40}),
    )!;
    expect(p.liquid, isFalse);
    expect(p.servingLabel, 'pack (40 g)');
  });

  test('beverages are drinks even without a volume on the pack', () {
    expect(
      OpenFoodFactsService.isLiquid({
        'categories_tags': ['en:beverages', 'en:juices'],
      }),
      isTrue,
    );
    expect(
      OpenFoodFactsService.isLiquid({
        'categories_tags': ['en:beverages', 'en:instant-beverages-powder'],
      }),
      isFalse,
    );
  });

  test('built-in drinks are in ml, and a ml entry reads as ml', () {
    expect(searchCommonFoods('cola').first.liquid, isTrue);
    expect(searchCommonFoods('banana').first.liquid, isFalse);
    final e = FoodEntry(
      id: '1',
      name: 'Juice',
      meal: MealType.snack,
      source: EntrySource.barcode,
      consumedAt: DateTime(2026),
      quantity: 300,
      unit: 'ml',
      nutrients: const Nutrients(calories: 120),
    );
    expect(e.portionDescription, '300 ml');
  });
}
