import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/models/food.dart';
import 'package:fittrack/models/nutrients.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FoodEntry banana({double kcal = 105, String? barcode}) => FoodEntry(
    id: 'b$kcal',
    name: 'Banana',
    barcode: barcode,
    meal: MealType.snack,
    source: EntrySource.manual,
    consumedAt: DateTime(2026, 11, 22, 15),
    quantity: 1,
    unit: 'serving',
    nutrients: Nutrients(calories: kcal, protein: 1.3 * kcal / 105, carbs: 27 * kcal / 105, fat: 0.4 * kcal / 105),
  );

  Future<AppState> fresh(MemoryStore store) async {
    final s = AppState(store: store, health: UnsupportedHealthService());
    await s.load();
    return s;
  }

  test('a food filled in before is filled again for free, scaled to the portion', () async {
    final s = await fresh(MemoryStore());
    // What an earlier AI answer left behind: 118 g, 3.1 g fibre, 14 g sugar for 105 kcal.
    s.detailCache[AppState.detailKey(banana())] = const FoodDetailRates(
      gramsPerKcal: 118 / 105,
      fiberPerKcal: 3.1 / 105,
      sugarPerKcal: 14 / 105,
    );
    final big = banana(kcal: 210); // two bananas' worth
    await s.logEntries([big]); // no API key in tests: only the memory can fill it
    await Future<void>.delayed(Duration.zero);
    expect(big.detailChecked, isTrue);
    expect(big.grams, closeTo(236, 0.5));
    expect(big.nutrients.fiber, closeTo(6.2, 0.05));
    expect(big.nutrients.sugar, closeTo(28, 0.05));
  });

  test('foods are matched by barcode first, then by name and brand, ignoring case and spacing', () {
    expect(AppState.detailKey(banana(barcode: '9300633')), 'b:9300633');
    final a = FoodEntry.fromJson(banana().toJson()..['name'] = '  BANANA ');
    expect(AppState.detailKey(a), AppState.detailKey(banana()));
  });

  test('the memory survives a restart', () async {
    final store = MemoryStore();
    final a = await fresh(store);
    a.detailCache['n:banana|'] = const FoodDetailRates(gramsPerKcal: 1.1, fiberPerKcal: 0.03, sugarPerKcal: 0.13);
    a.setSleepGoal(8); // any change saves
    await a.flush();
    final b = await fresh(store);
    expect(b.detailCache['n:banana|']?.fiberPerKcal, 0.03);
  });
}
