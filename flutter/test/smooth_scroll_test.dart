import 'package:fittrack/design/smooth_scroll.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ScrollController> _list(WidgetTester tester) async {
  final c = SmoothScrollController();
  await tester.pumpWidget(
    MaterialApp(
      home: ListView(controller: c, children: [for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('$i'))]),
    ),
  );
  return c;
}

Future<void> _wheel(WidgetTester tester, double dy) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(tester.getCenter(find.byType(ListView)));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
}

void main() {
  testWidgets('a mouse-wheel notch glides to its target instead of jumping', (tester) async {
    final c = await _list(tester);
    await _wheel(tester, 100);
    await tester.pump(); // the glide starts on the next frame
    await tester.pump(const Duration(milliseconds: 40));
    expect(c.offset, inExclusiveRange(1, 99)); // part-way there: a glide, not a jump
    await tester.pumpAndSettle();
    expect(c.offset, 100);
  });

  testWidgets('notches during a glide add up', (tester) async {
    final c = await _list(tester);
    await _wheel(tester, 100);
    await tester.pump(const Duration(milliseconds: 40));
    await _wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(c.offset, 200);
  });

  testWidgets('small trackpad deltas follow the finger directly', (tester) async {
    final c = await _list(tester);
    await _wheel(tester, 12);
    await tester.pump();
    expect(c.offset, 12);
  });
}
