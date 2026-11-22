import 'package:fittrack/models/food.dart';
import 'package:fittrack/screens/log/snap_meal_screen.dart';
import 'package:fittrack/services/ai_vision.dart';
import 'package:flutter_test/flutter_test.dart';

DetectedFood part(String name, String? dish, double g, double kcal, {double p = 0, double fv = 0}) => DetectedFood(
  name: name,
  dish: dish,
  grams: g,
  calories: kcal,
  protein: p,
  carbs: 0,
  fat: 0,
  confidence: 0.9,
  fruitVeg: fv,
);

void main() {
  final at = DateTime(2026, 11, 22, 19);

  test('a pizza photo is logged as the pizza, with its parts inside', () {
    final e = dishEntry(
      [
        part('Pizza base', 'Meat lovers pizza', 150, 400, p: 12),
        part('Mozzarella', 'Meat lovers pizza', 60, 180, p: 13),
        part('Pepperoni', 'Meat lovers pizza', 30, 150, p: 6),
      ],
      meal: MealType.dinner,
      at: at,
    );
    expect(e.name, 'Meat lovers pizza');
    expect(e.nutrients.calories, 730);
    expect(e.nutrients.protein, 31);
    expect(e.grams, 240);
    expect(e.components!.map((c) => c.name), ['Pizza base', 'Mozzarella', 'Pepperoni']);
  });

  test('a food on its own has no breakdown', () {
    final e = dishEntry([part('Apple', 'Apple', 180, 95, fv: 100)], meal: MealType.snack, at: at);
    expect(e.name, 'Apple');
    expect(e.components, isNull);
    expect(e.fruitVeg, 100);
  });

  test('the dish is read from the AI answer, and missing means the food itself', () {
    final a = AIVisionService.decodeAnalysis('''
{"items": [
 {"name": "Pizza base", "dish": "Meat lovers pizza", "estimated_grams": 150, "calories": 400, "protein_g": 12,
  "carbs_g": 60, "fat_g": 10, "fiber_g": 2, "sugar_g": 3, "sat_fat_g": 3, "sodium_mg": 500,
  "fruit_veg_percent": 0, "confidence": 0.8},
 {"name": "Cola", "estimated_grams": 375, "calories": 160, "protein_g": 0, "carbs_g": 40, "fat_g": 0,
  "fiber_g": 0, "sugar_g": 40, "sat_fat_g": 0, "sodium_mg": 20, "fruit_veg_percent": 0, "confidence": 0.9}
], "notes": ""}''');
    expect(a.items[0].dishName, 'Meat lovers pizza');
    expect(a.items[1].dishName, 'Cola');
  });

  test('parts survive saving, and follow a new portion', () {
    final e = dishEntry(
      [part('Base', 'Pizza', 100, 300), part('Cheese', 'Pizza', 50, 150)],
      meal: MealType.dinner,
      at: at,
    );
    final back = FoodEntry.fromJson(e.toJson());
    expect(back.components!.length, 2);
    expect(back.components![1].nutrients.calories, 150);
    back.rescale(75); // half the 150 g
    expect(back.components![0].grams, 50);
    expect(back.components![1].nutrients.calories, 75);
    expect(back.nutrients.calories, 225);
  });
}
