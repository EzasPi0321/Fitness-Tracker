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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    final s = AppScope.read(context);
    if (!s.healthEnabled || !s.health.isSupported) return;
    final w = await s.health.weightHistory(addDays(DateTime.now(), -TrendRange.quarter.days));
    if (mounted) setState(() => _healthWeights = w);
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

class _CalorieCard extends StatelessWidget {
  const _CalorieCard({required this.days, required this.logged, required this.target, required this.range});
  final List<_Day> days;
  final List<_Day> logged;
  final double target;
  final TrendRange range;

  double _step(double max) {
    for (final s in [250.0, 500.0, 1000.0, 2000.0, 2500.0, 5000.0]) {
      if (max / s <= 5) return s;
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
    final rawMax = math.max(target * 1.25, maxCal * 1.08) * k;
    final step = _step(rawMax);
    final maxY = (rawMax / step).ceil() * step;
    final barW = switch (range) {
      TrendRange.week => 22.0,
      TrendRange.month => 9.0,
      TrendRange.quarter => 3.0,
    };
    final o = t.caloriesO;
    final overO = Oklch(o.l - 0.02, 0.19, 28);

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'Calorie intake',
            logged.isEmpty ? 'No meals logged in this period' : 'Average ${Energy.format(avg)} a day',
          ),
          const SizedBox(height: S.xl),
          SizedBox(
            height: 230,
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
                  getDrawingHorizontalLine: (_) => FlLine(color: t.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: step,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(whole(v), style: tt.bodySmall!.copyWith(fontFeatures: tabular)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        final every = switch (range) {
                          TrendRange.week => 1,
                          TrendRange.month => 7,
                          TrendRange.quarter => 15,
                        };
                        if (i < 0 || i >= days.length || (days.length - 1 - i) % every != 0)
                          return const SizedBox.shrink();
                        final d = days[i].date;
                        final label = range == TrendRange.week
                            ? DateFormat('EEE').format(d)
                            : DateFormat('M/d').format(d);
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(label, style: tt.bodySmall),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: target * k,
                      color: t.muted,
                      strokeWidth: 1.2,
                      dashArray: const [5, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: tt.labelMedium,
                        labelResolver: (_) => 'Goal ${Energy.format(target)}',
                      ),
                    ),
                  ],
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => t.raised,
                    tooltipBorder: BorderSide(color: t.border),
                    tooltipBorderRadius: BorderRadius.circular(12),
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, _, rod, _) {
                      final d = days[group.x];
                      return BarTooltipItem(
                        '${DateFormat('EEE, MMM d').format(d.date)}\n',
                        tt.bodySmall!,
                        textAlign: TextAlign.left,
                        children: [
                          TextSpan(
                            text: '${Energy.format(d.n.calories)}\n',
                            style: tt.titleSmall!.copyWith(fontFeatures: tabular),
                          ),
                          TextSpan(
                            text: 'P ${whole(d.n.protein)}  C ${whole(d.n.carbs)}  F ${whole(d.n.fat)}',
                            style: tt.bodySmall!.copyWith(fontFeatures: tabular),
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
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(range == TrendRange.quarter ? 1.5 : 6),
                          ),
                          gradient: oklchLinearGradient(
                            d.n.calories > target * 1.1
                                ? [overO.withL(overO.l + 0.06), overO]
                                : [o.withL(o.l + 0.07).withC(o.c * 0.85), o],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: S.xl),
          Wrap(
            spacing: S.xl,
            runSpacing: S.md,
            children: [
              _Tile('Days logged', '${logged.length}/${range.days}'),
              _Tile(
                'Within ±10% of goal',
                '$onTarget',
                pill: onTarget > 0 ? StatusPill(text: 'on target', color: t.good) : null,
              ),
              _Tile(
                'Over goal',
                '$over',
                pill: over > 0 ? StatusPill(text: '>110%', color: t.over) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.pill});
  final String label;
  final String value;
  final Widget? pill;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 130),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: tt.titleLarge!.copyWith(fontFeatures: tabular)),
              if (pill != null) ...[const SizedBox(width: S.sm), pill!],
            ],
          ),
        ],
      ),
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
    final tt = Theme.of(context).textTheme;
    final avg = logged.isEmpty ? Nutrients.zero : Nutrients.sum(logged.map((d) => d.n)) * (1 / logged.length);
    final axis = Macro.values.expand((m) => [avg.of(m), targets.of(m)]).fold<double>(1, math.max) * 1.12;

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Average macros', 'Per logged day; the tick marks your target'),
          const SizedBox(height: S.xl),
          for (final m in Macro.values) ...[
            Row(
              children: [
                SizedBox(width: 64, child: Text(m.title, style: tt.bodyMedium)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      return SizedBox(
                        height: 22,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: t.inset, borderRadius: BorderRadius.circular(7)),
                              ),
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(end: (avg.of(m) / axis).clamp(0, 1)),
                              duration: Motion.of(context, Motion.slow),
                              curve: Motion.settle,
                              builder: (context, f, _) => Container(
                                width: w * f,
                                decoration: BoxDecoration(color: t.macro(m), borderRadius: BorderRadius.circular(7)),
                              ),
                            ),
                            Positioned(
                              left: (w * targets.of(m) / axis - 1.5).clamp(0, w - 3),
                              top: -4,
                              bottom: -4,
                              child: Container(
                                width: 3,
                                decoration: BoxDecoration(
                                  color: t.fg.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: S.md),
                SizedBox(
                  width: 92,
                  child: Text(
                    '${whole(avg.of(m))} / ${whole(targets.of(m))} g',
                    textAlign: TextAlign.right,
                    style: tt.bodySmall!.copyWith(fontFeatures: tabular),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.lg),
          ],
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
      final wo = Oklch(t.dark ? 0.74 : 0.58, t.dark ? 0.10 : 0.11, 205);
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
              getDrawingHorizontalLine: (_) => FlLine(color: t.border, strokeWidth: 1),
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
                      DateFormat('MMM d').format(start.add(Duration(minutes: (v * 1440).round()))),
                      style: tt.bodySmall,
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
                    child: Text(v.toStringAsFixed(0), style: tt.bodySmall!.copyWith(fontFeatures: tabular)),
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
                barWidth: 2.6,
                color: wo.toColor(),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: oklchStops([wo.withAlpha(0.28), wo.withAlpha(0)], steps: 6),
                  ),
                ),
                dotData: FlDotData(
                  getDotPainter: (spot, _, _, i) => FlDotCirclePainter(
                    radius: i == spots.length - 1 ? 5 : (spots.length > 30 ? 1.8 : 2.8),
                    color: wo.toColor(),
                    strokeWidth: i == spots.length - 1 ? 2.5 : 0,
                    strokeColor: t.surface,
                  ),
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
