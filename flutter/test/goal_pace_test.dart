import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/data/storage.dart';
import 'package:fittrack/models/nutrients.dart';
import 'package:fittrack/models/profile.dart';
import 'package:fittrack/services/health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 22);

  test('5 kg in 10 weeks is half a kilo a week: about 550 kcal under maintenance', () {
    final pace = GoalPace.of(
      goal: WeightGoal.lose,
      weightKg: 80,
      targetKg: 75,
      targetDate: DateTime(2027, 1, 31),
      now: now,
    )!;
    expect(pace.weeks, 10);
    expect(pace.kgPerWeek, closeTo(-0.5, 1e-9));
    expect(pace.dailyKcal, closeTo(-550, 1e-6));
    expect(pace.limited, isFalse);
  });

  test('a crash cut is held to 1% of body weight a week, and the date moves out', () {
    final pace = GoalPace.of(
      goal: WeightGoal.lose,
      weightKg: 80,
      targetKg: 70,
      targetDate: DateTime(2026, 12, 20),
      now: now,
    )!;
    expect(pace.limited, isTrue);
    expect(pace.kgPerWeek, closeTo(-0.8, 1e-9));
    expect(pace.reachBy.isAfter(DateTime(2027, 2, 1)), isTrue); // 12.5 weeks
  });

  test('a gain is held to 0.5% a week', () {
    final pace = GoalPace.of(
      goal: WeightGoal.gain,
      weightKg: 70,
      targetKg: 75,
      targetDate: DateTime(2026, 12, 6),
      now: now,
    )!;
    expect(pace.kgPerWeek, closeTo(0.35, 1e-9));
    expect(pace.dailyKcal, closeTo(385, 1e-6));
  });

  test('no pace without both values, on maintain, or with the target on the wrong side', () {
    expect(GoalPace.of(goal: WeightGoal.lose, weightKg: 80, targetKg: 75, now: now), isNull);
    expect(
      GoalPace.of(goal: WeightGoal.maintain, weightKg: 80, targetKg: 75, targetDate: DateTime(2027), now: now),
      isNull,
    );
    expect(
      GoalPace.of(goal: WeightGoal.lose, weightKg: 80, targetKg: 85, targetDate: DateTime(2027), now: now),
      isNull,
    );
  });

  test('the plan uses the pace; reaching the target holds weight at maintenance', () {
    final p = UserProfile(
      sex: BiologicalSex.male,
      weightKg: 80,
      heightCm: 180,
      goal: WeightGoal.lose,
      targetWeightKg: 75,
      targetDate: DateTime.now().add(const Duration(days: 70)),
    );
    final tdee = p.plan.tdee;
    expect(p.plan.targets.calories, closeTo(tdee - 550, 10));
    p.weightKg = 75;
    expect(p.targetReached, isTrue);
    expect(p.plan.targets.calories, closeTo(p.plan.tdee, 10)); // maintenance at the new weight
  });

  test('target and date are saved', () {
    final p = UserProfile(targetWeightKg: 65.5, targetDate: DateTime(2027, 3, 1));
    final back = UserProfile.fromJson(p.toJson());
    expect(back.targetWeightKg, 65.5);
    expect(back.targetDate, DateTime(2027, 3, 1));
  });

  test('a weigh-in re-plans the pace, unless targets were set by hand', () async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    final p = UserProfile(
      sex: BiologicalSex.male,
      weightKg: 80,
      heightCm: 180,
      goal: WeightGoal.lose,
      targetWeightKg: 75,
      targetDate: DateTime.now().add(const Duration(days: 70)),
    );
    p.targets = p.plan.targets;
    s.completeOnboarding(p);
    final before = s.profile!.targets.calories;
    await s.addWeight(79, DateTime.now());
    expect(s.profile!.targets.calories, isNot(before)); // 4 kg to go now, and a lower TDEE

    s.updateProfile((p) => p.targets = const Nutrients(calories: 2500, protein: 150, carbs: 280, fat: 80));
    await s.addWeight(78.5, DateTime.now().add(const Duration(minutes: 1)));
    expect(s.profile!.targets.calories, 2500);
  });
}
