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

  for (final scale in [1.0, 1.3]) {
    testWidgets('the end of the plan comes fully into view at text scale $scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // A Samsung phone: 384 x 832 logical, with a status bar and gesture bar.
      tester.view.padding = const FakeViewPadding(top: 96, bottom: 72);
      addTearDown(tester.view.resetPadding);
      await pump(tester);
      await tester.scrollUntilVisible(find.text('Set up my plan'), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up my plan'));
      await tester.pumpAndSettle();
      while (find.text('Your plan').evaluate().isEmpty) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 6; i++) {
        await tester.dragFrom(const Offset(200, 400), const Offset(0, -300), touchSlopY: 20);
        await tester.pumpAndSettle();
      }
      // Let go and wait: it must stay at the bottom, not spring back.
      await tester.pump(const Duration(seconds: 2));
      final last = tester.getRect(find.textContaining('You can fine-tune any number later'));
      final button = tester.getRect(find.text('Start tracking'));
      expect(last.bottom, lessThan(button.top), reason: 'last line hidden: $last vs button $button');
    }, variant: phone);
  }

  testWidgets('background updates (Health, update checks) keep the scroll where it is', (tester) async {
    final s = await pump(tester);
    await tester.ensureVisible(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    while (find.text('Your plan').evaluate().isEmpty) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -400), touchSlopY: 20);
    await tester.pumpAndSettle();
    final scrolled = offsetOf(tester);
    expect(scrolled, greaterThan(0));
    for (var i = 0; i < 3; i++) {
      s.notifyListeners();
      await tester.pumpAndSettle();
    }
    expect(offsetOf(tester), scrolled);
  }, variant: phone);

  testWidgets('a background update in the middle of a drag or fling keeps the scroll', (tester) async {
    final s = await pump(tester);
    await tester.ensureVisible(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    while (find.text('Your plan').evaluate().isEmpty) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    final g = await tester.startGesture(const Offset(200, 500));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, -20));
      if (i % 3 == 0) s.notifyListeners();
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    for (var i = 0; i < 30; i++) {
      if (i % 3 == 0) s.notifyListeners();
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(offsetOf(tester), greaterThan(100));
  }, variant: phone);

  testWidgets('a hard fling to the bottom stays at the bottom', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    while (find.text('Your plan').evaluate().isEmpty) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    await tester.flingFrom(const Offset(200, 600), const Offset(0, -500), 4000);
    await tester.pumpAndSettle();
    final pos = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.position.maxScrollExtent > 0)
        .position;
    expect(pos.pixels, pos.maxScrollExtent);
    await tester.pump(const Duration(seconds: 3));
    expect(pos.pixels, pos.maxScrollExtent);
  }, variant: phone);
}
