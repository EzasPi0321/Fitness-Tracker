import 'package:fittrack/screens/progress/progress_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<int> ticks(int days) => [
    for (var i = 0; i < days; i++)
      if (isAxisTick(i, days)) i,
  ];

  test('a week labels every day', () => expect(ticks(7), [0, 1, 2, 3, 4, 5, 6]));
  test('30 and 90 days get four evenly spaced dates, first day to today', () {
    expect(ticks(30), [0, 10, 19, 29]);
    expect(ticks(90), [0, 30, 59, 89]);
  });
  test('out of range is never a tick', () {
    expect(isAxisTick(-1, 90), isFalse);
    expect(isAxisTick(90, 90), isFalse);
  });
}
