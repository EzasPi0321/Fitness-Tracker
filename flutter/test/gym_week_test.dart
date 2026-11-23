import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/design/tokens.dart';
import 'package:fittrack/models/gym.dart';
import 'package:fittrack/models/util.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:fittrack/widgets/gym_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppState> pump(WidgetTester tester, DateTime day, void Function(AppState) setup) async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    setup(s);
    await tester.pumpWidget(
      AppScope(
        state: s,
        child: MaterialApp(
          theme: buildTheme(FT.darkTheme()),
          home: Scaffold(
            body: SingleChildScrollView(child: GymCard(day: day)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Let the state's delayed save run, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 1));
    return s;
  }

  testWidgets('today: trained today, and the week counts days', (tester) async {
    final today = startOfDay(DateTime.now());
    await pump(tester, today, (s) => s.logGym(TrainingType.legs, DateTime.now()));
    expect(find.text('Trained today'), findsOneWidget);
    expect(find.text('1 day this week'), findsOneWidget);
    expect(find.text('M'), findsOneWidget); // Monday-to-Sunday row
  });

  testWidgets('a past day with training says Trained, not Trained today', (tester) async {
    final past = addDays(startOfDay(DateTime.now()), -10);
    await pump(tester, past, (s) => s.logGym(TrainingType.push, past.add(const Duration(hours: 18))));
    expect(find.text('Trained'), findsOneWidget);
    expect(find.text('Trained today'), findsNothing);
  });

  testWidgets('two sessions on one day count as one day', (tester) async {
    final today = startOfDay(DateTime.now());
    await pump(tester, today, (s) {
      s.logGym(TrainingType.cardio, DateTime.now());
      s.logGym(TrainingType.push, DateTime.now());
    });
    expect(find.text('2 sessions today'), findsOneWidget);
    expect(find.text('1 day this week'), findsOneWidget);
  });
}
