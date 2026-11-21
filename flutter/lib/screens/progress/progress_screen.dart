import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/oklch.dart';
import '../../design/tokens.dart';
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
  List<WeightSample> _healthWeights = const [];
  List<SleepNight> _healthSleep = const [];

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
    if (mounted) {
      setState(() {
        _healthWeights = w;
        _healthSleep = sl;
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
    final weights = (state.healthEnabled && _healthWeights.isNotEmpty)
        ? _healthWeights.where((w) => !w.date.isBefore(start)).toList()
        : state.weightsByDate
              .where((w) => !w.date.isBefore(start))
              .map((w) => WeightSample(w.date, w.kilograms))
              .toList();

    final calorie = _CalorieCard(days: days, logged: logged, target: state.targets.calories, range: _range);
    final macros = _MacroCard(logged: logged, targets: state.targets);
    final weight = _WeightCard(points: weights, metric: metric, start: start);
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
                    Rise(delay: const Duration(milliseconds: 120), child: sleepCard),
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
FlLine _gridLine(FT t) => FlLine(color: t.border.withValues(alpha: 0.5), strokeWidth: 0.6);

class _CalorieCard extends StatelessWidget {
  const _CalorieCard({required this.days, required this.logged, required this.target, required this.range});
  final List<_Day> days;
  final List<_Day> logged;
  final double target;
  final TrendRange range;

  static const _chartH = 220.0;
  static const _bottomH = 26.0;
  static const _goalGutter = 54.0;

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
    final onTarget = logged.where((d) => (d.n.calories - target).abs() <= target * 0.1).length;
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
            'Calorie intake',
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
                final plotH = _chartH - _bottomH;
                // Bars take about a third of their slot: slim, but sized to the screen.
                final slot = (c.maxWidth - 36 - _goalGutter) / days.length;
                final barW = (slot * 0.36).clamp(2.0, 24.0);
                final radius = math.min(barW / 2, 4.0);
                final goalY = (plotH * (1 - (target * k / maxY))).clamp(0.0, plotH);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
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
                            // Empty gutter on the right: the goal tag lives there, clear of the bars.
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: _goalGutter,
                                getTitlesWidget: (_, _) => const SizedBox.shrink(),
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
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
                                  final every = switch (range) {
                                    TrendRange.week => 1,
                                    TrendRange.month => 7,
                                    TrendRange.quarter => 15,
                                  };
                                  if (i < 0 || i >= days.length || (days.length - 1 - i) % every != 0) {
                                    return const SizedBox.shrink();
                                  }
                                  final d = days[i].date;
                                  final isToday = d == today;
                                  final label = range == TrendRange.week
                                      ? (isToday ? 'Today' : DateFormat('EEE').format(d))
                                      : DateFormat('d MMM').format(d);
                                  return SideTitleWidget(
                                    meta: meta,
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
                    // Goal tag, in its own gutter so it never sits on a bar.
                    Positioned(
                      right: 0,
                      width: _goalGutter - 6,
                      top: goalY - 11,
                      height: 22,
                      child: IgnorePointer(
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: goalColor, borderRadius: BorderRadius.circular(6)),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Text(
                                whole(target * k),
                                style: tt.labelSmall!.copyWith(
                                  color: t.dark ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: tabular,
                                ),
                              ),
                            ),
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
  const _WeightCard({required this.points, required this.metric, required this.start});
  final List<WeightSample> points;
  final bool metric;
  final DateTime start;

  double _d(double kg) => metric ? kg : kg * poundsPerKilogram;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final unit = metric ? 'kg' : 'lb';
    String sub = 'No weigh-ins in this period';
    if (points.isNotEmpty) {
      final delta = _d(points.last.kilograms) - _d(points.first.kilograms);
      sub = '${oneDecimal(_d(points.last.kilograms))} $unit · ${delta > 0 ? '+' : ''}${oneDecimal(delta)} $unit';
    }
    final now = DateTime.now();
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
      final vals = points.map((p) => _d(p.kilograms)).toList();
      final lo = (vals.reduce(math.min) - 1).floorToDouble();
      final hi = (vals.reduce(math.max) + 1).ceilToDouble();
      final interval = math.max(1.0, ((hi - lo) / 4).ceilToDouble());
      final spots = [for (final p in points) FlSpot(x(p.date), _d(p.kilograms))];
      final wo = t.bodyO;
      body = SizedBox(
        height: 200,
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
                  interval: math.max(1, x(now) / 3),
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      DateFormat('d MMM').format(start.add(Duration(minutes: (v * 1440).round()))),
                      style: tt.labelSmall!.copyWith(color: t.muted),
                    ),
                  ),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
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
                      '${oneDecimal(s.y)} $unit\n',
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
              LineChartBarData(
                spots: spots,
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
      );
    }

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('Body weight', sub),
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
  static const _goalGutter = 54.0;

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
                final plotH = _chartH - _bottomH;
                final goalY = (plotH * (1 - goalHours / maxH)).clamp(0.0, plotH);
                final slot = (c.maxWidth - 36 - _goalGutter) / days.length;
                final barW = (slot * 0.36).clamp(2.0, 24.0);
                final radius = math.min(barW / 2, 4.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
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
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: _goalGutter,
                                getTitlesWidget: (_, _) => const SizedBox.shrink(),
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
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
                                  final every = switch (range) {
                                    TrendRange.week => 1,
                                    TrendRange.month => 7,
                                    TrendRange.quarter => 15,
                                  };
                                  if (i < 0 || i >= days.length || (days.length - 1 - i) % every != 0) {
                                    return const SizedBox.shrink();
                                  }
                                  final d = days[i];
                                  final isToday = d == today;
                                  final label = range == TrendRange.week
                                      ? (isToday ? 'Today' : DateFormat('EEE').format(d))
                                      : DateFormat('d MMM').format(d);
                                  return SideTitleWidget(
                                    meta: meta,
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
                    Positioned(
                      right: 0,
                      width: _goalGutter - 6,
                      top: goalY - 11,
                      height: 22,
                      child: IgnorePointer(
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: goalColor, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            '${goalHours % 1 == 0 ? goalHours.toStringAsFixed(0) : goalHours.toStringAsFixed(1)} h',
                            style: tt.labelSmall!.copyWith(
                              color: t.dark ? Colors.black : Colors.white,
                              fontWeight: FontWeight.w700,
                              fontFeatures: tabular,
                            ),
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
