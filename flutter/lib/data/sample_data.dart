import 'dart:math';

import '../models/food.dart';
import '../models/nutrients.dart';
import '../models/profile.dart';
import '../models/util.dart';

/// Realistic example data for the desktop preview and "Try with sample data".
/// Deterministic, so screenshots and the preview look the same every time.
class SampleData {
  SampleData._(this.profile, this.entries, this.weights, this.customFoods, this.water, this.steps);

  final UserProfile profile;
  final List<FoodEntry> entries;
  final List<WeightEntry> weights;
  final List<CustomFood> customFoods;
  final List<WaterEntry> water;
  final Map<DateTime, int> steps;

  static SampleData generate({DateTime? now}) {
    final rnd = Random(20261121);
    final today = startOfDay(now ?? DateTime.now());
    var n = 0;
    String id() => 'sample-${n++}';

    // name, brand, kcal, protein, carbs, fat, source
    const foods = <MealType, List<(String, String?, double, double, double, double, EntrySource)>>{
      MealType.breakfast: [
        ('Greek Yogurt', 'Fage', 150, 15, 8, 6, EntrySource.barcode),
        ('Oatmeal with Berries', null, 310, 10, 54, 6, EntrySource.manual),
        ('Scrambled Eggs', null, 180, 12, 2, 14, EntrySource.photoAI),
        ('Banana', null, 105, 1.3, 27, 0.4, EntrySource.manual),
        ('Whole-Grain Toast', "Dave's Killer Bread", 160, 7, 28, 2, EntrySource.barcode),
      ],
      MealType.lunch: [
        ('Chicken Salad', null, 480, 42, 18, 26, EntrySource.photoAI),
        ('Turkey Wrap', null, 430, 30, 42, 14, EntrySource.manual),
        ('Salmon Rice Bowl', null, 620, 35, 70, 18, EntrySource.photoAI),
        ('Lentil Soup', "Amy's", 320, 18, 46, 7, EntrySource.barcode),
      ],
      MealType.dinner: [
        ('Spaghetti Bolognese', null, 650, 32, 78, 20, EntrySource.photoAI),
        ('Steak & Potatoes', null, 720, 52, 45, 34, EntrySource.manual),
        ('Chicken Stir-Fry', null, 540, 38, 55, 16, EntrySource.photoAI),
        ('Veggie Burrito', null, 590, 22, 82, 18, EntrySource.manual),
      ],
      MealType.snack: [
        ('Protein Bar', 'Quest', 210, 20, 22, 7, EntrySource.barcode),
        ('Apple', null, 95, 0.5, 25, 0.3, EntrySource.manual),
        ('Almonds', null, 164, 6, 6, 14, EntrySource.customFood),
        ('Cottage Cheese', 'Good Culture', 140, 19, 6, 4, EntrySource.barcode),
      ],
    };
    const hours = {MealType.breakfast: 8.0, MealType.lunch: 12.5, MealType.dinner: 19.0, MealType.snack: 15.5};

    FoodEntry make(
      (String, String?, double, double, double, double, EntrySource) f,
      MealType meal,
      DateTime day, [
      double qty = 1,
    ]) {
      final minutes = (hours[meal]! * 60).round() + rnd.nextInt(40);
      return FoodEntry(
        id: id(),
        name: f.$1,
        brand: f.$2,
        meal: meal,
        source: f.$7,
        consumedAt: day.add(Duration(minutes: minutes)),
        quantity: qty,
        unit: 'serving',
        nutrients: Nutrients(calories: f.$3, protein: f.$4, carbs: f.$5, fat: f.$6) * qty,
      );
    }

    T pick<T>(List<T> l) => l[rnd.nextInt(l.length)];

    final entries = <FoodEntry>[
      make(foods[MealType.breakfast]![0], MealType.breakfast, today),
      make(foods[MealType.breakfast]![3], MealType.breakfast, today),
      make(foods[MealType.lunch]![0], MealType.lunch, today),
      make(foods[MealType.snack]![0], MealType.snack, today),
    ];
    for (var d = 1; d <= 89; d++) {
      if (rnd.nextDouble() < 0.14) continue; // an unlogged day
      final day = addDays(today, -d);
      entries.add(make(pick(foods[MealType.breakfast]!), MealType.breakfast, day));
      if (rnd.nextDouble() < 0.5) entries.add(make(pick(foods[MealType.breakfast]!), MealType.breakfast, day));
      entries.add(make(pick(foods[MealType.lunch]!), MealType.lunch, day, rnd.nextDouble() < 0.35 ? 1.5 : 1));
      entries.add(make(pick(foods[MealType.dinner]!), MealType.dinner, day, rnd.nextDouble() < 0.25 ? 1.25 : 1));
      final snacks = 1 + rnd.nextInt(3);
      for (var i = 0; i < snacks; i++) {
        entries.add(make(pick(foods[MealType.snack]!), MealType.snack, day));
      }
    }

    final weights = <WeightEntry>[];
    for (var d = 88; d >= 0; d -= 3) {
      final kg = 70 + d * 0.026 + (rnd.nextDouble() - 0.5) * 0.6;
      weights.add(
        WeightEntry(
          id: id(),
          date: addDays(today, -d).add(const Duration(hours: 7)),
          kilograms: (kg * 10).round() / 10,
        ),
      );
    }

    final profile = UserProfile(
      name: 'Priya Nair',
      sex: BiologicalSex.female,
      birthDate: DateTime(today.year - 30, 1, 1),
      heightCm: 170,
      weightKg: weights.last.kilograms,
    );
    profile.targets = profile.plan.targets;

    final custom = [
      CustomFood(
        id: id(),
        name: 'Almonds',
        servingDescription: 'handful (28 g)',
        servingGrams: 28,
        perServing: const Nutrients(calories: 164, protein: 6, carbs: 6, fat: 14),
        useCount: 12,
      ),
      CustomFood(
        id: id(),
        name: 'Overnight Oats',
        servingDescription: 'jar',
        servingGrams: 250,
        perServing: const Nutrients(calories: 380, protein: 18, carbs: 52, fat: 10),
        useCount: 5,
      ),
    ];

    final water = <WaterEntry>[
      WaterEntry(id: id(), at: today.add(const Duration(hours: 8, minutes: 5)), ml: 250),
      WaterEntry(id: id(), at: today.add(const Duration(hours: 12, minutes: 40)), ml: 500),
    ];
    for (var d = 1; d <= 30; d++) {
      final day = addDays(today, -d);
      final glasses = 4 + rnd.nextInt(6);
      for (var g = 0; g < glasses; g++) {
        water.add(
          WaterEntry(
            id: id(),
            at: day.add(Duration(hours: 7 + g * 2)),
            ml: rnd.nextBool() ? 250 : 500,
          ),
        );
      }
    }

    final steps = <DateTime, int>{today: 6240};
    for (var d = 1; d <= 90; d++) {
      steps[addDays(today, -d)] = 4000 + rnd.nextInt(9000);
    }

    return SampleData._(profile, entries, weights, custom, water, steps);
  }
}
