import 'package:fittrack/screens/progress/progress_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('under the goal or close to it is on target; more than 10% over, or under half, is not', () {
    expect(onCalorieTarget(1500, 2050), isTrue); // under
    expect(onCalorieTarget(900, 2050), isFalse); // under half: probably not fully logged
    expect(onCalorieTarget(2050, 2050), isTrue);
    expect(onCalorieTarget(2250, 2050), isTrue); // 9.8% over
    expect(onCalorieTarget(2300, 2050), isFalse); // 12% over
  });
}
