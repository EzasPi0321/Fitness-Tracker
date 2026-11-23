import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/design/tokens.dart';
import 'package:fittrack/models/food.dart';
import 'package:fittrack/models/nutrients.dart';
import 'package:fittrack/screens/today/edit_entry_sheet.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a servings entry can be changed by weight: 175 g of a 125 g cup', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    final entry = FoodEntry(
      id: 'tteok',
      name: 'Korean Rice Cakes',
      meal: MealType.lunch,
      source: EntrySource.barcode,
      consumedAt: DateTime.now(),
      quantity: 1,
      unit: '1 cup (125 g)',
      grams: 125,
      nutrients: const Nutrients(calories: 280, protein: 6, carbs: 60, fat: 1.5),
    );
    await s.logEntries([entry]);
    await tester.pumpWidget(
      AppScope(
        state: s,
        child: MaterialApp(
          theme: buildTheme(FT.darkTheme()),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showEditEntrySheet(context, entry), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Grams'));
    await tester.pumpAndSettle();
    expect(find.text('1 serving is 125 g'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '175');
    await tester.pumpAndSettle();
    expect(find.text('392 kcal'), findsOneWidget); // 280 × 175 / 125

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(entry.unit, 'g');
    expect(entry.quantity, closeTo(175, 0.01));
    expect(entry.nutrients.calories, closeTo(392, 0.5));
    expect(entry.portionDescription, '175 g');
  });
}
