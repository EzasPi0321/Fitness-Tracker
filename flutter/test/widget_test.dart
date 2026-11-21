import 'package:fittrack/app.dart';
import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppState> _state({bool sample = false}) async {
  final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
  await s.load(seedSampleIfEmpty: sample);
  return s;
}

Future<void> _pump(WidgetTester tester, AppState s, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FitTrackApp(state: s));
  await tester.pumpAndSettle();
}

final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  testWidgets('first run shows onboarding and finishes into Today', (tester) async {
    final s = await _state();
    await _pump(tester, s, const Size(400, 860));

    expect(find.text('Set up my plan'), findsOneWidget);
    await tester.tap(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    expect(find.text('About you'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Your plan'), findsOneWidget);
    await tester.tap(find.text('Start tracking'));
    await tester.pumpAndSettle();

    expect(s.profile, isNotNull);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Breakfast'), findsOneWidget);
  }, variant: desktop);

  testWidgets('sample data dashboard on a phone, then Progress and Settings', (tester) async {
    final s = await _state(sample: true);
    await _pump(tester, s, const Size(400, 860));

    expect(find.textContaining('sample data'), findsOneWidget);
    expect(find.text('kcal left'), findsOneWidget);
    expect(find.textContaining(', Alex'), findsOneWidget); // greeting uses the profile name
    // Water: one tap adds a glass.
    await tester.ensureVisible(find.text('250 ml'));
    await tester.pumpAndSettle();
    final before = s.waterTotalOn(DateTime.now());
    await tester.tap(find.text('250 ml'));
    await tester.pumpAndSettle();
    expect(s.waterTotalOn(DateTime.now()), before + 250);
    expect(find.text('Protein'), findsWidgets);

    await tester.tap(find.text('Progress').last);
    await tester.pumpAndSettle();
    expect(find.text('Calorie intake'), findsOneWidget);
    await tester.tap(find.text('30D'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/30'), findsOneWidget);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsWidgets); // the sample profile's name
    expect(find.text('AL'), findsNothing);
    expect(find.text('A'), findsOneWidget); // initials avatar
    expect(find.text('Cut'), findsOneWidget);
    await tester.tap(find.text('Cut'));
    await tester.pumpAndSettle();
    expect(s.profile!.goal.name, 'lose');
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Phone only'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Phone only'), findsOneWidget);
  }, variant: desktop);

  testWidgets('add menu opens, offers three choices, and manual entry logs food', (tester) async {
    final s = await _state(sample: true);
    await _pump(tester, s, const Size(400, 860));
    final before = s.entries.length;

    await tester.tap(find.bySemanticsLabel('Log food'));
    await tester.pumpAndSettle();
    expect(find.text('Manual entry'), findsOneWidget);
    expect(find.text('Enter barcode'), findsOneWidget); // desktop/test: no camera
    expect(find.text('Photo estimate'), findsOneWidget);

    // Tapping outside closes it (the scrim covers the page).
    await tester.tapAt(const Offset(40, 300));
    await tester.pumpAndSettle();
    expect(find.text('Manual entry'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Log food'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Granola');
    // Calories field accepts messy input (Postel's law).
    await tester.scrollUntilVisible(find.text('Calories'), 200, scrollable: find.byType(Scrollable).last);
    final calories = find.ancestor(of: find.text('Calories'), matching: find.byType(Row)).first;
    await tester.enterText(find.descendant(of: calories, matching: find.byType(TextField)), '210 kcal');
    await tester.pump();
    await tester.tap(find.text('Log 210 kcal'));
    await tester.pumpAndSettle();

    expect(s.entries.length, before + 1);
    expect(s.entries.last.nutrients.calories, 210);
    expect(find.textContaining('Logged Granola'), findsOneWidget);
  }, variant: desktop);

  testWidgets('wide window uses the side rail and two-column Today', (tester) async {
    final s = await _state(sample: true);
    await _pump(tester, s, const Size(1400, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('FitTrack'), findsOneWidget);
  }, variant: desktop);

  testWidgets('Food log shows the hourly timeline and finds past foods by search', (tester) async {
    final s = await _state(sample: true);
    await _pump(tester, s, const Size(420, 900));
    await tester.tap(find.text('Food log').last);
    await tester.pumpAndSettle();

    expect(find.text('Search for a food'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Add food at')), findsWidgets);

    await tester.enterText(find.byType(TextField).last, 'yog');
    await tester.pump(); // local results appear without waiting for the network
    expect(find.text('Greek Yogurt'), findsWidgets);
  }, variant: desktop);
}
