import 'package:fittrack/models/profile.dart';
import 'package:fittrack/models/util.dart';
import 'package:fittrack/screens/settings/profile_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => Energy.unit = EnergyUnit.kcal);

  test('in kJ, wording and amounts follow the unit', () {
    Energy.unit = EnergyUnit.kJ;
    expect(Energy.word, 'kilojoules');
    expect(Energy.fieldName, 'Energy');
    final line = goalLine(UserProfile(goal: WeightGoal.lose), 1800, 2300);
    expect(line, contains('2,092 kJ')); // the default 500 kcal cut
    expect(line, isNot(contains('kcal')));
  });

  test('in kcal, nothing changes', () {
    expect(Energy.word, 'calories');
    expect(goalLine(UserProfile(goal: WeightGoal.gain), 2600, 2300), contains('300 kcal'));
  });
}
