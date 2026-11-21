import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../models/nutrients.dart';
import '../../models/profile.dart';
import '../../models/util.dart';
import '../../services/platform_caps.dart';
import '../../widgets/common.dart';

enum _Step { welcome, health, body, activity, goal, plan }

/// First run, or "Recalculate from my profile". One decision per screen (Hick's law), and the
/// plan screen shows the numbers in three chunks: resting burn, maintenance, target.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.existing});
  final UserProfile? existing;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final UserProfile _draft = widget.existing?.copy() ?? UserProfile();
  late _Step _step = widget.existing == null ? _Step.welcome : _Step.body;
  bool _forward = true;
  int? _age;

  @override
  void initState() {
    super.initState();
    _age = _draft.age;
  }

  List<_Step> get _steps => [
    if (widget.existing == null) _Step.welcome,
    if (widget.existing == null && PlatformCaps.hasHealthStore) _Step.health,
    _Step.body,
    _Step.activity,
    _Step.goal,
    _Step.plan,
  ];

  int get _index => _steps.indexOf(_step);

  bool get _canContinue => _step != _Step.body || _draft.isBodyValid;

  void _go(int delta) {
    final i = (_index + delta).clamp(0, _steps.length - 1);
    setState(() {
      _forward = delta > 0;
      _step = _steps[i];
    });
  }

  void _finish() {
    final state = AppScope.read(context);
    _draft.targets = _draft.plan.targets;
    if (widget.existing != null) {
      state.updateProfile((p) {
        p
          ..sex = _draft.sex
          ..birthDate = _draft.birthDate
          ..heightCm = _draft.heightCm
          ..weightKg = _draft.weightKg
          ..activity = _draft.activity
          ..goal = _draft.goal
          ..usesMetric = _draft.usesMetric
          ..targets = _draft.targets;
      });
      Navigator.pop(context);
      showToast(context, 'New targets saved');
    } else {
      state.completeOnboarding(_draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final showChrome = _step != _Step.welcome;
    final last = _step == _Step.plan;

    return Scaffold(
      appBar: widget.existing != null ? AppBar(title: const Text('Recalculate targets')) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                if (showChrome)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, 0),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _index / (_steps.length - 1)),
                      duration: Motion.of(context, Motion.slow),
                      curve: Motion.standard,
                      builder: (context, v, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: t.inset),
                      ),
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.slow),
                    switchInCurve: Motion.enter,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) {
                      final incoming = child.key == ValueKey(_step);
                      final dir = (_forward == incoming) ? 1.0 : -1.0;
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: Offset(0.06 * dir, 0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(key: ValueKey(_step), child: _page(context)),
                  ),
                ),
                if (showChrome)
                  Padding(
                    padding: const EdgeInsets.all(S.lg),
                    child: Row(
                      children: [
                        if (_index > 0 && _steps[_index - 1] != _Step.welcome)
                          TextButton(onPressed: () => _go(-1), child: const Text('Back')),
                        const Spacer(),
                        Squishy(
                          onTap: _canContinue ? (last ? _finish : () => _go(1)) : null,
                          feel: last ? PressFeel.bold : PressFeel.normal,
                          haptic: last,
                          child: IgnorePointer(
                            child: FilledButton(
                              onPressed: _canContinue ? () {} : null,
                              child: Text(
                                last ? (widget.existing == null ? 'Start tracking' : 'Save targets') : 'Continue',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context) => switch (_step) {
    _Step.welcome => _welcome(context),
    _Step.health => _health(context),
    _Step.body => _body(context),
    _Step.activity => _choices<ActivityLevel>(
      'How active are you?',
      ActivityLevel.values,
      _draft.activity,
      (a) => a.title,
      (a) => a.detail,
      (a) => setState(() => _draft.activity = a),
      // TDEE for each level, from the body stats on the previous step.
      trailing: (a) => Energy.format(NutritionCalculator.tdee(_bmr, a)),
    ),
    _Step.goal => _choices<WeightGoal>(
      'What\'s your goal?',
      WeightGoal.values,
      _draft.goal,
      (g) => g.title,
      (g) => g.detail,
      (g) => setState(() => _draft.goal = g),
    ),
    _Step.plan => _plan(context),
  };

  Widget _welcome(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(S.xl),
      children: [
        const SizedBox(height: S.xxl),
        Rise(
          child: Container(
            width: 88,
            height: 88,
            alignment: Alignment.centerLeft,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), color: t.accent),
              child: Center(
                child: FIcon(Symbols.donut_large, size: 48, color: t.onAccent, weight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(height: S.xl),
        Rise(
          delay: const Duration(milliseconds: 60),
          child: Text('Eat to your plan,\nnot to a guess.', style: tt.displaySmall),
        ),
        const SizedBox(height: S.lg),
        Rise(
          delay: const Duration(milliseconds: 100),
          child: Text(
            'FitTrack works out your daily calories and macros, then makes logging fast: scan a barcode, snap your plate, or type it in.',
            style: tt.bodyLarge!.copyWith(color: t.muted),
          ),
        ),
        const SizedBox(height: S.xxl),
        Rise(
          delay: const Duration(milliseconds: 140),
          child: Squishy(
            onTap: () => _go(1),
            feel: PressFeel.bold,
            child: IgnorePointer(
              child: FilledButton(onPressed: () {}, child: const Text('Set up my plan')),
            ),
          ),
        ),
        const SizedBox(height: S.sm),
        Rise(
          delay: const Duration(milliseconds: 160),
          child: OutlinedButton(
            onPressed: () => AppScope.read(context).loadSampleData(),
            child: const Text('Look around with sample data'),
          ),
        ),
      ],
    );
  }

  Widget _health(BuildContext context) {
    final state = AppScope.of(context);
    final tt = Theme.of(context).textTheme;
    final t = FT.of(context);
    final name = state.health.storeName;
    return ListView(
      padding: const EdgeInsets.all(S.xl),
      children: [
        FIcon(Symbols.favorite, size: 44, color: t.over, fill: true),
        const SizedBox(height: S.lg),
        Text('Connect $name?', style: tt.headlineMedium),
        const SizedBox(height: S.md),
        Text(
          'FitTrack can fill in your height and weight, add exercise to your budget, and save meals to $name.',
          style: tt.bodyLarge!.copyWith(color: t.muted),
        ),
        const SizedBox(height: S.xl),
        FilledButton.tonal(
          onPressed: () async {
            await state.setHealthEnabled(true);
            if (!state.healthEnabled) return;
            final snap = await state.health.snapshot();
            setState(() {
              if (snap.heightCm != null && snap.heightCm! >= 100 && snap.heightCm! <= 250)
                _draft.heightCm = snap.heightCm!;
              if (snap.weightKg != null && snap.weightKg! >= 30 && snap.weightKg! <= 350)
                _draft.weightKg = snap.weightKg!;
            });
            _go(1);
          },
          child: Text('Connect $name'),
        ),
        if (state.healthError != null) ...[
          const SizedBox(height: S.md),
          StatusPill(text: state.healthError!, color: t.warn, icon: Symbols.info),
        ],
        const SizedBox(height: S.sm),
        Text('You can change this later in Settings. Tap Continue to skip.', style: tt.bodySmall),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final m = _draft.usesMetric;
    final heightDisplay = m ? _draft.heightCm : _draft.heightCm / centimetersPerInch;
    final weightDisplay = m ? _draft.weightKg : _draft.weightKg * poundsPerKilogram;
    return ListView(
      padding: const EdgeInsets.all(S.xl),
      children: [
        Text('About you', style: tt.headlineMedium),
        const SizedBox(height: S.sm),
        Text(
          'Used only to estimate how much energy you burn.',
          style: tt.bodyMedium!.copyWith(color: FT.of(context).muted),
        ),
        const SizedBox(height: S.xl),
        SegmentedButton<BiologicalSex>(
          segments: [for (final s in BiologicalSex.values) ButtonSegment(value: s, label: Text(s.title))],
          selected: {_draft.sex},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _draft.sex = s.first),
        ),
        const SizedBox(height: S.md),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Metric')),
            ButtonSegment(value: false, label: Text('Imperial')),
          ],
          selected: {m},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _draft.usesMetric = s.first),
        ),
        const SizedBox(height: S.lg),
        FGroup(
          footer: _draft.isBodyValid
              ? null
              : const Text('Check the values: age 13–110, height 100–250 cm, weight 30–350 kg.'),
          children: [
            FRow(
              label: 'Age',
              trailing: NumberInput(
                value: _age?.toDouble(),
                unit: 'yr',
                maxDigits: 0,
                onChanged: (v) => setState(() {
                  _age = v?.round();
                  if (_age != null) {
                    final now = DateTime.now();
                    _draft.birthDate = DateTime(now.year - _age!, now.month, now.day);
                  }
                }),
              ),
            ),
            FRow(
              label: 'Height',
              trailing: NumberInput(
                key: ValueKey('h$m'),
                value: (heightDisplay * (m ? 1 : 10)).round() / (m ? 1 : 10),
                unit: m ? 'cm' : 'in',
                maxDigits: m ? 0 : 1,
                onChanged: (v) => setState(() {
                  if (v != null) _draft.heightCm = m ? v : v * centimetersPerInch;
                }),
              ),
            ),
            FRow(
              label: 'Weight',
              trailing: NumberInput(
                key: ValueKey('w$m'),
                value: (weightDisplay * 10).round() / 10,
                unit: m ? 'kg' : 'lb',
                onChanged: (v) => setState(() {
                  if (v != null) _draft.weightKg = m ? v : v / poundsPerKilogram;
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _choices<T>(
    String title,
    List<T> values,
    T selected,
    String Function(T) label,
    String Function(T) detail,
    ValueChanged<T> onPick, {
    String Function(T)? trailing,
  }) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(S.xl),
      children: [
        Text(title, style: tt.headlineMedium),
        const SizedBox(height: S.xl),
        for (final v in values) ...[
          Squishy(
            onTap: () => onPick(v),
            feel: PressFeel.subtle,
            hitSlop: 0,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              padding: const EdgeInsets.all(S.lg),
              decoration: BoxDecoration(
                color: v == selected ? t.raised : t.surface,
                borderRadius: BorderRadius.circular(S.radiusCard - 6),
                border: Border.all(color: v == selected ? t.fg : t.border, width: v == selected ? 1.6 : 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label(v), style: tt.titleMedium),
                        const SizedBox(height: 2),
                        Text(detail(v), style: tt.bodySmall),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    Text(trailing(v), style: tt.titleSmall!.copyWith(fontFeatures: tabular)),
                    const SizedBox(width: S.md),
                  ],
                  BlurSwitcher(
                    child: FIcon(
                      v == selected ? Symbols.check_circle : Symbols.circle,
                      key: ValueKey(v == selected),
                      color: v == selected ? t.fg : t.border,
                      fill: v == selected,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: S.sm),
        ],
      ],
    );
  }

  double get _bmr =>
      NutritionCalculator.bmr(sex: _draft.sex, weightKg: _draft.weightKg, heightCm: _draft.heightCm, age: _draft.age);

  /// "Your TDEE by activity level": every level, yours highlighted.
  Widget _tdeeTable(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final bmr = _bmr;
    return FCard(
      padding: const EdgeInsets.symmetric(vertical: S.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.sm),
            child: Text('TDEE by activity level', style: tt.titleMedium),
          ),
          for (final a in ActivityLevel.values)
            Squishy(
              onTap: () => setState(() => _draft.activity = a),
              feel: PressFeel.subtle,
              hitSlop: 0,
              semanticLabel: '${a.title}, ${Energy.format(NutritionCalculator.tdee(bmr, a))} a day',
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.fast),
                margin: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
                decoration: BoxDecoration(
                  color: a == _draft.activity ? t.inset : Colors.transparent,
                  borderRadius: BorderRadius.circular(S.inner(S.radiusCard, S.sm)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: a.title,
                              style: tt.bodyLarge!.copyWith(
                                fontWeight: a == _draft.activity ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                            TextSpan(text: '  ${a.detail.toLowerCase()}', style: tt.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      whole(Energy.toDisplay(NutritionCalculator.tdee(bmr, a))),
                      style: tt.titleSmall!.copyWith(
                        fontFeatures: tabular,
                        fontWeight: a == _draft.activity ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.sm),
            child: Text(
              'Mifflin–St Jeor BMR (${Energy.format(bmr.floorToDouble())}) × activity factor. Tap a row to change your level.',
              style: tt.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _plan(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final plan = _draft.plan;
    Widget figure(String label, double v, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label (${Energy.label})', style: tt.bodySmall),
          CountUp(
            value: v,
            format: (x) => whole(Energy.toDisplay(x)),
            style: tt.headlineSmall!.copyWith(fontFeatures: tabular, color: color),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(S.xl),
      children: [
        Text('Your plan', style: tt.headlineMedium),
        const SizedBox(height: S.sm),
        Text('${_draft.goal.title} · ${_draft.activity.title}', style: tt.bodyMedium!.copyWith(color: t.muted)),
        const SizedBox(height: S.xl),
        FCard(
          padding: const EdgeInsets.all(S.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  figure('Resting burn', plan.bmr),
                  figure('Maintenance', plan.tdee),
                  figure('Daily goal', plan.targets.calories, color: t.calories),
                ],
              ),
              const SizedBox(height: S.xl),
              Divider(color: t.border),
              const SizedBox(height: S.lg),
              for (final m in Macro.values) ...[
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: t.macro(m), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: S.sm),
                    Expanded(child: Text(m.title, style: tt.bodyLarge)),
                    Text('${whole(plan.targets.of(m))} g', style: tt.titleMedium!.copyWith(fontFeatures: tabular)),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${whole(plan.targets.of(m) * m.kcalPerGram / plan.targets.calories * 100)}%',
                        textAlign: TextAlign.right,
                        style: tt.bodySmall!.copyWith(fontFeatures: tabular),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: S.md),
              ],
            ],
          ),
        ),
        const SizedBox(height: S.md),
        const SizedBox(height: S.lg),
        _tdeeTable(context),
        const SizedBox(height: S.md),
        Text(
          'Your daily goal is your TDEE ${_draft.goal == WeightGoal.maintain
              ? ''
              : _draft.goal == WeightGoal.lose
              ? 'minus 500 '
              : 'plus 300 '}kcal. You can fine-tune any number later in Settings.',
          style: tt.bodySmall,
        ),
      ],
    );
  }
}
