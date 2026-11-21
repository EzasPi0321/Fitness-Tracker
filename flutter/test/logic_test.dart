import 'dart:convert';

import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/sample_data.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/design/oklch.dart';
import 'package:fittrack/models/food.dart';
import 'package:fittrack/models/nutrients.dart';
import 'package:fittrack/models/profile.dart';
import 'package:fittrack/models/util.dart';
import 'package:fittrack/services/ai_vision.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:fittrack/services/open_food_facts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionCalculator (same cases as the iOS tests)', () {
    test('Mifflin–St Jeor male', () {
      expect(NutritionCalculator.bmr(sex: BiologicalSex.male, weightKg: 80, heightCm: 180, age: 30), closeTo(1780, 0.001));
    });

    test('Mifflin–St Jeor female', () {
      expect(NutritionCalculator.bmr(sex: BiologicalSex.female, weightKg: 60, heightCm: 165, age: 25), closeTo(1345.25, 0.001));
    });

    test('plan macros add up to calories', () {
      final plan = NutritionCalculator.plan(
          sex: BiologicalSex.male, age: 30, heightCm: 180, weightKg: 80, activity: ActivityLevel.moderate, goal: WeightGoal.lose);
      expect(plan.tdee, closeTo(1780 * 1.55, 0.01));
      expect(plan.targets.calories, 2260);
      expect(plan.targets.protein, 160);
      final macroKcal = plan.targets.protein * 4 + plan.targets.carbs * 4 + plan.targets.fat * 9;
      expect(macroKcal, closeTo(plan.targets.calories, 15));
    });

    test('plan respects the calorie floor', () {
      final plan = NutritionCalculator.plan(
          sex: BiologicalSex.female, age: 80, heightCm: 150, weightKg: 42, activity: ActivityLevel.sedentary, goal: WeightGoal.lose);
      expect(plan.targets.calories, greaterThanOrEqualTo(1200));
      expect(plan.targets.carbs, greaterThanOrEqualTo(0));
    });
  });

  group('Open Food Facts decoding', () {
    test('string numbers, brand split, derived serving', () {
      final json = jsonDecode('''
        {"status": 1, "code": "3017620422003", "product": {
          "product_name": "Nutella", "brands": "Ferrero, Nutella", "serving_size": "15 g",
          "serving_quantity": "15", "image_front_url": "",
          "nutriments": {"energy-kcal_100g": 539, "proteins_100g": "6,3", "carbohydrates_100g": 57.5, "fat_100g": 30.9}
        }}''');
      final p = OpenFoodFactsService.parseProduct('3017620422003', json)!;
      expect(p.name, 'Nutella');
      expect(p.brand, 'Ferrero');
      expect(p.imageUrl, isNull);
      expect(p.per100g!.protein, closeTo(6.3, 0.001));
      expect(p.perServing!.calories, closeTo(539 * 0.15, 0.01));
      expect(p.nutrientsForGrams(200)!.calories, closeTo(1078, 0.01));
    });

    test('falls back to kilojoules', () {
      final p = OpenFoodFactsService.parseProduct(
          '12345678', jsonDecode('{"status":1,"product":{"product_name":"Oats","nutriments":{"energy_100g":1500}}}'))!;
      expect(p.per100g!.calories, closeTo(1500 / 4.184, 0.01));
      expect(p.perServing, isNull);
    });

    test('not found', () {
      expect(OpenFoodFactsService.parseProduct('1', jsonDecode('{"status":0,"status_verbose":"product not found"}')), isNull);
    });
  });

  group('AI response parsing', () {
    test('decodes fenced JSON and drops invalid items', () {
      const raw = '''```json
{"items":[
  {"name":"Grilled chicken","estimated_grams":150,"calories":248,"protein_g":46,"carbs_g":0,"fat_g":5.4,"confidence":0.9},
  {"name":"","estimated_grams":50,"calories":10,"protein_g":0,"carbs_g":2,"fat_g":0,"confidence":0.2},
  {"name":"Rice","estimated_grams":0,"calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"confidence":0.4}
],"notes":"Oil not visible."}
```''';
      final a = AIVisionService.decodeAnalysis(raw);
      expect(a.items, hasLength(1));
      expect(a.items.first.name, 'Grilled chicken');
      expect(a.notes, 'Oil not visible.');
    });

    test('garbage is rejected with a clear error', () {
      expect(() => AIVisionService.decodeAnalysis('not json'), throwsA(isA<VisionException>()));
    });

    test('schemas differ per provider', () {
      expect(AIVisionService.responseSchema(VisionProvider.gemini)['type'], 'OBJECT');
      expect(AIVisionService.responseSchema(VisionProvider.openAI)['additionalProperties'], false);
    });
  });

  group('FoodEntry', () {
    test('rescale is linear', () {
      final e = FoodEntry(
        id: 'x',
        name: 'Yogurt',
        meal: MealType.breakfast,
        source: EntrySource.manual,
        consumedAt: DateTime(2025),
        quantity: 1,
        unit: 'cup',
        grams: 245,
        nutrients: const Nutrients(calories: 150, protein: 15, carbs: 8, fat: 6),
      );
      e.rescale(1.5);
      expect(e.nutrients.calories, closeTo(225, 0.001));
      expect(e.grams, closeTo(367.5, 0.001));
      expect(e.portionDescription, '1.5 × cup');
    });

    test('suggested meal by hour', () {
      expect(MealType.suggested(DateTime(2025, 1, 1, 8)), MealType.breakfast);
      expect(MealType.suggested(DateTime(2025, 1, 1, 13)), MealType.lunch);
      expect(MealType.suggested(DateTime(2025, 1, 1, 19)), MealType.dinner);
      expect(MealType.suggested(DateTime(2025, 1, 1, 16)), MealType.snack);
    });

    test('negative and non-finite values are cleaned', () {
      const n = Nutrients(calories: -5, protein: double.nan, carbs: double.infinity, fat: 3);
      expect(n.sanitized, const Nutrients(fat: 3));
    });
  });

  group("Postel's law: lenient numbers", () {
    final cases = <String, double?>{
      '150': 150,
      ' 150 kcal': 150,
      '6,3': 6.3,
      '6.3': 6.3,
      '1,234': 1234,
      '1,234.5': 1234.5,
      '1.234,5': 1234.5,
      '1 1/2': 1.5,
      '3/4': 0.75,
      '½': 0.5,
      '1½': 1.5,
      '~200': 200,
      '': null,
      'abc': null,
      '1/0': null,
    };
    cases.forEach((input, expected) {
      test('"$input" → $expected', () {
        final v = parseLenientNumber(input);
        if (expected == null) {
          expect(v, isNull);
        } else {
          expect(v, closeTo(expected, 1e-9));
        }
      });
    });
  });

  group('OKLCH', () {
    test('white and black round-trip', () {
      expect(const Oklch(1, 0, 0).toColor().toARGB32(), 0xFFFFFFFF);
      expect(const Oklch(0, 0, 0).toColor().toARGB32(), 0xFF000000);
    });

    test('out-of-gamut colours are reduced to fit', () {
      final c = const Oklch(0.7, 0.4, 150).toColor();
      expect(c.r, inInclusiveRange(0, 1));
      expect(c.g, inInclusiveRange(0, 1));
    });

    test('gradient stops are interpolated in OKLCH, not sRGB', () {
      final stops = oklchStops([const Oklch(0.6, 0.15, 255), const Oklch(0.6, 0.15, 55)], steps: 4);
      expect(stops, hasLength(5));
      // The middle stays saturated instead of going grey.
      final mid = stops[2];
      final spread = [mid.r, mid.g, mid.b].reduce((a, b) => a > b ? a : b) - [mid.r, mid.g, mid.b].reduce((a, b) => a < b ? a : b);
      expect(spread, greaterThan(0.15));
    });
  });

  group('AppState', () {
    AppState make([MemoryStore? store]) => AppState(store: store ?? MemoryStore(), health: UnsupportedHealthService());

    test('sample data is deterministic and spans 90 days', () {
      final a = SampleData.generate(now: DateTime(2026, 11, 21));
      final b = SampleData.generate(now: DateTime(2026, 11, 21));
      expect(a.entries.length, b.entries.length);
      expect(a.entries.length, greaterThan(200));
      expect(a.weights.first.date.isBefore(DateTime(2026, 8, 30)), isTrue);
    });

    test('persists and reloads the whole document', () async {
      final store = MemoryStore();
      final s = make(store);
      await s.load();
      s.completeOnboarding(UserProfile(weightKg: 72));
      await s.logEntries([
        FoodEntry(
          id: 'a',
          name: 'Apple',
          meal: MealType.snack,
          source: EntrySource.manual,
          consumedAt: DateTime.now(),
          quantity: 1,
          unit: 'serving',
          nutrients: const Nutrients(calories: 95, carbs: 25),
        ),
      ]);
      s.upsertCustomFood(barcode: '123456', name: 'Bar', serving: 'bar', perServing: const Nutrients(calories: 200));
      await s.flush();

      final again = make(store);
      await again.load();
      expect(again.profile!.weightKg, 72);
      expect(again.entries.single.name, 'Apple');
      expect(again.consumedOn(DateTime.now()).calories, 95);
      expect(again.customFoodForBarcode('123456')!.name, 'Bar');
      expect(again.weights, hasLength(1));
    });

    test('a damaged document starts clean instead of crashing', () async {
      final s = make(MemoryStore('{not json'));
      await s.load();
      expect(s.loaded, isTrue);
      expect(s.profile, isNull);
    });

    test('logging bumps the pulse; undo restores', () async {
      final s = make();
      await s.load();
      s.completeOnboarding(UserProfile());
      final e = FoodEntry(
        id: 'b',
        name: 'Toast',
        meal: MealType.breakfast,
        source: EntrySource.manual,
        consumedAt: DateTime.now(),
        quantity: 1,
        unit: 'slice',
        nutrients: const Nutrients(calories: 80),
      );
      final before = s.logPulse.value;
      await s.logEntries([e]);
      expect(s.logPulse.value, before + 1);
      await s.deleteEntry(e);
      expect(s.entries, isEmpty);
      await s.restoreEntry(e);
      expect(s.entries.single.id, 'b');
    });

    test('a later weigh-in updates the profile weight, an older one does not', () async {
      final s = make();
      await s.load();
      s.completeOnboarding(UserProfile(weightKg: 80));
      await s.addWeight(79, DateTime.now().add(const Duration(minutes: 1)));
      expect(s.profile!.weightKg, 79);
      await s.addWeight(90, DateTime(2000));
      expect(s.profile!.weightKg, 79);
    });
  });

  group('Verified / unverified', () {
    Map<String, dynamic> product(List<String> states, {List<String> errors = const [], num kcal = 539}) => {
          'status': 1,
          'product': {
            'product_name': 'Spread',
            'states_tags': states,
            'data_quality_errors_tags': errors,
            'nutriments': {'energy-kcal_100g': kcal, 'proteins_100g': 6.3, 'carbohydrates_100g': 57.5, 'fat_100g': 30.9},
          },
        };

    test('complete, clean and consistent is verified', () {
      final p = OpenFoodFactsService.parseProduct('1', product(['en:nutrition-facts-completed']))!;
      expect(p.trust!.verified, isTrue);
    });

    test('incomplete is unverified with a reason', () {
      final p = OpenFoodFactsService.parseProduct('1', product(['en:nutrition-facts-to-be-completed']))!;
      expect(p.trust!.verified, isFalse);
      expect(p.trust!.note, contains('not marked complete'));
    });

    test('flagged nutrition problems are unverified', () {
      final p = OpenFoodFactsService.parseProduct(
          '1', product(['en:nutrition-facts-completed'], errors: ['en:nutrition-value-over-105-carbohydrates']))!;
      expect(p.trust!.verified, isFalse);
    });

    test('calories that disagree with the macros are unverified', () {
      final p = OpenFoodFactsService.parseProduct('1', product(['en:nutrition-facts-completed'], kcal: 120))!;
      expect(p.trust!.verified, isFalse);
      expect(p.trust!.note, contains("don't match"));
    });

    test('trust survives a save and reload', () {
      final e = FoodEntry(
        id: 't',
        name: 'x',
        meal: MealType.snack,
        source: EntrySource.barcode,
        consumedAt: DateTime(2025),
        quantity: 1,
        unit: 'serving',
        nutrients: const Nutrients(calories: 100),
        trust: const NutritionTrust.unverified('why'),
      );
      final back = FoodEntry.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(back.trust!.verified, isFalse);
      expect(back.trust!.note, 'why');
    });
  });

  group('Nutrition label reading', () {
    test('a kJ-only label is converted to kcal and remembers the printed unit', () {
      final r = AIVisionService.decodeLabel(
          '{"product_name":"Oat bar","brand":"","serving_size":"1 bar (40 g)","serving_grams":40,"basis":"serving",'
          '"energy":836.8,"energy_unit":"kJ","protein_g":4,"carbs_g":28,"fat_g":7,"readable":true}');
      expect(r.perServing.calories, closeTo(200, 0.01));
      expect(r.printedUnit, EnergyUnit.kJ);
      expect(r.servingGrams, 40);
    });

    test('per-100 g labels are turned into per-serving values', () {
      final r = AIVisionService.decodeLabel(
          '{"product_name":"","brand":"","serving_size":"30 g","serving_grams":30,"basis":"100g",'
          '"energy":400,"energy_unit":"kcal","protein_g":10,"carbs_g":60,"fat_g":12,"readable":true}');
      expect(r.perServing.calories, closeTo(120, 0.01));
      expect(r.perServing.carbs, closeTo(18, 0.01));
    });

    test('an unreadable label with no numbers is an error', () {
      expect(
        () => AIVisionService.decodeLabel('{"energy":0,"protein_g":0,"carbs_g":0,"fat_g":0,"readable":false}'),
        throwsA(isA<VisionException>()),
      );
    });
  });

  group('Energy units', () {
    tearDown(() => Energy.unit = EnergyUnit.kcal);

    test('kcal by default, kJ on request, storage unchanged', () {
      expect(Energy.format(100), '100 kcal');
      Energy.unit = EnergyUnit.kJ;
      expect(Energy.format(100), '418 kJ');
      expect(Energy.fromDisplay(418.4), closeTo(100, 1e-9));
      expect(Energy.fieldName, 'Energy');
    });

    test('the choice is saved with the document', () async {
      final store = MemoryStore();
      final s = AppState(store: store, health: UnsupportedHealthService());
      await s.load();
      s.setEnergyUnit(EnergyUnit.kJ);
      await s.flush();
      Energy.unit = EnergyUnit.kcal;
      final again = AppState(store: store, health: UnsupportedHealthService());
      await again.load();
      expect(Energy.unit, EnergyUnit.kJ);
    });
  });

  group('Claude provider', () {
    test('text blocks are joined and thinking blocks ignored', () {
      final text = AIVisionService.claudeText({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'thinking', 'thinking': ''},
          {'type': 'text', 'text': '{"items":[],'},
          {'type': 'text', 'text': '"notes":""}'},
        ],
      });
      expect(AIVisionService.decodeAnalysis(text).items, isEmpty);
    });

    test('a refusal becomes a readable error', () {
      expect(
        () => AIVisionService.claudeText({
          'stop_reason': 'refusal',
          'stop_details': {'type': 'refusal', 'category': 'cyber'},
          'content': [],
        }),
        throwsA(isA<VisionException>().having((e) => e.message, 'message', contains('declined'))),
      );
    });

    test('picking a model picks its provider and key', () async {
      final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
      await s.load();
      expect(s.visionProvider, VisionProvider.claude);
      s.setVisionModel('gpt-4o');
      expect(s.visionProvider, VisionProvider.openAI);
      expect(s.visionProvider.keyLabel, 'OpenAI API key');
      expect(AiModel.byId('unknown').id, 'claude-opus-5-5');
    });
  });

  test('TDEE matches a standard Mifflin–St Jeor calculator (male, 26, 182 lb, 6 ft 0 in)', () {
    final bmr = NutritionCalculator.bmr(
      sex: BiologicalSex.male,
      weightKg: 182 / poundsPerKilogram,
      heightCm: 72 * centimetersPerInch,
      age: 26,
    );
    final expected = {
      ActivityLevel.sedentary: 2212,
      ActivityLevel.light: 2534,
      ActivityLevel.moderate: 2857,
      ActivityLevel.active: 3179,
      ActivityLevel.veryActive: 3502,
    };
    expected.forEach((level, kcal) => expect(NutritionCalculator.tdee(bmr, level), kcal, reason: level.name));
  });

  test('changing the profile goal recalculates targets', () async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    await s.load();
    s.completeOnboarding(UserProfile(
      sex: BiologicalSex.male,
      birthDate: DateTime(DateTime.now().year - 30, 1, 1),
      heightCm: 180,
      weightKg: 80,
      activity: ActivityLevel.moderate,
      goal: WeightGoal.maintain,
    ));
    s.updateProfileAndPlan((p) => p.goal = WeightGoal.maintain);
    final maintain = s.targets.calories;
    s.updateProfileAndPlan((p) => p.goal = WeightGoal.lose);
    expect(s.targets.calories, maintain - 500);
    s.updateProfileAndPlan((p) => p.goal = WeightGoal.gain);
    expect(s.targets.calories, maintain + 300);
    // Out-of-range input doesn't wreck the targets.
    final before = s.targets;
    s.updateProfileAndPlan((p) => p.weightKg = 5);
    expect(s.targets, before);
  });
}
