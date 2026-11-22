import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/models/util.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppState> fresh() async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    await s.load();
    return s;
  }

  final today = startOfDay(DateTime.now());

  test('fittrack://steps saves today, and Shortcuts number formats are understood', () async {
    final s = await fresh();
    expect(s.handleLink(Uri.parse('fittrack://steps?count=8432')), isTrue);
    expect(s.loggedSteps[today], 8432);
    expect(s.stepsFromShortcutAt, isNotNull);
    expect(s.handleLink(Uri.parse('fittrack://steps?count=9%2C120.0')), isTrue); // "9,120.0"
    expect(s.loggedSteps[today], 9120);
  });

  test('an earlier, lower count from the shortcut never lowers today', () async {
    final s = await fresh();
    s.handleLink(Uri.parse('fittrack://steps?count=9000'));
    s.handleLink(Uri.parse('fittrack://steps?count=4000'));
    expect(s.loggedSteps[today], 9000);
    s.setLoggedSteps(today, 4000); // typing it in can still correct it
    expect(s.loggedSteps[today], 4000);
  });

  test('a date can be given, and anything else is ignored', () async {
    final s = await fresh();
    expect(s.handleLink(Uri.parse('fittrack://steps?count=7000&date=2026-11-20')), isTrue);
    expect(s.loggedSteps[DateTime(2026, 11, 20)], 7000);
    expect(s.handleLink(Uri.parse('fittrack://steps')), isFalse);
    expect(s.handleLink(Uri.parse('fittrack://steps?count=-5')), isFalse);
    expect(s.handleLink(Uri.parse('fittrack://water?ml=500')), isFalse);
    expect(s.handleLink(Uri.parse('https://example.com/steps?count=5')), isFalse);
  });

  test('logged steps survive a save and reload', () async {
    final store = MemoryStore();
    final a = AppState(store: store, health: UnsupportedHealthService());
    await a.load();
    a.handleLink(Uri.parse('fittrack://steps?count=6543'));
    await a.flush();
    final b = AppState(store: store, health: UnsupportedHealthService());
    await b.load();
    expect(b.loggedSteps[today], 6543);
    expect(b.stepsFromShortcutAt, isNotNull);
  });
}
