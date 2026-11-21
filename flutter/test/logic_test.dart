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
import 'package:fittrack/services/label_ocr.dart';
import 'package:fittrack/services/open_food_facts.dart';
import 'package:fittrack/services/updates.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionCalculator (same cases as the iOS tests)', () {
    test('Mifflin–St Jeor male', () {
      expect(
        NutritionCalculator.bmr(sex: BiologicalSex.male, weightKg: 80, heightCm: 180, age: 30),
        closeTo(1780, 0.001),
      );
    });

    test('Mifflin–St Jeor female', () {
      expect(
        NutritionCalculator.bmr(sex: BiologicalSex.female, weightKg: 60, heightCm: 165, age: 25),
        closeTo(1345.25, 0.001),
      );
    });

    test('plan macros add up to calories', () {
      final plan = NutritionCalculator.plan(
        sex: BiologicalSex.male,
        age: 30,
        heightCm: 180,
        weightKg: 80,
        activity: ActivityLevel.moderate,
        goal: WeightGoal.lose,
      );
      expect(plan.tdee, closeTo(1780 * 1.55, 0.01));
      expect(plan.targets.calories, 2260);
      expect(plan.targets.protein, 160);
      final macroKcal = plan.targets.protein * 4 + plan.targets.carbs * 4 + plan.targets.fat * 9;
      expect(macroKcal, closeTo(plan.targets.calories, 15));
    });

    test('plan respects the calorie floor', () {
      final plan = NutritionCalculator.plan(
        sex: BiologicalSex.female,
        age: 80,
        heightCm: 150,
        weightKg: 42,
        activity: ActivityLevel.sedentary,
        goal: WeightGoal.lose,
      );
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
        '12345678',
        jsonDecode('{"status":1,"product":{"product_name":"Oats","nutriments":{"energy_100g":1500}}}'),
      )!;
      expect(p.per100g!.calories, closeTo(1500 / 4.184, 0.01));
      expect(p.perServing, isNull);
    });

    test('not found', () {
      expect(
        OpenFoodFactsService.parseProduct('1', jsonDecode('{"status":0,"status_verbose":"product not found"}')),
        isNull,
      );
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
      final spread =
          [mid.r, mid.g, mid.b].reduce((a, b) => a > b ? a : b) - [mid.r, mid.g, mid.b].reduce((a, b) => a < b ? a : b);
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
        '1',
        product(['en:nutrition-facts-completed'], errors: ['en:nutrition-value-over-105-carbohydrates']),
      )!;
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
        '"energy":836.8,"energy_unit":"kJ","protein_g":4,"carbs_g":28,"fat_g":7,"readable":true}',
      );
      expect(r.perServing.calories, closeTo(200, 0.01));
      expect(r.printedUnit, EnergyUnit.kJ);
      expect(r.servingGrams, 40);
    });

    test('per-100 g labels are turned into per-serving values', () {
      final r = AIVisionService.decodeLabel(
        '{"product_name":"","brand":"","serving_size":"30 g","serving_grams":30,"basis":"100g",'
        '"energy":400,"energy_unit":"kcal","protein_g":10,"carbs_g":60,"fat_g":12,"readable":true}',
      );
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
    s.completeOnboarding(
      UserProfile(
        sex: BiologicalSex.male,
        birthDate: DateTime(DateTime.now().year - 30, 1, 1),
        heightCm: 180,
        weightKg: 80,
        activity: ActivityLevel.moderate,
        goal: WeightGoal.maintain,
      ),
    );
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

  group('Water', () {
    test('goal follows body weight until set, entries add up per day, undo removes the last', () async {
      final store = MemoryStore();
      final s = AppState(store: store, health: UnsupportedHealthService());
      await s.load();
      s.completeOnboarding(UserProfile(weightKg: 80));
      expect(s.waterGoal, 2800); // 80 kg × 35 ml
      final now = DateTime.now();
      await s.addWater(250, now);
      await s.addWater(500, now);
      await s.addWater(330, now.subtract(const Duration(days: 1)));
      expect(s.waterTotalOn(now), 750);
      expect(s.undoWater(now)!.ml, 500);
      expect(s.waterTotalOn(now), 250);
      s.setWaterGoal(2000);
      await s.flush();
      final again = AppState(store: store, health: UnsupportedHealthService());
      await again.load();
      expect(again.waterGoal, 2000);
      expect(again.water, hasLength(2));
    });

    test('volumes read naturally in both unit systems', () {
      expect(Volume.format(250, metric: true), '250 ml');
      expect(Volume.format(2500, metric: true), '2.5 L');
      expect(Volume.format(2000, metric: true), '2 L');
      expect(Volume.format(8 * mlPerFluidOunce, metric: false), '8 fl oz');
    });
  });

  test('greeting and initials come from the profile name', () {
    expect(greeting(DateTime(2026, 1, 1, 8), 'Daniel'), 'Good morning, Daniel');
    expect(greeting(DateTime(2026, 1, 1, 14), ''), 'Good afternoon');
    expect(greeting(DateTime(2026, 1, 1, 21), ' Sam '), 'Good evening, Sam');
    expect(UserProfile(name: 'Daniel Xie').initials, 'DX');
    expect(UserProfile(name: 'Daniel Xie').firstName, 'Daniel');
    expect(UserProfile().initials, '');
    final back = UserProfile.fromJson(UserProfile(name: 'Kai').toJson());
    expect(back.name, 'Kai');
  });

  test('portions read naturally', () {
    FoodEntry e(double q, String unit) => FoodEntry(
      id: 'p',
      name: 'x',
      meal: MealType.snack,
      source: EntrySource.manual,
      consumedAt: DateTime(2025),
      quantity: q,
      unit: unit,
      nutrients: Nutrients.zero,
    );
    expect(e(1, 'serving').portionDescription, '1 serving');
    expect(e(2, 'serving').portionDescription, '2 servings');
    expect(e(150, 'g').portionDescription, '150 g');
    expect(e(1.5, 'cup').portionDescription, '1.5 × cup');
  });

  test('step goal and sample steps', () async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    await s.load(seedSampleIfEmpty: true);
    expect(s.sampleSteps[startOfDay(DateTime.now())], 6240);
    s.setStepGoal(8000);
    expect(s.stepGoal, 8000);
    s.setStepGoal(0); // ignored
    expect(s.stepGoal, 8000);
  });

  group('Updates', () {
    final release = {
      'tag_name': 'v2.0.0-build12',
      'html_url': 'https://github.com/EzasPi0321/Fitness-Tracker/releases/tag/v2.0.0-build12',
      'body': 'Add water tracking\n\nMore notes',
      'assets': [
        {'name': 'FitTrack.apk', 'browser_download_url': 'https://example.test/FitTrack.apk'},
        {'name': 'FitTrack-Windows.zip', 'browser_download_url': 'https://example.test/FitTrack-Windows.zip'},
      ],
    };

    test('a newer build is offered with the right file per platform', () {
      final android = UpdateService.parseRelease(
        release,
        currentBuild: 7,
        platform: TargetPlatform.android,
        web: false,
      )!;
      expect(android.build, 12);
      expect(android.version, '2.0.0');
      expect(android.downloadUrl, endsWith('FitTrack.apk'));
      expect(android.notes, 'Add water tracking');
      final windows = UpdateService.parseRelease(
        release,
        currentBuild: 7,
        platform: TargetPlatform.windows,
        web: false,
      )!;
      expect(windows.downloadUrl, endsWith('FitTrack-Windows.zip'));
      final ios = UpdateService.parseRelease(release, currentBuild: 7, platform: TargetPlatform.iOS, web: false)!;
      expect(ios.downloadUrl, isNull); // opens the release page instead
    });

    test('the same or an older build is not offered', () {
      expect(
        UpdateService.parseRelease(release, currentBuild: 12, platform: TargetPlatform.android, web: false),
        isNull,
      );
      expect(
        UpdateService.parseRelease(
          {'tag_name': 'nightly'},
          currentBuild: 1,
          platform: TargetPlatform.android,
          web: false,
        ),
        isNull,
      );
    });

    test('a dismissed update hides the banner until a newer one arrives', () async {
      final s = AppState(store: MemoryStore(), health: UnsupportedHealthService(), updates: _FakeUpdates(12));
      await s.load();
      await s.checkForUpdates(manual: true);
      expect(s.showUpdateBanner, isTrue);
      s.dismissUpdate();
      expect(s.showUpdateBanner, isFalse);
      (s.updates as _FakeUpdates).build = 13;
      await s.checkForUpdates(manual: true);
      expect(s.showUpdateBanner, isTrue);
    });
  });
  group('On-device label reading', () {
    test('US panel, values on the same line', () {
      final r = LabelOcr.parse('''
Nutrition Facts
8 servings per container
Serving size 2 tbsp (32g)
Amount per serving
Calories 190
% Daily Value*
Total Fat 16g 21%
Saturated Fat 3g 15%
Trans Fat 0g
Sodium 140mg 6%
Total Carbohydrate 8g 3%
Dietary Fiber 2g 7%
Total Sugars 3g
Protein 7g
''')!;
      expect(r.perServing.calories, 190);
      expect(r.perServing.fat, 16);
      expect(r.perServing.carbs, 8);
      expect(r.perServing.protein, 7);
      expect(r.servingGrams, 32);
      expect(r.readable, isTrue);
    });

    test('EU panel per 100 g with kJ and kcal, values split onto the next line', () {
      final r = LabelOcr.parse('''
Nutrition information per 100g
Energy
2252 kJ / 539 kcal
Fat
30,9 g
of which saturates
10,6 g
Carbohydrate
57,5 g
of which sugars
56,3 g
Protein
6,3 g
''')!;
      expect(r.perServing.calories, 539);
      expect(r.perServing.fat, closeTo(30.9, 1e-9));
      expect(r.perServing.carbs, closeTo(57.5, 1e-9));
      expect(r.perServing.protein, closeTo(6.3, 1e-9));
      expect(r.servingGrams, 100);
      expect(r.servingDescription, '100 g');
    });

    test('a kJ-only label is converted', () {
      final r = LabelOcr.parse('Energy 836.8 kJ\nProtein 4 g\nFat 7 g\nCarbohydrate 28 g')!;
      expect(r.perServing.calories, closeTo(200, 0.01));
      expect(r.printedUnit, EnergyUnit.kJ);
    });

    test('Australian panel read row by row (kJ with Cal, "Fat, total", two columns)', () {
      final r = LabelOcr.parse('''
NUTRITION INFORMATION
Servings per package: 8
Serving size: 30 g
Avg. Quantity per Serving Avg. Quantity per 100 g
Energy 540 kJ (129 Cal) 1800 kJ (430 Cal)
Protein 3.2 g 10.7 g
Fat, total 2.1 g 7.0 g
- saturated 0.4 g 1.3 g
Carbohydrate 19.8 g 66.0 g
- sugars 4.5 g 15.0 g
Dietary Fibre 2.9 g 9.7 g
Sodium 95 mg 317 mg
''')!;
      expect(r.perServing.calories, 129); // the per-serving column, not per 100 g
      expect(r.perServing.protein, closeTo(3.2, 1e-9));
      expect(r.perServing.fat, closeTo(2.1, 1e-9));
      expect(r.perServing.carbs, closeTo(19.8, 1e-9));
      expect(r.servingGrams, 30);
      expect(r.readable, isTrue);
    });

    test('Australian panel read column by column (names first, then values)', () {
      final r = LabelOcr.parse('''
NUTRITION INFORMATION
Servings per package: 5
Serving size: 40 g
Energy
Protein
Fat, total
- saturated
Carbohydrate
- sugars
Sodium
Avg. Quantity per Serving
628 kJ
4.1 g
5.6 g
1.0 g
21.2 g
6.3 g
120 mg
Avg. Quantity per 100 g
1570 kJ
10.3 g
14.0 g
2.5 g
53.0 g
15.8 g
300 mg
''')!;
      expect(r.perServing.calories, closeTo(628 / 4.184, 0.01));
      expect(r.printedUnit, EnergyUnit.kJ);
      expect(r.perServing.protein, closeTo(4.1, 1e-9));
      expect(r.perServing.fat, closeTo(5.6, 1e-9)); // not the "- saturated" 1.0 g
      expect(r.perServing.carbs, closeTo(21.2, 1e-9)); // not the "- sugars" 6.3 g
      expect(r.servingGrams, 40);
    });

    test('Australian kJ-only panel with no Cal figure', () {
      final r = LabelOcr.parse('''
Serving size: 250 mL
Energy 420kJ 168kJ
Protein 8.5g 3.4g
Fat, total 9.8g 3.9g
Carbohydrate 12.0g 4.8g
''')!;
      expect(r.perServing.calories, closeTo(420 / 4.184, 0.01));
      expect(r.perServing.fat, closeTo(9.8, 1e-9));
    });

    test('text that is not a nutrition panel gives nothing', () {
      expect(LabelOcr.parse('Ingredients: oats, honey, almonds'), isNull);
    });
  });

  test('connecting with only some health permissions still syncs, and says what is missing', () async {
    final s = AppState(store: MemoryStore(), health: _PartialHealth());
    await s.load();
    s.completeOnboarding(UserProfile());
    final before = s.healthRefresh.value;
    await s.setHealthEnabled(true);
    expect(s.healthEnabled, isTrue);
    expect(s.healthError, isNull);
    expect(s.healthMissing, ['Water']);
    expect(s.healthRefresh.value, greaterThan(before)); // screens re-read steps
  });
}

class _PartialHealth extends UnsupportedHealthService {
  @override
  bool get isSupported => true;
  @override
  List<String> get readNames => const ['Steps', 'Weight', 'Water'];
  @override
  Future<bool> requestAuthorization() async => true;
  @override
  Future<Set<String>?> grantedReads() async => {'Steps', 'Weight'};
  @override
  Future<int?> steps(DateTime day) async => 4210;
}

class _FakeUpdates extends UpdateService {
  _FakeUpdates(this.build);
  int build;
  @override
  Future<AppUpdate?> check({int currentBuild = appBuild}) async =>
      AppUpdate(version: '2.0.0', build: build, notes: 'notes', downloadUrl: null, pageUrl: 'https://example.test');
}
