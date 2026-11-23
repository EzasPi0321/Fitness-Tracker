import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/weight_trend.dart';
import 'body_fat.dart';
import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/oklch.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../models/gym.dart';
import '../../models/nutrients.dart';
import '../../models/profile.dart';
import '../../models/sleep.dart';
import '../../models/util.dart';
import '../../services/health_service.dart';
import '../../widgets/common.dart';

enum TrendRange {
  week(7, '7D'),
  month(30, '30D'),
  quarter(90, '90D');

  const TrendRange(this.days, this.label);
  final int days;
  final String label;
}

class _Day {
  _Day(this.date, this.n, this.count);
  final DateTime date;
  final Nutrients n;
  final int count;
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  TrendRange _range = TrendRange.week;
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<WeightSample> _healthWeights = const [];
  List<SleepNight> _healthSleep = const [];
  List<WeightSample> _healthBodyFat = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    final s = AppScope.read(context);
    if (!s.healthEnabled || !s.health.isSupported) return;
    final since = addDays(DateTime.now(), -TrendRange.quarter.days);
    final w = await s.health.weightHistory(since);
    final sl = await s.health.sleep(startOfDay(since), DateTime.now());
    // Body fat is measured every few weeks, so look back a year rather than the chart range.
    final bf = await s.health.bodyFatHistory(addDays(DateTime.now(), -365));
    if (mounted) {
      setState(() {
        _healthWeights = w;
        _healthSleep = sl;
        _healthBodyFat = bf;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 840 ? S.xxl : S.lg;
    final today = startOfDay(DateTime.now());
    final start = addDays(today, -(_range.days - 1));
    final days = [
      for (var i = 0; i < _range.days; i++)
        () {
          final d = addDays(start, i);
          final list = state.entriesOn(d);
          return _Day(d, Nutrients.sum(list.map((e) => e.nutrients)), list.length);
        }(),
    ];
    final logged = days.where((d) => d.count > 0).toList();
    final metric = state.profile?.usesMetric ?? true;
    // The trend runs over all weigh-ins, so it's already settled when the chart's period starts.
    final allWeights = (state.healthEnabled && _healthWeights.isNotEmpty)
        ? _healthWeights
        : state.weightsByDate.map((w) => WeightSample(w.date, w.kilograms)).toList();
    final trendAll = weightTrend([for (final w in allWeights) (w.date, w.kilograms)]);
    final weights = allWeights.where((w) => !w.date.isBefore(start)).toList();
    final trend = [
      for (final p in trendAll)
        if (!p.$1.isBefore(start)) WeightSample(p.$1, p.$2),
    ];

    final calorie = _CalorieCard(days: days, logged: logged, target: state.targets.calories, range: _range);
    final macros = _MacroCard(logged: logged, targets: state.targets);
    final weight = _WeightCard(
      points: weights,
      trend: trend,
      weeklyChange: weeklyTrendChange(trendAll),
      metric: metric,
      start: start,
    );
    final bodyFat = BodyFatCard(
      readings: mergeBodyFat(state.bodyFatByDate, state.healthEnabled ? _healthBodyFat : const []),
      metric: metric,
    );
    // Logged nights win over the health store's for the same morning.
    final nights = {...nightsByDay(_healthSleep), ...state.loggedNights};
    final sleepCard = _SleepTrendCard(
      days: [for (final d in days) d.date],
      nights: nights,
      goalHours: state.sleepGoalHours,
      range: _range,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(gutter, S.lg, gutter, S.xxl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: S.md,
                      spacing: S.md,
                      children: [
                        Text('Progress', style: tt.headlineMedium),
                        Wrap(
                          spacing: S.sm,
                          runSpacing: S.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SegmentedButton<TrendRange>(
                              segments: [
                                for (final r in TrendRange.values) ButtonSegment(value: r, label: Text(r.label)),
                              ],
                              selected: {_range},
                              showSelectedIcon: false,
                              onSelectionChanged: (s) => setState(() => _range = s.first),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => showLogWeightSheet(context),
                              icon: const FIcon(Symbols.monitor_weight, size: 20, weight: FontWeight.w600),
                              label: const Text('Log weight'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: S.xl),
                    Rise(child: calorie),
                    const SizedBox(height: S.lg),
                    if (width >= 900)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Rise(delay: const Duration(milliseconds: 60), child: macros),
                          ),
                          const SizedBox(width: S.lg),
                          Expanded(
                            child: Rise(delay: const Duration(milliseconds: 90), child: weight),
                          ),
                        ],
                      )
                    else ...[
                      Rise(delay: const Duration(milliseconds: 60), child: macros),
                      const SizedBox(height: S.lg),
                      Rise(delay: const Duration(milliseconds: 90), child: weight),
                    ],
                    const SizedBox(height: S.lg),
                    Rise(delay: const Duration(milliseconds: 105), child: bodyFat),
                    const SizedBox(height: S.lg),
                    Rise(delay: const Duration(milliseconds: 120), child: sleepCard),
                    const SizedBox(height: S.lg),
                    Rise(
                      delay: const Duration(milliseconds: 150),
                      child: _GymYearCard(sessions: state.gym),
                    ),
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

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, this.sub);
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: tt.titleLarge),
        const SizedBox(height: 2),
        Text(
          sub,
          style: tt.bodyMedium!.copyWith(color: FT.of(context).muted, fontFeatures: tabular),
        ),
      ],
    );
  }
}

/// Compact axis label: 2,500 → "2.5k".
String _compact(double v) {
  if (v.abs() < 1000) return whole(v);
  final k = v / 1000;
  return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k';
}

/// Grid lines: hairline, dashed and quiet, so data carries the weight.
/// Which days get a date under the axis. Every chart uses the same rule, so their dates line
/// up: each day for a week, otherwise four evenly spaced dates from the first day to today.
bool isAxisTick(int i, int days) {
  if (i < 0 || i >= days) return false;
  if (days <= 7) return true;
  for (var k = 0; k <= 3; k++) {
    if (i == ((days - 1) * k / 3).round()) return true;
  }
  return false;
}

/// Width of the value labels on the left of every chart.
const _axisW = 36.0;

/// A logged day is on target when it's at or under the goal, or no more than 10% over it.
/// Days under half the goal don't count: most likely not everything was logged.
bool onCalorieTarget(double calories, double target) =>
    target <= 0 || (calories >= target * 0.5 && calories <= target * 1.1);

FlLine _gridLine(FT t) => FlLine(color: t.border.withValues(alpha: 0.5), strokeWidth: 0.6);

class _CalorieCard extends StatelessWidget {
  const _CalorieCard({required this.days, required this.logged, required this.target, required this.range});
  final List<_Day> days;
  final List<_Day> logged;
  final double target;
  final TrendRange range;

  static const _chartH = 220.0;
  static const _bottomH = 26.0;

  double _step(double max) {
    for (final s in [250.0, 500.0, 1000.0, 2000.0, 2500.0, 5000.0]) {
      if (max / s <= 4) return s;
    }
    return 10000;
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final avg = logged.isEmpty ? 0.0 : logged.fold<double>(0, (a, d) => a + d.n.calories) / logged.length;
    final onTarget = logged.where((d) => onCalorieTarget(d.n.calories, target)).length;
    final over = logged.where((d) => d.n.calories > target * 1.1).length;
    final maxCal = days.fold<double>(0, (a, d) => math.max(a, d.n.calories));
    // The chart is drawn in the user's energy unit so its axis lands on round numbers.
    final k = Energy.toDisplay(1);
    final rawMax = math.max(target * 1.2, maxCal * 1.06) * k;
    final step = _step(rawMax);
    final maxY = (rawMax / step).ceil() * step;
    // Bars are neutral; colour is saved for meaning: the goal line, and days over it.
    final barColor = t.fg.withValues(alpha: t.dark ? 0.86 : 0.78);
    final goalColor = t.calories;
    final today = startOfDay(DateTime.now());

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            Energy.isKJ ? 'Energy intake' : 'Calorie intake',
            logged.isEmpty ? 'No meals logged in this period' : 'Average ${Energy.format(avg)} a day',
          ),
          const SizedBox(height: S.md),
          Wrap(
            spacing: S.lg,
            runSpacing: S.xs,
            children: [
              _LegendItem(
                swatch: _LineSwatch(color: goalColor),
                label: 'Goal ${Energy.format(target)}',
              ),
              _LegendItem(
                swatch: _BarSwatch(color: barColor),
                label: 'Eaten',
              ),
              if (over > 0)
                _LegendItem(
                  swatch: _BarSwatch(color: t.over),
                  label: 'Over goal',
                ),
            ],
          ),
          const SizedBox(height: S.lg),
          SizedBox(
            height: _chartH,
            child: LayoutBuilder(
              builder: (context, c) {
                // Bars take about a third of their slot: slim, but sized to the screen.
                final slot = (c.maxWidth - _axisW) / days.length;
                final barW = (slot * 0.36).clamp(2.0, 24.0);
                final radius = math.min(barW / 2, 4.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: BarChart(
                          duration: Motion.of(context, Motion.slow),
                          curve: Motion.standard,
                          BarChartData(
                            maxY: maxY,
                            minY: 0,
                            alignment: BarChartAlignment.spaceAround,
                            gridData: FlGridData(
                              drawVerticalLine: false,
                              horizontalInterval: step,
                              getDrawingHorizontalLine: (_) => _gridLine(t),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border(bottom: BorderSide(color: t.border)),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(),
                              rightTitles: const AxisTitles(),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: _axisW,
                                  interval: step,
                                  getTitlesWidget: (v, meta) => SideTitleWidget(
                                    meta: meta,
                                    child: Text(
                                      _compact(v),
                                      style: tt.labelSmall!.copyWith(color: t.muted, fontFeatures: tabular),
                                    ),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: _bottomH,
                                  getTitlesWidget: (v, meta) {
                                    final i = v.toInt();
                                    if (!isAxisTick(i, days.length)) return const SizedBox.shrink();
                                    final d = days[i].date;
                                    final isToday = d == today;
                                    final label = range == TrendRange.week
                                        ? (isToday ? 'Today' : DateFormat('EEE').format(d))
                                        : DateFormat('d MMM').format(d);
                                    return SideTitleWidget(
                                      meta: meta,
                                      fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                                      child: Text(
                                        label,
                                        style: tt.labelSmall!.copyWith(
                                          color: isToday ? t.fg : t.muted,
                                          fontWeight: isToday ? FontWeight.w600 : null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            extraLinesData: ExtraLinesData(
                              extraLinesOnTop: true,
                              horizontalLines: [HorizontalLine(y: target * k, color: goalColor, strokeWidth: 1.5)],
                            ),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (_) => t.raised,
                                tooltipBorder: BorderSide(color: t.border),
                                tooltipBorderRadius: BorderRadius.circular(12),
                                tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                getTooltipItem: (group, _, rod, _) {
                                  final d = days[group.x];
                                  final pct = target > 0 ? (d.n.calories / target * 100).round() : 0;
                                  return BarTooltipItem(
                                    '${DateFormat('EEE d MMM').format(d.date)}\n',
                                    tt.labelSmall!.copyWith(color: t.muted),
                                    textAlign: TextAlign.left,
                                    children: [
                                      TextSpan(
                                        text: '${Energy.format(d.n.calories)}  ',
                                        style: tt.titleSmall!.copyWith(fontFeatures: tabular),
                                      ),
                                      TextSpan(
                                        text: '$pct%\n',
                                        style: tt.labelSmall!.copyWith(
                                          color: d.n.calories > target * 1.1 ? t.over : t.muted,
                                          fontFeatures: tabular,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'P ${whole(d.n.protein)}  C ${whole(d.n.carbs)}  F ${whole(d.n.fat)}',
                                        style: tt.labelSmall!.copyWith(color: t.muted, fontFeatures: tabular),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            barGroups: [
                              for (final (i, d) in days.indexed)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: d.n.calories * k,
                                      width: barW,
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                                      color: d.n.calories > target * 1.1 ? t.over : barColor,
                                      backDrawRodData: BackgroundBarChartRodData(
                                        show: range != TrendRange.quarter,
                                        toY: maxY,
                                        color: t.fg.withValues(alpha: 0.025),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: S.xl),
          Divider(height: 1, color: t.border),
          const SizedBox(height: S.lg),
          Row(
            children: [
              Expanded(child: _Tile('Days logged', '${logged.length}', suffix: '/${range.days}')),
              Expanded(
                child: _Tile(
                  'On target',
                  '$onTarget',
                  suffix: onTarget == 1 ? ' day' : ' days',
                  valueColor: onTarget > 0 ? t.good : null,
                ),
              ),
              Expanded(
                child: _Tile(
                  'Over goal',
                  '$over',
                  suffix: over == 1 ? ' day' : ' days',
                  valueColor: over > 0 ? t.over : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.swatch, required this.label});
  final Widget swatch;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: FT.of(context).muted)),
      ],
    );
  }
}

class _BarSwatch extends StatelessWidget {
  const _BarSwatch({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
  );
}

class _LineSwatch extends StatelessWidget {
  const _LineSwatch({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 2,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
  );
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.suffix, this.valueColor});
  final String label;
  final String value;
  final String? suffix;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: tt.titleLarge!.copyWith(color: valueColor ?? t.fg, fontFeatures: tabular),
              ),
              if (suffix != null)
                TextSpan(
                  text: suffix,
                  style: tt.bodySmall!.copyWith(color: t.muted, fontFeatures: tabular),
                ),
            ],
          ),
          maxLines: 1,
        ),
      ],
    );
  }
}

class _MacroCard extends StatelessWidget {
  const _MacroCard({required this.logged, required this.targets});
  final List<_Day> logged;
  final Nutrients targets;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final avg = logged.isEmpty ? Nutrients.zero : Nutrients.sum(logged.map((d) => d.n)) * (1 / logged.length);

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Average macros', 'Per logged day, against your target'),
          const SizedBox(height: S.xl),
          for (final (i, m) in Macro.values.indexed) ...[
            if (i > 0) const SizedBox(height: S.lg + 2),
            _MacroRow(label: m.title, color: t.macro(m), value: avg.of(m), target: targets.of(m)),
          ],
        ],
      ),
    );
  }
}

/// One macro: name and numbers on top, a slim track below with the target marked.
/// The track runs to 125% of target so overshoot stays visible.
class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.label, required this.color, required this.value, required this.target});
  final String label;
  final Color color;
  final double value;
  final double target;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    const span = 1.25;
    final frac = target > 0 ? (value / (target * span)).clamp(0.0, 1.0) : 0.0;
    final tick = 1 / span;
    final pct = target > 0 ? (value / target * 100).round() : 0;
    final over = target > 0 && value > target * 1.1;

    return Semantics(
      label: label,
      value: '${whole(value)} of ${whole(target)} grams',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: tt.bodyMedium)),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: whole(value),
                      style: tt.titleSmall!.copyWith(fontFeatures: tabular),
                    ),
                    TextSpan(
                      text: ' / ${whole(target)} g',
                      style: tt.bodySmall!.copyWith(color: t.muted, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '$pct%',
                  textAlign: TextAlign.right,
                  style: tt.labelSmall!.copyWith(color: over ? t.over : t.muted, fontFeatures: tabular),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(color: t.inset, borderRadius: BorderRadius.circular(3)),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: frac),
                      duration: Motion.of(context, Motion.slow),
                      curve: Motion.settle,
                      builder: (context, f, _) => Container(
                        width: w * f,
                        height: 6,
                        decoration: BoxDecoration(color: over ? t.over : color, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    // Target: a thin full-height tick with a gap cut around it, so it reads on any fill.
                    Positioned(
                      left: (w * tick - 2.5).clamp(0, w - 5),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 5,
                        decoration: BoxDecoration(
                          color: t.fg,
                          borderRadius: BorderRadius.circular(2.5),
                          border: Border.all(color: t.surface, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({
    required this.points,
    required this.trend,
    required this.weeklyChange,
    required this.metric,
    required this.start,
  });
  final List<WeightSample> points;

  /// The smoothed line, one value per weigh-in, and how far it moved in the last week (kg).
  final List<WeightSample> trend;
  final double? weeklyChange;
  final bool metric;
  final DateTime start;

  double _d(double kg) => metric ? kg : kg * poundsPerKilogram;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final unit = metric ? 'kg' : 'lb';
    // Lead with the trend, not the last scale reading: it's the number that means something.
    String sub = 'No weigh-ins in this period';
    if (trend.length >= 2) {
      final w = weeklyChange;
      final rate = w == null
          ? ''
          : w.abs() < 0.05
          ? ' · steady'
          : ' · ${w > 0 ? '+' : '−'}${oneDecimal(_d(w.abs()))} $unit a week';
      sub = 'Trend ${oneDecimal(_d(trend.last.kilograms))} $unit$rate';
    } else if (points.isNotEmpty) {
      sub = '${oneDecimal(_d(points.last.kilograms))} $unit';
    }
    final now = DateTime.now();
    final today = startOfDay(now);
    final days = (today.difference(start).inHours / 24).round() + 1;
    double x(DateTime d) => d.difference(start).inMinutes / 1440;

    Widget body;
    if (points.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: S.xl),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: () => showLogWeightSheet(context),
            icon: const FIcon(Symbols.add, size: 20, weight: FontWeight.w600),
            label: const Text('Log your weight'),
          ),
        ),
      );
    } else {
      final vals = [...points, ...trend].map((p) => _d(p.kilograms)).toList();
      final lo = (vals.reduce(math.min) - 1).floorToDouble();
      final hi = (vals.reduce(math.max) + 1).ceilToDouble();
      final interval = math.max(1.0, ((hi - lo) / 4).ceilToDouble());
      final spots = [for (final p in points) FlSpot(x(p.date), _d(p.kilograms))];
      final trendSpots = [for (final p in trend) FlSpot(x(p.date), _d(p.kilograms))];
      final showTrend = trendSpots.length >= 2;
      final wo = t.bodyO;
      body = SizedBox(
        height: 200,
        child: RepaintBoundary(
          child: LineChart(
            duration: Motion.of(context, Motion.slow),
            curve: Motion.standard,
            LineChartData(
              minX: 0,
              maxX: x(now),
              minY: lo,
              maxY: hi,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => _gridLine(t),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    // One title per day, kept only on the same dates as the other charts.
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (v != i || !isAxisTick(i, days)) return const SizedBox.shrink();
                      final d = addDays(start, i);
                      final label = days <= 7
                          ? (d == today ? 'Today' : DateFormat('EEE').format(d))
                          : DateFormat('d MMM').format(d);
                      return SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          label,
                          style: tt.labelSmall!.copyWith(
                            color: d == today ? t.fg : t.muted,
                            fontWeight: d == today ? FontWeight.w600 : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: _axisW,
                    interval: interval,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        v.toStringAsFixed(0),
                        style: tt.labelSmall!.copyWith(color: t.muted, fontFeatures: tabular),
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => t.raised,
                  tooltipBorder: BorderSide(color: t.border),
                  tooltipBorderRadius: BorderRadius.circular(12),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${showTrend ? (s.barIndex == 0 ? 'Weighed ' : 'Trend ') : ''}${oneDecimal(s.y)} $unit\n',
                        tt.titleSmall!.copyWith(fontFeatures: tabular),
                        children: [
                          TextSpan(
                            text: DateFormat('EEE, MMM d').format(start.add(Duration(minutes: (s.x * 1440).round()))),
                            style: tt.bodySmall,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                if (showTrend)
                  LineChartBarData(
                    spots: spots,
                    barWidth: 0,
                    color: Colors.transparent,
                    dotData: FlDotData(
                      getDotPainter: (spot, _, _, i) =>
                          FlDotCirclePainter(radius: 2.5, color: wo.withAlpha(0.45).toColor(), strokeWidth: 0),
                    ),
                  ),
                LineChartBarData(
                  spots: showTrend ? trendSpots : spots,
                  isCurved: true, // moves along curves, not straight segments
                  curveSmoothness: 0.3,
                  preventCurveOverShooting: true,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  color: wo.toColor(),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: oklchStops([wo.withAlpha(0.16), wo.withAlpha(0)], steps: 6),
                    ),
                  ),
                  // Only the latest weigh-in gets a dot: the line carries the rest.
                  dotData: FlDotData(
                    checkToShowDot: (spot, bar) => spot == bar.spots.last,
                    getDotPainter: (spot, _, _, i) =>
                        FlDotCirclePainter(radius: 4.5, color: wo.toColor(), strokeWidth: 2.5, strokeColor: t.surface),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('Body weight', sub),
          if (trend.length >= 2) ...[
            const SizedBox(height: S.md),
            Wrap(
              spacing: S.lg,
              runSpacing: S.xs,
              children: [
                _LegendItem(
                  swatch: _LineSwatch(color: t.bodyO.toColor()),
                  label: 'Trend',
                ),
                _LegendItem(
                  swatch: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: t.bodyO.withAlpha(0.45).toColor()),
                  ),
                  label: 'Weigh-ins',
                ),
              ],
            ),
            const SizedBox(height: S.lg),
          ] else
            const SizedBox(height: S.xl),
          body,
        ],
      ),
    );
  }
}

Future<void> showLogWeightSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => const _LogWeightSheet(),
  );
}

class _LogWeightSheet extends StatefulWidget {
  const _LogWeightSheet();

  @override
  State<_LogWeightSheet> createState() => _LogWeightSheetState();
}

class _LogWeightSheetState extends State<_LogWeightSheet> {
  late final bool _metric = AppScope.read(context).profile?.usesMetric ?? true;
  late double? _value = () {
    final kg = AppScope.read(context).profile?.weightKg ?? 70;
    return ((_metric ? kg : kg * poundsPerKilogram) * 10).round() / 10;
  }();
  DateTime _date = DateTime.now();

  Future<void> _save() async {
    final v = _value;
    if (v == null || v <= 0) return;
    final kg = _metric ? v : v / poundsPerKilogram;
    Navigator.pop(context);
    await AppScope.read(context).addWeight(kg, _date);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log weight', style: tt.headlineSmall),
            const SizedBox(height: S.lg),
            FGroup(
              children: [
                FRow(
                  label: 'Weight',
                  trailing: NumberInput(
                    value: _value,
                    unit: _metric ? 'kg' : 'lb',
                    onChanged: (v) => setState(() => _value = v),
                  ),
                ),
                FRow(
                  label: 'Date',
                  trailing: Text(
                    DateFormat('EEE, MMM d').format(_date),
                    style: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, 8));
                  },
                ),
              ],
            ),
            const SizedBox(height: S.xl),
            FilledButton(onPressed: (_value ?? 0) > 0 ? _save : null, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}

/// Hours asleep each night against the goal. Same build as the calorie chart: neutral bars,
/// a solid goal line with its value in its own gutter, and three plain stats underneath.
class _SleepTrendCard extends StatelessWidget {
  const _SleepTrendCard({required this.days, required this.nights, required this.goalHours, required this.range});
  final List<DateTime> days;
  final Map<DateTime, SleepNight> nights;
  final double goalHours;
  final TrendRange range;

  static const _chartH = 200.0;
  static const _bottomH = 26.0;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final inRange = [
      for (final d in days)
        if (nights[d] != null) nights[d]!,
    ];
    double hours(SleepNight n) => n.asleep.inMinutes / 60;
    final avg = inRange.isEmpty ? 0.0 : inRange.fold<double>(0, (a, n) => a + hours(n)) / inRange.length;
    final onGoal = inRange.where((n) => hours(n) >= goalHours - 0.25).length;
    // Usual bedtime: the median, counting minutes from noon so 11 PM and 1 AM sit together.
    String? usualBed;
    if (inRange.isNotEmpty) {
      final mins = [for (final n in inRange) ((n.start.hour + 12) % 24) * 60 + n.start.minute]..sort();
      final m = mins[mins.length ~/ 2];
      final at = DateTime(2000, 1, 1, ((m ~/ 60) + 12) % 24, m % 60);
      usualBed = DateFormat.jm().format(at);
    }
    final maxH = math.max(10.0, inRange.fold<double>(goalHours + 1, (a, n) => math.max(a, hours(n)))).ceilToDouble();
    final barColor = t.fg.withValues(alpha: t.dark ? 0.86 : 0.78);
    final goalColor = t.bodyO.toColor();
    final today = startOfDay(DateTime.now());

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'Sleep',
            inRange.isEmpty
                ? 'No nights in this period'
                : 'Average ${formatSleep(Duration(minutes: (avg * 60).round()))} a night',
          ),
          const SizedBox(height: S.md),
          Wrap(
            spacing: S.lg,
            runSpacing: S.xs,
            children: [
              _LegendItem(
                swatch: _LineSwatch(color: goalColor),
                label: 'Goal ${formatSleep(Duration(minutes: (goalHours * 60).round()))}',
              ),
              _LegendItem(
                swatch: _BarSwatch(color: barColor),
                label: 'Asleep',
              ),
            ],
          ),
          const SizedBox(height: S.lg),
          SizedBox(
            height: _chartH,
            child: LayoutBuilder(
              builder: (context, c) {
                final slot = (c.maxWidth - _axisW) / days.length;
                final barW = (slot * 0.36).clamp(2.0, 24.0);
                final radius = math.min(barW / 2, 4.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: BarChart(
                          duration: Motion.of(context, Motion.slow),
                          curve: Motion.standard,
                          BarChartData(
                            maxY: maxH,
                            minY: 0,
                            alignment: BarChartAlignment.spaceAround,
                            gridData: FlGridData(
                              drawVerticalLine: false,
                              horizontalInterval: 2,
                              getDrawingHorizontalLine: (_) => _gridLine(t),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border(bottom: BorderSide(color: t.border)),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(),
                              rightTitles: const AxisTitles(),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: _axisW,
                                  interval: 2,
                                  getTitlesWidget: (v, meta) => SideTitleWidget(
                                    meta: meta,
                                    child: Text(
                                      '${v.round()} h',
                                      style: tt.labelSmall!.copyWith(color: t.muted, fontFeatures: tabular),
                                    ),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: _bottomH,
                                  getTitlesWidget: (v, meta) {
                                    final i = v.toInt();
                                    if (!isAxisTick(i, days.length)) return const SizedBox.shrink();
                                    final d = days[i];
                                    final isToday = d == today;
                                    final label = range == TrendRange.week
                                        ? (isToday ? 'Today' : DateFormat('EEE').format(d))
                                        : DateFormat('d MMM').format(d);
                                    return SideTitleWidget(
                                      meta: meta,
                                      fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                                      child: Text(
                                        label,
                                        style: tt.labelSmall!.copyWith(
                                          color: isToday ? t.fg : t.muted,
                                          fontWeight: isToday ? FontWeight.w600 : null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            extraLinesData: ExtraLinesData(
                              extraLinesOnTop: true,
                              horizontalLines: [HorizontalLine(y: goalHours, color: goalColor, strokeWidth: 1.5)],
                            ),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (_) => t.raised,
                                tooltipBorder: BorderSide(color: t.border),
                                tooltipBorderRadius: BorderRadius.circular(12),
                                tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                getTooltipItem: (group, _, rod, _) {
                                  final n = nights[days[group.x]];
                                  if (n == null) return null;
                                  final time = DateFormat.jm();
                                  return BarTooltipItem(
                                    '${DateFormat('EEE d MMM').format(days[group.x])}\n',
                                    tt.labelSmall!.copyWith(color: t.muted),
                                    textAlign: TextAlign.left,
                                    children: [
                                      TextSpan(
                                        text: '${formatSleep(n.asleep)}\n',
                                        style: tt.titleSmall!.copyWith(fontFeatures: tabular),
                                      ),
                                      TextSpan(
                                        text: '${time.format(n.start)} – ${time.format(n.end)}',
                                        style: tt.labelSmall!.copyWith(color: t.muted, fontFeatures: tabular),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            barGroups: [
                              for (final (i, d) in days.indexed)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: nights[d] == null ? 0 : hours(nights[d]!),
                                      width: barW,
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                                      color: barColor,
                                      backDrawRodData: BackgroundBarChartRodData(
                                        show: range != TrendRange.quarter,
                                        toY: maxH,
                                        color: t.fg.withValues(alpha: 0.025),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: S.xl),
          Divider(height: 1, color: t.border),
          const SizedBox(height: S.lg),
          Row(
            children: [
              Expanded(child: _Tile('Nights logged', '${inRange.length}', suffix: '/${days.length}')),
              Expanded(child: _Tile('On goal', '$onGoal', suffix: onGoal == 1 ? ' night' : ' nights')),
              Expanded(child: _Tile('Usual bedtime', usualBed ?? '–')),
            ],
          ),
        ],
      ),
    );
  }
}

/// The gym year at a glance: how many sessions, every training day on a calendar, and the
/// split between push, pull, legs, cardio and sport.
class _GymYearCard extends StatefulWidget {
  const _GymYearCard({required this.sessions});
  final List<GymSession> sessions;

  @override
  State<_GymYearCard> createState() => _GymYearCardState();
}

class _GymYearCardState extends State<_GymYearCard> {
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final y = GymYear(_year, widget.sessions);
    final thisYear = DateTime.now().year;
    final firstYear = widget.sessions.fold<int>(thisYear, (a, s) => math.min(a, s.at.year));
    final maxType = y.byType.values.fold<int>(1, math.max);

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Gym', style: tt.titleLarge)),
              IconButton(
                tooltip: 'Previous year',
                onPressed: _year > firstYear ? () => setState(() => _year--) : null,
                icon: FIcon(Symbols.chevron_left, color: _year > firstYear ? t.fg : t.border),
              ),
              BlurSwitcher(
                child: Text(
                  '$_year',
                  key: ValueKey(_year),
                  style: tt.titleMedium!.copyWith(fontFeatures: tabular),
                ),
              ),
              IconButton(
                tooltip: 'Next year',
                onPressed: _year < thisYear ? () => setState(() => _year++) : null,
                icon: FIcon(Symbols.chevron_right, color: _year < thisYear ? t.fg : t.border),
              ),
            ],
          ),
          const SizedBox(height: S.xs),
          if (y.total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.lg),
              child: Text(
                _year == thisYear
                    ? 'No workouts logged yet this year. Log one from the Gym card on Today.'
                    : 'No workouts logged in $_year.',
                style: tt.bodyMedium!.copyWith(color: t.muted),
              ),
            )
          else ...[
            // The answer first: one number for the year, its unit small beside it.
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                CountUp(
                  value: y.total.toDouble(),
                  format: whole,
                  style: tt.displaySmall!.copyWith(fontSize: 48, height: 1.05, fontFeatures: tabular),
                ),
                const SizedBox(width: 6),
                Text(y.total == 1 ? 'session' : 'sessions', style: tt.titleMedium!.copyWith(color: t.muted)),
              ],
            ),
            const SizedBox(height: S.xs),
            Text(
              [
                if (y.daysTrained != y.total) 'on ${y.daysTrained} days',
                '${y.activeWeeks.length} active ${y.activeWeeks.length == 1 ? 'week' : 'weeks'}',
                'best run ${y.bestWeekStreak} ${y.bestWeekStreak == 1 ? 'week' : 'weeks'}',
              ].join('  ·  '),
              style: tt.bodySmall!.copyWith(fontFeatures: tabular),
            ),
            const SizedBox(height: S.xl),
            _YearGrid(year: _year, byDay: y.byDay, sessions: y.sessions),
            const SizedBox(height: S.xl),
            for (final (i, type) in TrainingType.values.indexed) ...[
              if (i > 0) const SizedBox(height: S.md),
              _TypeRow(type: type, count: y.byType[type] ?? 0, total: y.total, max: maxType),
            ],
          ],
        ],
      ),
    );
  }
}

/// One square per day, a column per week (Monday on top), like a training diary's year page.
/// Empty days are the inset grey; one session fills the square, two or more fill it brighter.
/// Drawn in a single painter (one layer, not 365 widgets), so it scrolls and builds lightly;
/// tapping a training day says what was done.
class _YearGrid extends StatelessWidget {
  const _YearGrid({required this.year, required this.byDay, required this.sessions});
  final int year;
  final Map<DateTime, int> byDay;
  final List<GymSession> sessions;

  static const _cell = 11.0, _gap = 3.0, _labelH = 16.0;
  static const _step = _cell + _gap;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final first = weekStart(DateTime(year, 1, 1));
    final today = startOfDay(DateTime.now());
    final lastDay = year == today.year ? today : DateTime(year, 12, 31);
    final weeks = (lastDay.difference(first).inDays ~/ 7) + 1;
    final width = weeks * _step - _gap;
    final height = _labelH + 7 * _step - _gap;

    // Month labels sit above the week each month starts in.
    final months = <(double, String)>[];
    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final day = addDays(first, w * 7 + d);
        if (day.year == year && day.day == 1) months.add((w * _step, DateFormat('MMM').format(day)));
      }
    }

    void tap(Offset at) {
      final w = (at.dx / _step).floor(), d = ((at.dy - _labelH) / _step).floor();
      if (w < 0 || w >= weeks || d < 0 || d > 6) return;
      final day = addDays(first, w * 7 + d);
      final done = [
        for (final s in sessions)
          if (s.day == day) s.summary,
      ];
      if (done.isEmpty) return;
      showToast(context, '${DateFormat('EEE d MMM').format(day)} · ${done.join(' + ')}');
    }

    final grid = SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          for (final (x, label) in months)
            Positioned(
              left: x,
              top: 0,
              child: Text(label, style: tt.labelSmall),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => tap(d.localPosition),
              child: RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  painter: _YearGridPainter(
                    first: first,
                    weeks: weeks,
                    year: year,
                    lastDay: lastDay,
                    today: today,
                    byDay: byDay,
                    empty: t.inset,
                    one: t.fg.withValues(alpha: 0.72),
                    many: t.fg,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fits on a wide screen. On a phone it scrolls sideways, opens on the latest weeks, and
        // fades only the earlier side that runs off the edge (never the current week).
        LayoutBuilder(
          builder: (context, c) {
            if (width <= c.maxWidth) return grid;
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                colors: [Color(0x00000000), Color(0xFF000000)],
                stops: [0, 0.08],
              ).createShader(rect),
              child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: grid),
            );
          },
        ),
        const SizedBox(height: S.sm),
        Row(
          children: [
            Text('Rest', style: tt.labelSmall),
            const SizedBox(width: 6),
            for (final c in [t.inset, t.fg.withValues(alpha: 0.72), t.fg]) ...[
              Container(
                width: _cell,
                height: _cell,
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2.5)),
              ),
              const SizedBox(width: 3),
            ],
            const SizedBox(width: 3),
            Text('Two sessions', style: tt.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _YearGridPainter extends CustomPainter {
  _YearGridPainter({
    required this.first,
    required this.weeks,
    required this.year,
    required this.lastDay,
    required this.today,
    required this.byDay,
    required this.empty,
    required this.one,
    required this.many,
  });

  final DateTime first, lastDay, today;
  final int weeks, year;
  final Map<DateTime, int> byDay;
  final Color empty, one, many;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = _YearGrid._cell, step = _YearGrid._step, top = _YearGrid._labelH;
    final fill = Paint();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = many;
    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final day = addDays(first, w * 7 + d);
        if (day.year != year || day.isAfter(lastDay)) continue;
        final n = byDay[day] ?? 0;
        fill.color = n == 0 ? empty : (n >= 2 ? many : one);
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * step, top + d * step, cell, cell),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(r, fill);
        if (day == today) canvas.drawRRect(r.deflate(0.6), ring);
      }
    }
  }

  @override
  bool shouldRepaint(_YearGridPainter o) =>
      o.year != year || o.weeks != weeks || o.byDay != byDay || o.empty != empty || o.many != many;
}

/// One training type: name, a slim bar against the most-trained type, the count and its share.
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.count, required this.total, required this.max});
  final TrainingType type;
  final int count;
  final int total;
  final int max;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final pct = total == 0 ? 0 : (count / total * 100).round();
    return Semantics(
      label: type.label,
      value: '$count sessions, $pct percent',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(type.label, style: tt.bodyMedium)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(color: t.inset, borderRadius: BorderRadius.circular(3)),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: max == 0 ? 0 : count / max),
                    duration: Motion.of(context, Motion.slow),
                    curve: Motion.settle,
                    builder: (context, f, _) => Container(
                      width: c.maxWidth * f.clamp(0.0, 1.0),
                      height: 6,
                      decoration: BoxDecoration(
                        color: t.fg.withValues(alpha: t.dark ? 0.86 : 0.78),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: S.md),
          SizedBox(
            width: 36,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: tt.titleSmall!.copyWith(fontFeatures: tabular),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: tt.labelSmall!.copyWith(fontFeatures: tabular),
            ),
          ),
        ],
      ),
    );
  }
}
