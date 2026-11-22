import 'package:fittrack/models/weight_trend.dart';
import 'package:fittrack/services/ai_vision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trend weight', () {
    final d0 = DateTime(2026, 11, 1, 7);
    DateTime day(int n) => d0.add(Duration(days: n));

    test('a one-day water spike barely moves the trend', () {
      final t = weightTrend([(day(0), 70), (day(1), 70), (day(2), 72), (day(3), 70)]);
      expect(t[2].$2, closeTo(70.2, 0.01)); // 10% of a 2 kg jump
      expect(t.last.$2, lessThan(70.2));
    });

    test('a real change shows up within a couple of weeks', () {
      final points = [for (var i = 0; i < 21; i++) (day(i), i < 7 ? 70.0 : 68.0)];
      final t = weightTrend(points);
      expect(t.last.$2, lessThan(68.6)); // most of the 2 kg drop after two weeks
    });

    test('a long gap counts as many days', () {
      final daily = weightTrend([(day(0), 70), (day(1), 68)]);
      final weekLater = weightTrend([(day(0), 70), (day(7), 68)]);
      expect(weekLater.last.$2, lessThan(daily.last.$2));
    });

    test('weekly change needs a week of trend, then reports the move', () {
      expect(weeklyTrendChange(weightTrend([(day(0), 70), (day(3), 69)])), isNull);
      final t = weightTrend([for (var i = 0; i < 15; i++) (day(i), 70.0 - i * 0.1)]);
      final w = weeklyTrendChange(t)!;
      expect(w, lessThan(0));
      expect(w, greaterThan(-0.7));
    });

    test('unsorted input is sorted first', () {
      final t = weightTrend([(day(2), 72), (day(0), 70)]);
      expect(t.first.$1, day(0));
    });
  });

  test('the correction prompt carries the edited items and what the user said', () {
    final prev = MealAnalysis(
      items: [
        DetectedFood(name: 'Caesar salad', grams: 250, calories: 420, protein: 18, carbs: 14, fat: 32, confidence: 0.8),
      ],
    );
    final p = AIVisionService.refinePrompt(prev, '  no dressing  ');
    expect(p, contains('Caesar salad: 250 g, 420 kcal'));
    expect(p, contains('"no dressing"'));
    expect(p, contains('Return every item'));
  });
}
