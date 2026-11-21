import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/oklch.dart';
import '../../design/tokens.dart';
import '../../models/nutrients.dart';
import '../../models/util.dart';
import '../../services/ai_vision.dart';
import '../../services/platform_caps.dart';
import '../../widgets/common.dart';
import 'profile_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 840 ? S.xxl : S.lg;
    final twoCol = width >= 1000;

    final left = [
      const ProfileSection(),
      const SizedBox(height: S.xl),
      const _TargetsSection(),
      const SizedBox(height: S.xl),
      const _UnitsSection(),
      const SizedBox(height: S.xl),
      const _DataSection(),
    ];
    final right = [
      const _HealthSection(),
      const SizedBox(height: S.xl),
      const _AISection(),
      const SizedBox(height: S.xl),
      FGroup(
        label: 'About',
        children: [
          const FRow(label: 'Product data', sub: 'Open Food Facts, ODbL licence'),
          FRow(
            label: 'Version',
            trailing: Text('2.0', style: tt.bodyLarge!.copyWith(color: FT.of(context).muted)),
          ),
        ],
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
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
    );
  }
}

class _TargetsSection extends StatelessWidget {
  const _TargetsSection();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tg = state.targets;
    final macroKcal = tg.protein * 4 + tg.carbs * 4 + tg.fat * 9;
    final diff = macroKcal - tg.calories;

    void set(Nutrients Function(Nutrients n, double v) f, double? v) {
      if (v == null || v < 0) return;
      state.updateProfile((p) => p.targets = f(p.targets, v.roundToDouble()));
    }

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
            leading: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: t.macro(m), shape: BoxShape.circle),
            ),
            label: m.title,
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
          leading: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: const Oklch(0.68, 0.13, 235).toColor(), shape: BoxShape.circle),
          ),
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
        FRow(
          label: "Reset to my profile's plan",
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
        footer: const Text('Apple Health and Health Connect sync run in the phone app.'),
        children: [
          FRow(
            leading: FIcon(Symbols.favorite, color: t.muted),
            label: 'Health sync',
            trailing: const StatusPill(text: 'Phone only', color: Color(0xFF8A8F8C)),
          ),
        ],
      );
    }
    final name = state.health.storeName;
    return FGroup(
      label: name,
      footer: state.healthError != null
          ? StatusPill(text: state.healthError!, color: t.warn, icon: Symbols.info)
          : Text('Reads active energy, workouts and weight. Logged meals are saved as nutrition in $name.'),
      children: [
        FRow(
          leading: FIcon(Symbols.favorite, color: t.over, fill: true),
          label: 'Sync with $name',
          trailing: Switch(value: state.healthEnabled, onChanged: state.setHealthEnabled),
        ),
        FRow(
          label: 'Add active energy to budget',
          sub: 'Exercise calories raise today\'s goal',
          trailing: Switch(
            value: state.addActiveEnergy,
            onChanged: state.healthEnabled ? state.setAddActiveEnergy : null,
          ),
        ),
      ],
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
          decoration: const InputDecoration(labelText: 'Model'),
          borderRadius: BorderRadius.circular(S.radiusControl),
          dropdownColor: t.raised,
          items: [for (final m in AiModel.all) DropdownMenuItem(value: m.id, child: Text(m.label))],
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
            'Used for meal photos and nutrition labels. The key stays in this device\'s secure storage.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
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
                      const Expanded(child: Text('Delete every food log? This can\'t be undone.')),
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
        if (!state.isSample)
          FRow(
            leading: FIcon(Symbols.auto_awesome, color: t.muted),
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
