import 'package:fittrack/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page(FocusNode focus) => MaterialApp(
    builder: (context, child) => KeyboardDismisser(child: child!),
    home: Scaffold(
      body: ListView(
        children: [
          TextField(focusNode: focus, keyboardType: TextInputType.number),
          const SizedBox(height: 2000),
        ],
      ),
    ),
  );

  testWidgets('tapping outside a field puts the keyboard away', (tester) async {
    final focus = FocusNode();
    await tester.pumpWidget(page(focus));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('tapping the field itself keeps it open', (tester) async {
    final focus = FocusNode();
    await tester.pumpWidget(page(focus));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('starting to scroll puts the keyboard away', (tester) async {
    final focus = FocusNode();
    await tester.pumpWidget(page(focus));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });
}
