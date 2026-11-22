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

  test('the pace is re-planned weekly from the trend weight, not on every weigh-in', () async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    final p = UserProfile(
      sex: BiologicalSex.male,
      weightKg: 80,
      heightCm: 180,
      goal: WeightGoal.lose,
      targetWeightKg: 75,
      targetDate: DateTime.now().add(const Duration(days: 70)),
    );
    s.completeOnboarding(p);
    s.updateProfileAndPlan((_) {}); // plans from 80 kg today
    final planned = s.profile!.targets.calories;

    // A water-weight drop the next day changes nothing.
    await s.addWeight(78, DateTime.now().add(const Duration(minutes: 1)));
    expect(s.profile!.targets.calories, planned);
    expect(s.profile!.planWeightKg, 80);

    // A week on, the next weigh-in re-plans from the trend: it has only moved part of the way
    // to the 78 kg readings, so one low day counts for little.
    s.profile!.planUpdatedAt = DateTime.now().subtract(const Duration(days: 8));
    await s.addWeight(78, DateTime.now().add(const Duration(minutes: 2)));
    expect(s.profile!.planWeightKg, greaterThan(78));
    expect(s.profile!.planWeightKg, lessThan(80));
    expect(s.profile!.planUpdatedAt!.isAfter(DateTime.now().subtract(const Duration(minutes: 1))), isTrue);

    // Targets typed in by hand are never re-planned.
    s.updateProfile(
      (p) => p
        ..targets = const Nutrients(calories: 2500, protein: 150, carbs: 280, fat: 80)
        ..customTargets = true
        ..planUpdatedAt = DateTime.now().subtract(const Duration(days: 8)),
    );
    await s.addWeight(77.5, DateTime.now().add(const Duration(minutes: 3)));
    expect(s.profile!.targets.calories, 2500);
  });

  test('plan state is saved', () {
    final p = UserProfile(planWeightKg: 79.4, planUpdatedAt: DateTime(2026, 11, 22), customTargets: true);
    final back = UserProfile.fromJson(p.toJson());
    expect(back.planWeightKg, 79.4);
    expect(back.planUpdatedAt, DateTime(2026, 11, 22));
    expect(back.customTargets, isTrue);
  });

  test('a weight typed into Profile is planned from, not the older weigh-ins', () {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    s.completeOnboarding(UserProfile(sex: BiologicalSex.male, weightKg: 70, heightCm: 184));
    s.updateProfileAndPlan(
      (p) => p
        ..weightKg = 83
        ..weightTypedAt = DateTime.now().add(const Duration(seconds: 1))
        ..goal = WeightGoal.lose
        ..targetWeightKg = 78
        ..targetDate = DateTime.now().add(const Duration(days: 98)),
    );
    expect(s.profile!.planWeightKg, 83);
    expect(s.profile!.targetReached, isFalse);
    expect(s.profile!.pace!.kgToGo, closeTo(-5, 1e-9));
  });

  test('profile weight follows the trend weight after each weigh-in', () async {
    final s = AppState(store: MemoryStore(), health: UnsupportedHealthService());
    s.completeOnboarding(UserProfile(sex: BiologicalSex.male, weightKg: 80, heightCm: 180));
    await s.addWeight(78, DateTime.now().add(const Duration(days: 1)));
    expect(s.profile!.weightKg, greaterThan(79.5)); // one light day barely moves it
    expect(s.profile!.weightKg, lessThan(80));
  });
}
