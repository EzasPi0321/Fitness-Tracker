import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/design/tokens.dart';
import 'package:fittrack/models/util.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:fittrack/widgets/water_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the pencil lists the day’s drinks; any one can be removed, and the box starts empty', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    final today = startOfDay(DateTime.now());
    await s.addWater(250, today.add(const Duration(hours: 8)));
    await s.addWater(500, today.add(const Duration(hours: 12)));
    await tester.pumpWidget(
      AppScope(
        state: s,
        child: MaterialApp(
          theme: buildTheme(FT.darkTheme()),
          home: Scaffold(
            body: SingleChildScrollView(child: WaterCard(day: today)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Other amount, or remove a drink'));
    await tester.pumpAndSettle();
    expect(find.text('Today’s drinks'), findsOneWidget);
    expect(find.text('330'), findsNothing); // no example value that looks typed in

    // Remove the morning glass, not just the last one.
    await tester.tap(find.byTooltip('Remove 250 ml'));
    await tester.pumpAndSettle();
    expect(s.waterTotalOn(today), 500);

    // Add another amount from the same sheet.
    await tester.enterText(find.byType(TextField), '330');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(s.waterTotalOn(today), 830);
    await tester.pump(const Duration(seconds: 4)); // toasts and the delayed save finish
  });
}
