import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/util.dart';
import '../../widgets/common.dart';

/// Everything the TDEE calculator needs, plus the goal. Any change recalculates the daily
/// targets straight away, so the numbers on Today always follow the profile.
class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
    if (p == null) return const SizedBox.shrink();
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final metric = p.usesMetric;
    final bmr = NutritionCalculator.bmr(sex: p.sex, weightKg: p.weightKg, heightCm: p.heightCm, age: p.age);
    final tdee = NutritionCalculator.tdee(bmr, p.activity);
    final plan = p.plan;

    void update(void Function(UserProfile p) change) => state.updateProfileAndPlan(change);

    final totalInches = (p.heightCm / centimetersPerInch).round();
    final heightField = metric
        ? NumberInput(
            key: const ValueKey('cm'),
            value: p.heightCm.roundToDouble(),
            unit: 'cm',
            maxDigits: 0,
            onChanged: (v) {
              if (v != null && v >= 100 && v <= 250) update((p) => p.heightCm = v);
            },
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NumberInput(
                key: const ValueKey('ft'),
                value: (totalInches ~/ 12).toDouble(),
                unit: 'ft',
                maxDigits: 0,
                width: 76,
                onChanged: (v) {
                  if (v == null) return;
                  final inches = v.round() * 12 + totalInches % 12;
                  if (inches >= 40 && inches <= 98) update((p) => p.heightCm = inches * centimetersPerInch);
                },
              ),
              const SizedBox(width: S.sm),
              NumberInput(
                key: const ValueKey('in'),
                value: (totalInches % 12).toDouble(),
                unit: 'in',
                maxDigits: 0,
                width: 76,
                onChanged: (v) {
                  if (v == null || v < 0 || v >= 12) return;
                  final inches = (totalInches ~/ 12) * 12 + v.round();
                  if (inches >= 40 && inches <= 98) update((p) => p.heightCm = inches * centimetersPerInch);
                },
              ),
            ],
          );

    Widget figure(String label, double kcal, {bool strong = false}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall),
          CountUp(
            value: kcal,
            format: Energy.format,
            style: (strong ? tt.titleLarge : tt.titleMedium)!.copyWith(
              fontFeatures: tabular,
              color: strong ? t.calories : null,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Goal'),
        // Goal first: it's the decision people come here to change most.
        SegmentedButton<WeightGoal>(
          segments: const [
            ButtonSegment(value: WeightGoal.lose, label: Text('Cut')),
            ButtonSegment(value: WeightGoal.maintain, label: Text('Maintain')),
            ButtonSegment(value: WeightGoal.gain, label: Text('Gain')),
          ],
          selected: {p.goal},
          showSelectedIcon: false,
          onSelectionChanged: (s) => update((p) => p.goal = s.first),
        ),
        if (p.goal != WeightGoal.maintain) ...[const SizedBox(height: S.md), _TargetGroup(profile: p, update: update)],
        Padding(
          padding: const EdgeInsets.fromLTRB(6, S.sm, 6, S.md),
          child: BlurSwitcher(
            child: Align(
              key: ValueKey('${p.goal}${p.targetWeightKg}${p.targetDate}${p.weightKg}'),
              alignment: Alignment.centerLeft,
              child: Text(goalLine(p, plan.targets.calories, tdee), style: tt.bodySmall),
            ),
          ),
        ),
        FGroup(
          children: [
            FRow(
              label: 'Sex',
              trailing: SegmentedButton<BiologicalSex>(
                segments: const [
                  ButtonSegment(value: BiologicalSex.male, label: Text('Male')),
                  ButtonSegment(value: BiologicalSex.female, label: Text('Female')),
                ],
                selected: {p.sex},
                showSelectedIcon: false,
                onSelectionChanged: (s) => update((p) => p.sex = s.first),
              ),
            ),
            FRow(
              label: 'Age',
              trailing: NumberInput(
                value: p.age.toDouble(),
                unit: 'years',
                maxDigits: 0,
                width: 120,
                onChanged: (v) {
                  if (v == null || v < 13 || v > 110) return;
                  final now = DateTime.now();
                  update((p) => p.birthDate = DateTime(now.year - v.round(), now.month, now.day));
                },
              ),
            ),
            FRow(label: 'Height', trailing: heightField),
            FRow(
              label: 'Weight',
              trailing: NumberInput(
                key: ValueKey('w$metric'),
                value: ((metric ? p.weightKg : p.weightKg * poundsPerKilogram) * 10).round() / 10,
                unit: metric ? 'kg' : 'lb',
                onChanged: (v) {
                  if (v == null) return;
                  final kg = metric ? v : v / poundsPerKilogram;
                  if (kg >= 30 && kg <= 350) update((p) => p.weightKg = kg);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.md),
              child: DropdownButtonFormField<ActivityLevel>(
                initialValue: p.activity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Activity level'),
                borderRadius: BorderRadius.circular(S.radiusControl),
                dropdownColor: t.raised,
                selectedItemBuilder: (_) => [
                  for (final a in ActivityLevel.values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${a.title} (${a.detail.toLowerCase()})', overflow: TextOverflow.ellipsis),
                    ),
                ],
                items: [
                  for (final a in ActivityLevel.values)
                    DropdownMenuItem(
                      value: a,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${a.title} (${a.detail.toLowerCase()})', overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: S.md),
                          Text(
                            whole(Energy.toDisplay(NutritionCalculator.tdee(bmr, a))),
                            style: tt.labelMedium!.copyWith(fontFeatures: tabular),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (a) {
                  if (a != null) update((p) => p.activity = a);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.md),
              child: DropdownButtonFormField<DietStyle>(
                initialValue: p.diet,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Macro split'),
                borderRadius: BorderRadius.circular(S.radiusControl),
                dropdownColor: t.raised,
                selectedItemBuilder: (_) => [
                  for (final d in DietStyle.values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(d.title, overflow: TextOverflow.ellipsis),
                    ),
                ],
                items: [
                  for (final d in DietStyle.values)
                    DropdownMenuItem(
                      value: d,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(d.title, overflow: TextOverflow.ellipsis),
                          Text(
                            d.detail,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall!.copyWith(color: t.muted, fontFeatures: tabular),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (d) {
                  if (d != null) update((p) => p.diet = d);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: S.md),
        FCard(
          padding: const EdgeInsets.all(S.lg),
          child: Row(
            children: [
              figure('BMR', bmr.floorToDouble()),
              figure('TDEE', tdee),
              figure('Daily target', plan.targets.calories, strong: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, S.sm, 6, 0),
          child: Row(
            children: [
              FIcon(Symbols.info, size: 14, color: t.muted, weight: FontWeight.w500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Mifflin–St Jeor. Changing anything here updates your daily targets below.',
                  style: tt.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the goal does to the daily target, in one or two sentences.
String goalLine(UserProfile p, double calories, double tdee) {
  final metric = p.usesMetric;
  String kg(double v) => metric ? '${oneDecimal(v)} kg' : '${oneDecimal(v * poundsPerKilogram)} lb';
  String kcal(double v) => '${v >= 0 ? '+' : '−'}\u00A0${Energy.format(v.abs())}'; // never split from its sign
  final floor = calories <= NutritionCalculator.minimumCalories(p.sex) + 5 && p.goal == WeightGoal.lose
      ? ' Held at the ${Energy.format(NutritionCalculator.minimumCalories(p.sex))} minimum, so it may take longer.'
      : '';
  if (p.goal == WeightGoal.maintain) return 'Maintain: eat your TDEE.';
  if (p.targetReached) {
    return 'You’ve reached ${kg(p.targetWeightKg!)}. Eating your TDEE to hold it; switch to Maintain, or set a new target.';
  }
  final pace = p.pace;
  if (pace == null) {
    return p.goal == WeightGoal.lose
        ? 'Cut: TDEE − 500 kcal, about 0.5 kg (1 lb) a week. Add a target weight and date to set the pace.'
        : 'Gain: TDEE + 300 kcal, a lean surplus. Add a target weight and date to set the pace.';
  }
  final verb = pace.kgToGo < 0 ? 'Lose' : 'Gain';
  final weeks = pace.weeks.round();
  final perWeek = kg(pace.kgPerWeek.abs());
  final adj = kcal(calories - tdee);
  if (pace.limited) {
    return '$verb ${kg(pace.kgToGo.abs())} in $weeks week${weeks == 1 ? '' : 's'} is faster than the safe '
        '${kg(pace.safeKgPerWeek)} a week. Planned at that pace instead: TDEE $adj, reaching it around '
        '${DateFormat('d MMM').format(pace.reachBy)}.$floor';
  }
  return '$verb ${kg(pace.kgToGo.abs())} in $weeks week${weeks == 1 ? '' : 's'}: about $perWeek a week, '
      'so TDEE $adj.$floor Updates each time you weigh in.';
}

/// Target weight and the date to reach it, for a cut or gain.
class _TargetGroup extends StatelessWidget {
  const _TargetGroup({required this.profile, required this.update});
  final UserProfile profile;
  final void Function(void Function(UserProfile p) change) update;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final p = profile;
    final metric = p.usesMetric;
    final target = p.targetWeightKg;
    final date = p.targetDate;
    final today = DateTime.now();
    final weeks = date == null ? null : (date.difference(DateTime(today.year, today.month, today.day)).inHours / 168);

    Future<void> pickDate() async {
      final first = DateTime(today.year, today.month, today.day + 7);
      final picked = await showDatePicker(
        context: context,
        initialDate: date != null && date.isAfter(first) ? date : DateTime(today.year, today.month + 3, today.day),
        firstDate: first,
        lastDate: DateTime(today.year + 3, today.month, today.day),
        helpText: 'Reach it by',
      );
      if (picked != null) update((p) => p.targetDate = picked);
    }

    return FGroup(
      children: [
        FRow(
          label: 'Target weight',
          sub: p.goal == WeightGoal.lose ? 'Where the cut ends' : 'Where the gain ends',
          trailing: NumberInput(
            key: ValueKey('tw$metric'),
            value: target == null ? null : ((metric ? target : target * poundsPerKilogram) * 10).round() / 10,
            unit: metric ? 'kg' : 'lb',
            hint: metric
                ? oneDecimal(p.weightKg + (p.goal == WeightGoal.lose ? -5 : 3))
                : oneDecimal((p.weightKg + (p.goal == WeightGoal.lose ? -5 : 3)) * poundsPerKilogram),
            onChanged: (v) {
              if (v == null) return update((p) => p.targetWeightKg = null);
              final kg = metric ? v : v / poundsPerKilogram;
              if (kg >= 30 && kg <= 350) update((p) => p.targetWeightKg = kg);
            },
          ),
        ),
        FRow(
          label: 'Reach it by',
          sub: weeks == null ? 'Pick a date' : '${weeks.round()} weeks from today',
          onTap: pickDate,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                date == null ? 'Set date' : DateFormat('d MMM yyyy').format(date),
                style: tt.bodyLarge!.copyWith(color: date == null ? t.muted : null, fontFeatures: tabular),
              ),
              const SizedBox(width: S.xs),
              FIcon(Symbols.calendar_month, size: 20, color: t.muted),
            ],
          ),
        ),
      ],
    );
  }
}
