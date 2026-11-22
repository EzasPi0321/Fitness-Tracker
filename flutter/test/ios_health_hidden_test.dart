import 'package:fittrack/app.dart';
import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:fittrack/services/platform_caps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPhone builds are signed with a free Apple ID, which can't use Apple Health, so nothing
/// about Health is offered there. Android keeps it.
void main() {
  Future<AppState> pump(WidgetTester tester, {bool sample = false}) async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    await s.load(seedSampleIfEmpty: sample);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FitTrackApp(state: s));
    await tester.pumpAndSettle();
    return s;
  }

  testWidgets('iPhone: setup skips the Health step', (tester) async {
    expect(PlatformCaps.hideHealth, isTrue);
    await pump(tester);
    await tester.ensureVisible(find.text('Set up my plan'));
    await tester.tap(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    expect(find.text('About you'), findsOneWidget);
    expect(find.textContaining('Connect Apple Health'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android: setup still offers Health Connect', (tester) async {
    expect(PlatformCaps.hideHealth, isFalse);
    await pump(tester);
    await tester.ensureVisible(find.text('Set up my plan'));
    await tester.tap(find.text('Set up my plan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connect'), findsWidgets);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('iPhone: Settings has no Health section and no steps target', (tester) async {
    await pump(tester, sample: true);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Health sync'), findsNothing);
    expect(find.text('Apple Health'), findsNothing);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sleep').last, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Steps'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
