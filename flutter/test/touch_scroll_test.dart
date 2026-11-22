import 'package:fittrack/app.dart';
import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A finger dragging up must scroll every long screen on a phone.
void main() {
  final phone = TargetPlatformVariant.only(TargetPlatform.android);

  Future<AppState> pump(WidgetTester tester, {bool sample = false}) async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    await s.load(seedSampleIfEmpty: sample);
    tester.view.physicalSize = const Size(400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FitTrackApp(state: s));
    await tester.pumpAndSettle();
    return s;
  }

  double offsetOf(WidgetTester tester) {
    final positions = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((s) => s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0)
        .map((s) => s.position.pixels);
    return positions.fold(0, (a, b) => a + b);
  }

  Future<void> dragUp(WidgetTester tester, Offset from) async {
    await tester.dragFrom(from, const Offset(0, -300), touchSlopY: 20);
    await tester.pumpAndSettle();
  }

  testWidgets('onboarding plan step scrolls from a finger on the rows', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    while (find.text('Your plan').evaluate().isEmpty) {
      // Each step must scroll under a finger too, before moving on.
      final before = offsetOf(tester);
      final scrollable = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .any((s) => s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0);
      if (scrollable) {
        await dragUp(tester, const Offset(200, 400));
        expect(offsetOf(tester), greaterThan(before), reason: 'onboarding step did not scroll');
      }
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    final before = offsetOf(tester);
    await dragUp(tester, const Offset(200, 500));
    expect(offsetOf(tester), greaterThan(before), reason: 'plan did not scroll');
  }, variant: phone);

  testWidgets('a slow drag that starts on a tappable row still scrolls', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    while (find.text('Your plan').evaluate().isEmpty) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    // Rest on the row long enough for its press animation, then move like a finger does.
    final row = tester.getCenter(find.textContaining('little or no exercise', findRichText: true).hitTestable().first);
    final before = offsetOf(tester);
    final g = await tester.startGesture(row);
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(offsetOf(tester), greaterThan(before), reason: 'slow drag on a row did not scroll');
  }, variant: phone);

  testWidgets('Today, Progress and Settings scroll from a finger', (tester) async {
    await pump(tester, sample: true);
    for (final tab in ['Today', 'Progress', 'Settings']) {
      if (tab != 'Today') {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
      }
      final before = offsetOf(tester);
      await dragUp(tester, const Offset(200, 450));
      expect(offsetOf(tester), greaterThan(before), reason: '$tab did not scroll');
    }
  }, variant: phone);
}
