import 'package:fittrack/models/food.dart';
import 'package:fittrack/screens/log/voice_entry_screen.dart';
import 'package:fittrack/services/ai_vision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spoken meals keep each item with its own meal, even the same food twice', () {
    final r = AIVisionService.decodeSpokenMeals('''
{"items": [
  {"meal": "breakfast", "name": "toast", "estimated_grams": 60, "calories": 160, "protein_g": 6, "carbs_g": 28, "fat_g": 2, "fiber_g": 2, "sugar_g": 2, "confidence": 0.9},
  {"meal": "breakfast", "name": "scrambled eggs", "estimated_grams": 120, "calories": 180, "protein_g": 13, "carbs_g": 1, "fat_g": 13, "fiber_g": 0, "sugar_g": 1, "confidence": 0.85},
  {"meal": "lunch", "name": "toast", "estimated_grams": 30, "calories": 80, "protein_g": 3, "carbs_g": 14, "fat_g": 1, "fiber_g": 1, "sugar_g": 1, "confidence": 0.9},
  {"meal": "dinner", "name": "spaghetti bolognese", "estimated_grams": 400, "calories": 560, "protein_g": 30, "carbs_g": 70, "fat_g": 16, "fiber_g": 6, "sugar_g": 9, "confidence": 0.7},
  {"meal": "dinner", "name": "", "estimated_grams": 0, "calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0, "fiber_g": 0, "sugar_g": 0, "confidence": 0}
], "notes": "Assumed a standard serve of pasta."}
''');
    expect(r.items.map((i) => i.meal), [MealType.breakfast, MealType.breakfast, MealType.lunch, MealType.dinner]);
    expect(r.items.map((i) => i.food.name), contains('Scrambled eggs')); // AI names come back sentence-cased
    expect(r.items[2].food.grams, 30); // lunch toast is its own item, not the breakfast one
    expect(r.notes, contains('pasta'));
    expect(r.needsCarefulLook, isFalse);
  });

  test('nothing found asks the careful model to look', () {
    expect(AIVisionService.decodeSpokenMeals('{"items": [], "notes": ""}').needsCarefulLook, isTrue);
  });

  test('meal times: now for the current meal today, usual hours otherwise', () {
    final now = DateTime(2026, 11, 22, 13, 5);
    final today = DateTime(2026, 11, 22);
    expect(mealTime(today, MealType.lunch, now: now), now);
    expect(mealTime(today, MealType.breakfast, now: now), DateTime(2026, 11, 22, 8));
    expect(mealTime(DateTime(2026, 11, 21), MealType.lunch, now: now), DateTime(2026, 11, 21, 12, 30));
    expect(mealTime(today, MealType.dinner, now: now), DateTime(2026, 11, 22, 18, 30));
  });

  test('voice is a source that survives saving', () {
    expect(EntrySource.parse('voice'), EntrySource.voice);
  });
}
