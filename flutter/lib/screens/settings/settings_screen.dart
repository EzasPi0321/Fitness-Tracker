import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../models/ai_usage.dart';
import '../../models/nutrients.dart';
import '../../models/profile.dart';
import '../../models/util.dart';
import '../../services/ai_vision.dart';
import '../../services/platform_caps.dart';
import '../../services/updates.dart';
import '../../widgets/update_banner.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 840 ? S.xxl : S.lg;
    final twoCol = width >= 1000;

    final left = [const _UnitsSection(), const SizedBox(height: S.xl), const _DataSection()];
    final right = [
      if (!PlatformCaps.hideHealth) ...[const _HealthSection(), const SizedBox(height: S.xl)],
      const _AISection(),
      const SizedBox(height: S.xl),
      FGroup(
        label: 'About',
        children: [
          const FRow(label: 'Product data', sub: 'Open Food Facts, ODbL licence'),
          FRow(
            label: 'Version',
            trailing: Text(
              appBuild == 0 ? 'Development build' : '2.0.0 (build $appBuild)',
              style: tt.bodyLarge!.copyWith(color: FT.of(context).muted),
            ),
          ),
          const _UpdateRow(),
        ],
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: WithSmoothScroll(
          builder: (c) => ListView(
            controller: c,
            padding: EdgeInsets.fromLTRB(gutter, S.lg, gutter, S.xxl),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: twoCol ? 1100 : 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Settings', style: tt.headlineMedium),
                      if (state.isSample) ...[
                        const SizedBox(height: S.sm),
                        Text(
                          'Sample data is loaded. Changes here are saved but you can start fresh any time.',
                          style: tt.bodySmall,
                        ),
                      ],
                      const SizedBox(height: S.xl),
                      if (twoCol)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left),
                            ),
                            const SizedBox(width: S.xl),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
                            ),
                          ],
                        )
                      else ...[
                        ...left,
                        const SizedBox(height: S.xl),
                        ...right,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TargetsSection extends StatelessWidget {
  const TargetsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tg = state.targets;
    final macroKcal = tg.protein * 4 + tg.carbs * 4 + tg.fat * 9;
    final diff = macroKcal - tg.calories;

    // Guidelines for adjusting: the recommended range for each macro at today's calorie goal.
    final ranges = NutritionCalculator.ranges(tg.calories);
    String rangeText(Macro m) {
      final r = ranges[m]!;
      final v = tg.of(m);
      final where = v < r.low ? ' · below range' : (v > r.high ? ' · above range' : '');
      return 'Range ${whole(r.low)}–${whole(r.high)} g$where';
    }

    void set(Nutrients Function(Nutrients n, double v) f, double? v) {
      if (v == null || v < 0) return;
      state.updateProfile((p) => p.targets = f(p.targets, v.roundToDouble()));
    }

    // Every target gets a dot in the colour it's drawn with in the charts (neutral for steps
    // and sleep), so all the labels share one left edge.
    Widget dot(Color c) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    final neutral = t.fg.withValues(alpha: t.dark ? 0.86 : 0.78);

    return FGroup(
      label: 'Daily targets',
      footer: diff.abs() > 50
          ? StatusPill(
              icon: Symbols.info,
              color: t.warn,
              text:
                  'Macros add up to ${Energy.format(macroKcal)}, ${Energy.format(diff.abs())} ${diff > 0 ? 'over' : 'under'} your goal',
            )
          : Text('Macros add up to ${Energy.format(macroKcal)}.'),
      children: [
        FRow(
          leading: dot(t.calories),
          label: Energy.fieldName,
          trailing: NumberInput(
            key: ValueKey(Energy.unit),
            value: Energy.toDisplay(tg.calories).roundToDouble(),
            unit: Energy.label,
            maxDigits: 0,
            width: 130,
            onChanged: (v) => set(
              (n, v) => Nutrients(calories: Energy.fromDisplay(v), protein: n.protein, carbs: n.carbs, fat: n.fat),
              v,
            ),
          ),
        ),
        for (final m in Macro.values)
          FRow(
            leading: dot(t.macro(m)),
            label: m.title,
            sub: rangeText(m),
            trailing: NumberInput(
              value: tg.of(m),
              unit: 'g',
              maxDigits: 0,
              width: 130,
              onChanged: (v) => set(
                (n, v) => Nutrients(
                  calories: n.calories,
                  protein: m == Macro.protein ? v : n.protein,
                  carbs: m == Macro.carbs ? v : n.carbs,
                  fat: m == Macro.fat ? v : n.fat,
                ),
                v,
              ),
            ),
          ),
        FRow(
          leading: dot(t.bodyO.toColor()),
          label: 'Water',
          sub: state.waterGoalOverride == null ? 'From your weight (35 ml per kg)' : 'Your own goal',
          trailing: NumberInput(
            key: ValueKey('water${state.profile?.usesMetric}${state.waterGoalOverride == null}'),
            value: Volume.toDisplay(state.waterGoal, metric: state.profile?.usesMetric ?? true).roundToDouble(),
            unit: Volume.unit(metric: state.profile?.usesMetric ?? true),
            maxDigits: 0,
            width: 130,
            onChanged: (v) {
              if (v == null || v <= 0) return;
              state.setWaterGoal(Volume.fromDisplay(v, metric: state.profile?.usesMetric ?? true));
            },
          ),
        ),
        if (!PlatformCaps.hideHealth)
          FRow(
            leading: dot(neutral),
            label: 'Steps',
            sub: Theme.of(context).platform == TargetPlatform.android
                ? 'From Samsung Health'
                : 'From Apple Health or Samsung Health',
            trailing: NumberInput(
              value: state.stepGoal.toDouble(),
              unit: 'steps',
              maxDigits: 0,
              width: 140,
              onChanged: (v) {
                if (v != null && v >= 500) state.setStepGoal(v.round());
              },
            ),
          ),
        FRow(
          leading: dot(neutral),
          label: 'Sleep',
          sub: 'Hours asleep each night (7–9 suits most adults)',
          trailing: NumberInput(
            value: state.sleepGoalHours,
            unit: 'h',
            maxDigits: 1,
            width: 110,
            onChanged: (v) {
              if (v != null) state.setSleepGoal(v);
            },
          ),
        ),
        FRow(
          leading: const SizedBox(width: 10), // same left edge as the dotted rows above
          label: "Reset to my profile’s plan",
          sub: 'Undo manual changes to these numbers',
          trailing: FIcon(Symbols.restart_alt, color: t.muted),
          onTap: () {
            state.setWaterGoal(null);
            state.updateProfileAndPlan((_) {});
            showToast(context, 'Targets reset to your plan');
          },
        ),
      ],
    );
  }
}

class _UnitsSection extends StatelessWidget {
  const _UnitsSection();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final metric = state.profile?.usesMetric ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Appearance'),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.system, label: Text('Match device')),
          ],
          selected: {state.appearance},
          showSelectedIcon: false,
          onSelectionChanged: (s) => state.setAppearance(s.first),
        ),
        const SizedBox(height: S.xl),
        const SectionLabel('Units'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Metric (kg, cm)')),
            ButtonSegment(value: false, label: Text('Imperial (lb, in)')),
          ],
          selected: {metric},
          showSelectedIcon: false,
          onSelectionChanged: (s) => state.updateProfile((p) => p.usesMetric = s.first),
        ),
        const SizedBox(height: S.md),
        SegmentedButton<EnergyUnit>(
          segments: const [
            ButtonSegment(value: EnergyUnit.kcal, label: Text('Calories (kcal)')),
            ButtonSegment(value: EnergyUnit.kJ, label: Text('Kilojoules (kJ)')),
          ],
          selected: {state.energyUnit},
          showSelectedIcon: false,
          onSelectionChanged: (s) => state.setEnergyUnit(s.first),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, S.sm, 6, 0),
          child: Text(
            '1 kcal = 4.184 kJ. Barcodes and label photos are converted to this unit automatically.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _HealthSection extends StatelessWidget {
  const _HealthSection();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    if (!PlatformCaps.hasHealthStore) {
      return FGroup(
        label: 'Health sync',
        children: [
          FRow(
            leading: FIcon(Symbols.favorite, color: t.muted),
            label: 'Health sync',
            trailing: StatusPill(text: 'Phone only', color: FT.of(context).muted),
          ),
        ],
      );
    }
    final name = state.health.storeName;
    return FGroup(
      label: name,
      footer: state.healthError != null
          ? StatusPill(text: state.healthError!, color: t.warn, icon: Symbols.info)
          : Text(
              'Reads steps, sleep, active energy, workouts and weight; saves meals, water, weight and sleep. '
              '${Theme.of(context).platform == TargetPlatform.android ? 'Samsung phones: in Samsung Health, open Settings › Health Connect and turn on sharing for steps, sleep, exercise, weight, water and nutrition. FitTrack reads and writes it from there.' : 'Manage access in Settings › Health › Data Access & Devices.'}',
            ),
      children: [
        FRow(
          leading: FIcon(Symbols.favorite, color: t.over, fill: true),
          label: 'Sync with $name',
          trailing: Switch(value: state.healthEnabled, onChanged: state.setHealthEnabled),
        ),
        FRow(
          label: 'Add active energy to budget',
          sub: 'Exercise calories raise today’s goal',
          trailing: Switch(
            value: state.addActiveEnergy,
            onChanged: state.healthEnabled ? state.setAddActiveEnergy : null,
          ),
        ),
        if (state.healthEnabled) const _HealthStatus(),
      ],
    );
  }
}

/// What FitTrack can actually see right now: today's steps, and any data type that hasn't been
/// allowed, with the exact place to fix it.
class _HealthStatus extends StatefulWidget {
  const _HealthStatus();

  @override
  State<_HealthStatus> createState() => _HealthStatusState();
}

class _HealthStatusState extends State<_HealthStatus> {
  int? _steps;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final state = AppScope.read(context);
    setState(() => _checking = true);
    await state.refreshHealthAccess();
    final steps = await state.health.steps(DateTime.now());
    state.refreshHealth();
    if (mounted) {
      setState(() {
        _steps = steps;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final android = Theme.of(context).platform == TargetPlatform.android;
    final missing = state.healthMissing;
    final noSteps = !_checking && (_steps == null || _steps == 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.sm, S.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _checking ? 'Checking…' : 'Steps today: ${_steps == null ? '—' : whole(_steps!.toDouble())}',
                  style: tt.bodyLarge,
                ),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  StatusPill(text: 'Not allowed: ${missing.join(', ')}', color: t.warn, icon: Symbols.info),
                  const SizedBox(height: 4),
                  Text(
                    android
                        ? 'Allow them in Settings › Apps › Health Connect › App permissions › FitTrack.'
                        : 'Allow them in Settings › Health › Data Access & Devices › FitTrack.',
                    style: tt.bodySmall,
                  ),
                ],
                if (noSteps && android) ...[
                  const SizedBox(height: 4),
                  Text(
                    'No steps yet. In Samsung Health: Settings › Health Connect › App permissions › '
                    'Samsung Health, and turn on Steps (and Exercise, Weight). Samsung Health copies '
                    'new steps every so often, so give it a few minutes.',
                    style: tt.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Check again',
            onPressed: _checking ? null : _check,
            icon: FIcon(Symbols.refresh, color: t.fg),
          ),
        ],
      ),
    );
  }
}

class _AISection extends StatefulWidget {
  const _AISection();

  @override
  State<_AISection> createState() => _AISectionState();
}

/// Two choices only: which model, and the API key for it.
class _AISectionState extends State<_AISection> {
  final _key = TextEditingController();
  bool _obscure = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final s = AppScope.read(context);
    final k = await s.keys.read(s.visionProvider.keyName);
    if (mounted) {
      setState(() {
        _key.text = k;
        _saved = k.isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final provider = state.visionProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('AI photo estimates'),
        DropdownButtonFormField<String>(
          initialValue: AiModel.byId(state.visionModel).id,
          decoration: InputDecoration(
            labelText: 'Model',
            helperText: AiModel.byId(state.visionModel).isSmart
                ? 'Each photo goes to Haiku first, and to Opus only when Haiku is unsure. Uses your Anthropic key.'
                : null,
            helperMaxLines: 3,
          ),
          borderRadius: BorderRadius.circular(S.radiusControl),
          dropdownColor: t.raised,
          isExpanded: true,
          items: [
            for (final m in AiModel.all)
              DropdownMenuItem(
                value: m.id,
                child: Text(m.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            state.setVisionModel(id);
            _loadKey(); // each company's key is kept separately
          },
        ),
        const SizedBox(height: S.sm),
        TextField(
          controller: _key,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: provider.keyLabel,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BlurSwitcher(
                  child: _saved
                      ? FIcon(Symbols.check, key: const ValueKey('saved'), color: t.good, weight: FontWeight.w600)
                      : const SizedBox(key: ValueKey('idle'), width: 0),
                ),
                IconButton(
                  tooltip: _obscure ? 'Show key' : 'Hide key',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: BlurSwitcher(
                    child: FIcon(
                      _obscure ? Symbols.visibility : Symbols.visibility_off,
                      key: ValueKey(_obscure),
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          onChanged: (v) async {
            // Postel: tolerate pasted whitespace and quotes around the key.
            final clean = v.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
            await state.keys.write(provider.keyName, clean);
            if (mounted) setState(() => _saved = clean.isNotEmpty);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, S.sm, 6, 0),
          child: Text(
            'Needed for meal-photo estimates. Nutrition labels are read on your phone without a key; with one, the AI reads them instead. The key stays in this device’s secure storage.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: S.lg),
        const _AiUsageGroup(),
      ],
    );
  }
}

class _DataSection extends StatefulWidget {
  const _DataSection();

  @override
  State<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<_DataSection> {
  bool _confirm = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    return FGroup(
      label: 'Data',
      children: [
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.base),
          child: _confirm
              ? Padding(
                  key: const ValueKey('confirm'),
                  padding: const EdgeInsets.all(S.md),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Delete every food log? This can’t be undone.')),
                      TextButton(onPressed: () => setState(() => _confirm = false), child: const Text('Keep')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: t.over),
                        onPressed: () {
                          state.deleteAllLogs();
                          setState(() => _confirm = false);
                          showToast(context, 'All food logs deleted');
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                )
              : FRow(
                  key: const ValueKey('ask'),
                  leading: FIcon(Symbols.delete, color: t.over),
                  label: 'Delete all food logs',
                  onTap: () => setState(() => _confirm = true),
                ),
        ),
        if (!AppState.demoAllowed)
          const SizedBox.shrink()
        else if (!state.isSample)
          FRow(
            leading: FIcon(Symbols.dataset, color: t.muted),
            label: 'Load sample data',
            sub: 'Replaces your log with 90 days of examples',
            onTap: () => state.loadSampleData(),
          )
        else
          FRow(
            leading: FIcon(Symbols.restart_alt, color: t.muted),
            label: 'Start my own plan',
            sub: 'Clears the sample data',
            onTap: state.startFresh,
          ),
      ],
    );
  }
}

/// "Check for updates": asks GitHub for the latest release and offers it.
class _UpdateRow extends StatefulWidget {
  const _UpdateRow();

  @override
  State<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<_UpdateRow> {
  bool _checking = false;
  String? _result;

  Future<void> _check() async {
    final state = AppScope.read(context);
    setState(() {
      _checking = true;
      _result = null;
    });
    String result;
    try {
      final u = await state.checkForUpdates(manual: true);
      result = u == null ? "You’re up to date" : 'Version ${u.label} is ready';
    } on UpdateCheckException catch (e) {
      result = e.message;
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final update = state.availableUpdate;
    final t = FT.of(context);
    if (PlatformCaps.isWeb) {
      return const FRow(label: 'Updates', sub: 'The web version is always the latest');
    }
    return FRow(
      leading: FIcon(Symbols.system_update, color: t.fg),
      label: update == null ? 'Check for updates' : 'Install version ${update.label}',
      sub: _result ?? (update == null ? 'From the Releases page on GitHub' : update.notes),
      onTap: _checking ? null : (update == null ? _check : () => openUpdate(context, update)),
      trailing: _checking
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
          : update == null
          ? FIcon(Symbols.refresh, color: t.muted)
          : FIcon(Symbols.download, color: t.fg, weight: FontWeight.w600),
    );
  }
}

/// What photo estimates cost and how much credit is left. The API key can't read the account
/// balance, so the user types it in once and FitTrack counts down from there using the token
/// counts the provider reports with every answer.
class _AiUsageGroup extends StatelessWidget {
  const _AiUsageGroup();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final month = state.aiUsageThisMonth.toList();
    final monthUsd = month.fold<double>(0, (a, u) => a + (u.usd ?? 0));
    final priced = state.visionProvider == VisionProvider.claude;
    final per = state.costPerPhotoUsd;
    final left = state.aiBalanceLeftUsd;
    final photos = state.photosLeft;
    final tokens = month.fold<int>(0, (a, u) => a + u.inputTokens + u.outputTokens);

    Widget value(String text, {Color? color}) => Text(
      text,
      style: tt.titleSmall!.copyWith(color: color, fontFeatures: tabular),
    );

    return FGroup(
      label: 'Usage',
      footer: Text(
        priced
            ? 'At Anthropic’s list prices. Your key can’t read your balance, so copy it from the Console’s Billing page.'
            : 'Prices for this provider aren’t tracked; its console shows your balance.',
      ),
      children: [
        FRow(
          label: 'This month',
          sub: month.isEmpty
              ? 'No photos sent yet'
              : '${month.length} ${month.length == 1 ? 'photo' : 'photos'} and labels',
          // Nothing on the right until there's something to count: the subtitle already says so.
          trailing: month.isEmpty ? null : value(priced ? formatUsd(monthUsd) : '${whole(tokens.toDouble())} tokens'),
        ),
        if (priced && per != null)
          FRow(
            label: 'Per photo',
            sub: state.costPerPhotoIsMeasured ? 'Average of your recent photos' : 'Estimate until you’ve sent some',
            trailing: value(formatUsd(per)),
          ),
        if (priced)
          FRow(
            label: 'Credit balance',
            sub: state.aiBalanceAt == null
                ? 'Optional: what your Anthropic Console shows'
                : 'Entered ${DateFormat('d MMM').format(state.aiBalanceAt!)}',
            trailing: NumberInput(
              key: ValueKey(state.aiBalanceAt),
              value: state.aiBalanceUsd,
              unit: 'US\$',
              hint: 'US\$',
              maxDigits: 2,
              width: 120,
              onChanged: (v) => state.setAiBalance(v),
            ),
          ),
        if (priced && left != null)
          FRow(
            label: 'Left now',
            sub: photos == null ? null : 'About $photos more ${photos == 1 ? 'photo' : 'photos'} at your current mix',
            trailing: value(formatUsd(left), color: photos != null && photos < 20 ? t.warn : null),
          ),
      ],
    );
  }
}
