import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../models/food.dart';
import '../../models/nutrients.dart';
import '../../models/util.dart';
import '../../services/health_service.dart';
import '../../services/platform_caps.dart';
import '../../widgets/common.dart';
import '../../widgets/rings.dart';
import '../../widgets/steps_card.dart';
import '../../widgets/update_banner.dart';
import '../../widgets/water_card.dart';
import '../log/log_flows.dart';
import 'add_menu.dart';
import 'edit_entry_sheet.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  DateTime _day = startOfDay(DateTime.now());
  double _active = 0;
  List<WorkoutSummary> _workouts = const [];
  int? _steps;
  final _collapsed = <MealType>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    final state = AppScope.read(context);
    if (!state.healthEnabled || !state.health.isSupported) {
      // No health store: sample data still shows example steps on the desktop preview.
      final sample = state.isSample ? state.sampleSteps[startOfDay(_day)] : null;
      if (_active != 0 || _workouts.isNotEmpty || _steps != sample) {
        setState(() {
          _active = 0;
          _workouts = const [];
          _steps = sample;
        });
      }
      return;
    }
    final day = _day;
    final active = await state.health.activeEnergy(day);
    final workouts = await state.health.workouts(day);
    final steps = await state.health.steps(day);
    if (mounted && day == _day) {
      setState(() {
        _active = active;
        _workouts = workouts;
        _steps = steps;
      });
    }
  }

  void _select(DateTime d) {
    setState(() => _day = startOfDay(d));
    _loadHealth();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final isToday = sameDay(_day, DateTime.now());
    final entries = state.entriesOn(_day);
    final consumed = Nutrients.sum(entries.map((e) => e.nutrients));
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;
    // Steps need a phone health store (or sample data on the preview).
    final canConnect = state.health.isSupported && !state.healthEnabled;
    final showSteps = _steps != null || state.health.isSupported;
    final stepsCard = StepsCard(steps: _steps, canConnect: canConnect);

    final summary = _SummaryCard(
      consumed: consumed,
      targets: state.targets,
      active: _active,
      showActive: state.healthEnabled && state.health.isSupported,
      includeActive: state.healthEnabled && state.addActiveEnergy,
      pulse: state.logPulse,
    );

    final meals = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, meal) in MealType.values.indexed) ...[
          if (i > 0) const SizedBox(height: S.md),
          Rise(
            delay: Duration(milliseconds: 60 + 30 * i),
            child: _MealCard(
              meal: meal,
              entries: entries.where((e) => e.meal == meal).toList(),
              collapsed: _collapsed.contains(meal),
              onToggle: () =>
                  setState(() => _collapsed.contains(meal) ? _collapsed.remove(meal) : _collapsed.add(meal)),
              onAdd: () => openManualEntry(context, day: _day, meal: meal),
            ),
          ),
        ],
        if (_workouts.isNotEmpty) ...[
          const SizedBox(height: S.xl),
          FGroup(
            label: 'Workouts',
            children: [
              for (final w in _workouts)
                FRow(
                  leading: FIcon(Symbols.fitness_center, color: t.fg),
                  label: w.name,
                  sub: '${DateFormat.jm().format(w.start)} · ${w.duration.inMinutes} min',
                  trailing: w.activeCalories == null
                      ? null
                      : Text(
                          Energy.format(w.activeCalories!),
                          style: tt.titleSmall!.copyWith(color: t.warn, fontFeatures: tabular),
                        ),
                ),
            ],
          ),
        ],
      ],
    );

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  padding: EdgeInsets.fromLTRB(_gutter(width), S.lg, _gutter(width), 0),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const UpdateBanner(),
                            if (state.isSample) const _SampleBanner(),
                            Row(
                              children: [
                                Expanded(
                                  child: BlurSwitcher(
                                    child: Align(
                                      key: ValueKey(_day),
                                      alignment: Alignment.centerLeft,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (isToday)
                                            Text(
                                              greeting(DateTime.now(), state.profile?.firstName ?? ''),
                                              style: tt.titleMedium!.copyWith(color: t.muted),
                                            ),
                                          Text(dayTitle(_day), style: tt.headlineMedium),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                AnimatedOpacity(
                                  opacity: isToday ? 0 : 1,
                                  duration: Motion.of(context, Motion.fast),
                                  child: IgnorePointer(
                                    ignoring: isToday,
                                    child: TextButton.icon(
                                      onPressed: () => _select(DateTime.now()),
                                      icon: const FIcon(Symbols.history, size: 18, weight: FontWeight.w600),
                                      label: const Text('Back to today'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: S.md),
                            DayCarousel(selected: _day, onSelect: _select),
                            const SizedBox(height: S.lg),
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 380,
                                    child: Column(
                                      children: [
                                        Rise(child: summary),
                                        const SizedBox(height: S.lg),
                                        Rise(
                                          delay: const Duration(milliseconds: 40),
                                          child: WaterCard(day: _day),
                                        ),
                                        if (showSteps) ...[
                                          const SizedBox(height: S.lg),
                                          Rise(delay: const Duration(milliseconds: 60), child: stepsCard),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: S.xl),
                                  Expanded(child: meals),
                                ],
                              )
                            else ...[
                              Rise(child: summary),
                              const SizedBox(height: S.lg),
                              Rise(
                                delay: const Duration(milliseconds: 40),
                                child: WaterCard(day: _day),
                              ),
                              if (showSteps) ...[
                                const SizedBox(height: S.lg),
                                Rise(delay: const Duration(milliseconds: 60), child: stepsCard),
                              ],
                              const SizedBox(height: S.xl),
                              meals,
                            ],
                            const SizedBox(height: 120), // room so the add button never covers a row
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          AddMenu(day: _day),
        ],
      ),
    );
  }
}

double _gutter(double width) => width >= 840 ? S.xxl : S.lg;

class _SampleBanner extends StatelessWidget {
  const _SampleBanner();

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final note = PlatformCaps.hasCamera ? '' : ' Barcode scanning and meal photos need the phone app.';
    return Padding(
      padding: const EdgeInsets.only(bottom: S.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.sm, S.sm),
        decoration: BoxDecoration(
          color: t.warn.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(S.radiusControl),
          border: Border.all(color: t.warn.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            FIcon(Symbols.info, size: 18, color: t.warn, weight: FontWeight.w500),
            const SizedBox(width: S.sm),
            Expanded(child: Text('You\'re looking at sample data.$note', style: tt.bodyMedium)),
            TextButton(onPressed: () => AppScope.read(context).startFresh(), child: const Text('Start my plan')),
          ],
        ),
      ),
    );
  }
}

/// The last three weeks as a swipeable strip; edges fade so it's clear there's more.
class DayCarousel extends StatelessWidget {
  const DayCarousel({super.key, required this.selected, required this.onSelect});
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final today = startOfDay(DateTime.now());
    final target = state.targets.calories;

    return SizedBox(
      height: 92,
      child: FadeEdges(
        inset: 0.06,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          reverse: true, // today sits at the right edge, like a calendar strip
          padding: const EdgeInsets.symmetric(horizontal: S.xl),
          itemCount: 21,
          separatorBuilder: (_, _) => const SizedBox(width: S.sm),
          itemBuilder: (context, i) {
            final day = addDays(today, -i);
            final isSel = sameDay(day, selected);
            final kcal = state.consumedOn(day).calories;
            return Squishy(
              onTap: () => onSelect(day),
              feel: PressFeel.subtle,
              semanticLabel: DateFormat('EEEE, MMMM d').format(day),
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.fast),
                curve: Motion.standard,
                width: 56,
                decoration: BoxDecoration(
                  color: isSel ? t.raised : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: isSel ? t.border : Colors.transparent),
                  boxShadow: isSel ? t.shadow : null,
                ),
                padding: const EdgeInsets.symmetric(vertical: S.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('EEE').format(day).substring(0, 2),
                      style: tt.labelMedium!.copyWith(color: isSel ? t.fg : t.muted),
                    ),
                    MiniRing(progress: target > 0 ? kcal / target : 0, size: 28),
                    Text(
                      '${day.day}',
                      style: tt.titleSmall!.copyWith(fontFeatures: tabular, color: isSel ? t.fg : t.muted),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.consumed,
    required this.targets,
    required this.active,
    required this.showActive,
    required this.includeActive,
    required this.pulse,
  });

  final Nutrients consumed;
  final Nutrients targets;
  final double active;
  final bool showActive;
  final bool includeActive;
  final Listenable pulse;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final budget = targets.calories + (includeActive ? active : 0);
    final narrow = MediaQuery.sizeOf(context).width < 400;

    final stats = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Stat(icon: Symbols.flag, label: 'Goal', value: targets.calories, color: t.muted),
        const SizedBox(height: S.lg),
        _Stat(icon: Symbols.restaurant, label: 'Eaten', value: consumed.calories, color: t.calories),
        if (showActive) ...[
          const SizedBox(height: S.lg),
          _Stat(
            icon: Symbols.local_fire_department,
            label: includeActive ? 'Active (+)' : 'Active',
            value: active,
            color: t.warn,
          ),
        ],
      ],
    );

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        children: [
          Row(
            children: [
              CalorieRing(
                consumed: consumed.calories,
                budget: budget,
                pulse: pulse,
                size: narrow ? 150 : 176,
                stroke: narrow ? 16 : 18,
              ),
              const SizedBox(width: S.xl),
              Expanded(child: stats),
            ],
          ),
          const SizedBox(height: S.xl),
          Divider(color: t.border),
          const SizedBox(height: S.lg),
          Row(
            children: [
              for (final m in Macro.values)
                Expanded(
                  child: MacroGauge(label: m.title, consumed: consumed.of(m), target: targets.of(m), color: t.macro(m)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        children: [
          FIcon(icon, size: 20, color: color, weight: FontWeight.w600, fill: true),
          const SizedBox(width: S.md),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: tt.bodySmall),
                CountUp(
                  value: value,
                  format: (v) => Energy.format(v),
                  style: tt.titleMedium!.copyWith(fontFeatures: tabular),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.entries,
    required this.collapsed,
    required this.onToggle,
    required this.onAdd,
  });

  final MealType meal;
  final List<FoodEntry> entries;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final kcal = entries.fold<double>(0, (a, e) => a + e.nutrients.calories);
    const radius = S.radiusCard - 4;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.border),
        boxShadow: t.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Squishy(
            onTap: onToggle,
            feel: PressFeel.subtle,
            hitSlop: 0,
            semanticLabel: '${meal.title}, ${whole(kcal)} kilocalories, ${collapsed ? 'collapsed' : 'expanded'}',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.md, S.md),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: t.inset,
                      // Nested radius: card corner minus the 16 px inset, kept round enough to read as a chip.
                      borderRadius: BorderRadius.circular(S.inner(radius, S.lg).clamp(10, 12)),
                    ),
                    child: Center(
                      child: FIcon(mealIcon(meal), size: 20, color: t.fg, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: S.md),
                  Expanded(child: Text(meal.title, style: tt.titleMedium)),
                  Text(
                    Energy.format(kcal),
                    style: tt.bodyMedium!.copyWith(color: t.muted, fontFeatures: tabular),
                  ),
                  const SizedBox(width: S.xs),
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: Motion.of(context, Motion.fast),
                    child: FIcon(Symbols.expand_more, size: 22, color: t.muted, weight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.base),
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(color: t.border),
                      if (entries.isEmpty)
                        Squishy(
                          onTap: onAdd,
                          feel: PressFeel.subtle,
                          hitSlop: 0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: 14),
                            child: Row(
                              children: [
                                Text('Nothing logged yet', style: tt.bodyMedium!.copyWith(color: t.muted)),
                                const Spacer(),
                                FIcon(Symbols.add, size: 18, color: t.fg, weight: FontWeight.w600),
                                const SizedBox(width: 4),
                                Text('Add', style: tt.labelLarge!.copyWith(color: t.fg)),
                              ],
                            ),
                          ),
                        ),
                      for (final (i, e) in entries.indexed) ...[
                        if (i > 0) Divider(indent: 56, color: t.border),
                        _EntryRow(entry: e),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final FoodEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final state = AppScope.read(context);

    // List rows are the most frequently touched thing in the app: no squash, just a quick tint.
    final row = InkWell(
      onTap: () => showEditEntrySheet(context, entry),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.md),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: FIcon(sourceIcon(entry.source), size: 18, color: t.muted, weight: FontWeight.w400),
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(entry.name, style: tt.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (entry.trust != null) ...[const SizedBox(width: 4), TrustTag(entry.trust!, compact: true)],
                    ],
                  ),
                  Text(
                    [?entry.brand, entry.portionDescription].join(' · '),
                    style: tt.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: S.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Energy.format(entry.nutrients.calories), style: tt.titleSmall!.copyWith(fontFeatures: tabular)),
                MacroInline(entry.nutrients),
              ],
            ),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: t.over,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: S.xl),
        child: const FIcon(Symbols.delete, color: Colors.white, weight: FontWeight.w600),
      ),
      onDismissed: (_) {
        state.deleteEntry(entry);
        showToast(context, 'Deleted ${entry.name}', actionLabel: 'Undo', onAction: () => state.restoreEntry(entry));
      },
      child: Semantics(hint: 'Double-tap to edit, swipe left to delete', child: row),
    );
  }
}
