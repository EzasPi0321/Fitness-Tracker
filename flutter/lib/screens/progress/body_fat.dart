import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/oklch.dart';
import '../../design/tokens.dart';
import '../../models/body_fat.dart';
import '../../models/profile.dart';
import '../../models/util.dart';
import '../../services/ai_vision.dart';
import '../../services/body_report_ocr.dart';
import '../../services/health_service.dart' show WeightSample;
import '../../services/platform_caps.dart';
import '../../widgets/common.dart';
import '../log/snap_meal_screen.dart' show ReadingPhoto, prepareMealPhoto;

/// Readings to draw: everything logged here, plus Health's readings on days with none here.
List<BodyFatEntry> mergeBodyFat(List<BodyFatEntry> logged, List<WeightSample> health) {
  final days = {for (final e in logged) startOfDay(e.at)};
  return [
    ...logged,
    for (final h in health)
      if (!days.contains(startOfDay(h.date)))
        BodyFatEntry(
          id: 'health-${h.date.millisecondsSinceEpoch}',
          at: h.date,
          percent: h.kilograms,
          source: BodyFatSource.health,
        ),
  ]..sort((a, b) => a.at.compareTo(b.at));
}

String _pct(double v) => oneDecimal(v);

/// The latest reading on a scale of the body fat categories, the trend, and lean mass.
class BodyFatCard extends StatelessWidget {
  const BodyFatCard({super.key, required this.readings, required this.metric});
  final List<BodyFatEntry> readings;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final sex = state.profile?.sex ?? BiologicalSex.female;
    final latest = readings.isEmpty ? null : readings.last;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Body fat', style: tt.titleLarge),
              const SizedBox(height: 2),
              Text(
                latest == null ? 'No readings yet' : _describe(latest),
                style: tt.bodyMedium!.copyWith(color: t.muted, fontFeatures: tabular),
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(8, -6),
          child: TextButton.icon(
            onPressed: () => showBodyFatSheet(context),
            icon: const FIcon(Symbols.add, size: 18, weight: FontWeight.w600),
            label: const Text('Log'),
          ),
        ),
      ],
    );

    if (latest == null) {
      return FCard(
        padding: const EdgeInsets.all(S.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: S.lg),
            Text(
              'Read it from an InBody, DEXA or smart-scale screenshot, estimate it from a photo of yourself, '
              'or type in a reading.',
              style: tt.bodyMedium,
            ),
            const SizedBox(height: S.lg),
            _BandScale(percent: null, sex: sex),
          ],
        ),
      );
    }

    final first = readings.first;
    final delta = latest.percent - first.percent;
    final band = BodyFatBand.of(latest.percent, sex);
    final weight = state.weightNear(latest.at);
    final unit = metric ? 'kg' : 'lb';
    double mass(double kg) => metric ? kg : kg * poundsPerKilogram;

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: S.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              CountUp(
                value: latest.percent,
                format: _pct,
                style: tt.displaySmall!.copyWith(fontSize: 40, height: 1.05, fontFeatures: tabular),
              ),
              const SizedBox(width: 4),
              Text('%', style: tt.titleMedium!.copyWith(color: t.muted)),
              if (latest.source.isEstimate) ...[const SizedBox(width: S.sm), Text('estimate', style: tt.bodySmall)],
            ],
          ),
          const SizedBox(height: S.lg),
          _BandScale(percent: latest.percent, low: latest.low, high: latest.high, sex: sex),
          const SizedBox(height: S.sm),
          // Small print under the scale: which range it's in, and the change since the first reading.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: S.md,
            children: [
              Text('${band.label} range for ${sex == BiologicalSex.male ? 'men' : 'women'}', style: tt.bodySmall),
              if (readings.length > 1)
                Text(
                  '${delta > 0
                      ? '+'
                      : delta < 0
                      ? '−'
                      : ''}${_pct(delta.abs())} since '
                  '${DateFormat('d MMM').format(first.at)}',
                  style: tt.bodySmall!.copyWith(fontFeatures: tabular),
                ),
            ],
          ),
          if (readings.length > 1) ...[const SizedBox(height: S.xl), _Trend(readings: readings)],
          if (weight != null) ...[
            const SizedBox(height: S.xl),
            Divider(height: 1, color: t.border),
            const SizedBox(height: S.lg),
            Row(
              children: [
                Expanded(
                  child: _Stat(label: 'Lean mass', value: oneDecimal(mass(latest.leanKg(weight))), unit: unit),
                ),
                Expanded(
                  child: _Stat(label: 'Fat mass', value: oneDecimal(mass(weight - latest.leanKg(weight))), unit: unit),
                ),
                Expanded(
                  child: _Stat(label: 'Readings', value: '${readings.length}', unit: ''),
                ),
              ],
            ),
          ],
          const SizedBox(height: S.lg),
          for (final r in readings.reversed.take(3)) _ReadingRow(reading: r),
        ],
      ),
    );
  }

  static String _describe(BodyFatEntry e) {
    final when = DateFormat('d MMM').format(e.at);
    return switch (e.source) {
      BodyFatSource.report => 'Latest from ${e.device?.isNotEmpty == true ? e.device : 'a report'} · $when',
      BodyFatSource.photo => 'Latest estimated from a photo · $when',
      BodyFatSource.health => 'Latest from Health · $when',
      BodyFatSource.typed => 'Latest reading · $when',
    };
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: tt.titleMedium!.copyWith(fontFeatures: tabular),
              ),
              if (unit.isNotEmpty) TextSpan(text: ' $unit', style: tt.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// One past reading: date, where it came from, the value, and a way to remove it.
class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.reading});
  final BodyFatEntry reading;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final r = reading;
    final from = switch (r.source) {
      BodyFatSource.report => (r.device?.isNotEmpty ?? false) ? r.device! : 'Report',
      BodyFatSource.photo => 'Photo estimate',
      BodyFatSource.health => 'Health',
      BodyFatSource.typed => 'Typed in',
    };
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(DateFormat('d MMM').format(r.at), style: tt.bodyMedium!.copyWith(fontFeatures: tabular)),
          ),
          Expanded(
            child: Text(from, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: S.sm),
          Text(
            r.source.isEstimate && r.low != null ? '${r.low!.round()}–${r.high!.round()}%' : '${_pct(r.percent)}%',
            style: tt.titleSmall!.copyWith(fontFeatures: tabular),
          ),
          if (r.source == BodyFatSource.health)
            const SizedBox(width: 44)
          else
            Transform.translate(
              offset: const Offset(12, 0),
              child: IconButton(
                constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                padding: EdgeInsets.zero,
                tooltip: 'Remove reading',
                onPressed: () {
                  final removed = state.removeBodyFat(r.id);
                  if (removed != null) {
                    showToast(
                      context,
                      'Reading removed',
                      actionLabel: 'Undo',
                      onAction: () => state.restoreBodyFat(removed),
                    );
                  }
                },
                icon: FIcon(Symbols.close, size: 18, color: t.muted, weight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }
}

/// The five body fat categories as one bar, with the reading as a thumb on it. A photo
/// estimate also shows its range, so it reads as "somewhere in here", not an exact value.
class _BandScale extends StatelessWidget {
  const _BandScale({required this.percent, required this.sex, this.low, this.high});
  final double? percent;
  final double? low;
  final double? high;
  final BiologicalSex sex;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final edges = BodyFatBand.edges(sex);
    final band = percent == null ? null : BodyFatBand.of(percent!, sex);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double x(double v) => ((v - edges.first) / (edges.last - edges.first)).clamp(0.0, 1.0) * w;
        return SizedBox(
          height: 40,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: percent ?? edges.first),
            duration: Motion.of(context, Motion.slow),
            curve: Motion.standard,
            builder: (context, v, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 6,
                  height: 16,
                  child: CustomPaint(
                    painter: _BandPainter(
                      edges: edges,
                      active: band?.index,
                      low: low,
                      high: high,
                      track: t.inset,
                      fill: t.bodyO,
                      surface: t.surface,
                      fg: t.fg,
                      value: percent == null ? null : v,
                    ),
                  ),
                ),
                // Boundary numbers under the bar, centred on each joint.
                for (var i = 1; i < edges.length - 1; i++)
                  Positioned(
                    left: x(edges[i]) - 14,
                    width: 28,
                    top: 26,
                    child: Text(
                      whole(edges[i]),
                      textAlign: TextAlign.center,
                      style: tt.labelSmall!.copyWith(color: t.muted, fontFeatures: tabular),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter({
    required this.edges,
    required this.active,
    required this.low,
    required this.high,
    required this.track,
    required this.fill,
    required this.surface,
    required this.fg,
    required this.value,
  });

  final List<double> edges;
  final int? active;
  final double? low;
  final double? high;
  final Color track;
  final Oklch fill;
  final Color surface;
  final Color fg;
  final double? value;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    double x(double v) => ((v - edges.first) / (edges.last - edges.first)).clamp(0.0, 1.0) * w;
    const barH = 6.0, gap = 2.0;
    final cy = size.height / 2;
    for (var i = 0; i < edges.length - 1; i++) {
      final l = x(edges[i]) + (i == 0 ? 0 : gap / 2);
      final r = x(edges[i + 1]) - (i == edges.length - 2 ? 0 : gap / 2);
      final rect = RRect.fromLTRBR(l, cy - barH / 2, r, cy + barH / 2, const Radius.circular(barH / 2));
      canvas.drawRRect(rect, Paint()..color = i == active ? fill.withAlpha(0.55).toColor() : track);
    }
    final lo = low, hi = high;
    if (lo != null && hi != null) {
      final rect = RRect.fromLTRBR(x(lo), 0, x(hi), size.height, Radius.circular(size.height / 2));
      canvas.drawRRect(rect, Paint()..color = fill.withAlpha(0.22).toColor());
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = fill.withAlpha(0.6).toColor(),
      );
    }
    final v = value;
    if (v != null) {
      final c = Offset(x(v), cy);
      canvas.drawCircle(c, 7, Paint()..color = surface);
      canvas.drawCircle(c, 5.5, Paint()..color = fg);
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.value != value || old.active != active || old.low != low || old.high != high || old.track != track;
}

/// Readings over time. Measured readings are solid dots; photo estimates are hollow.
class _Trend extends StatelessWidget {
  const _Trend({required this.readings});
  final List<BodyFatEntry> readings;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final start = startOfDay(readings.first.at);
    final now = DateTime.now();
    double x(DateTime d) => d.difference(start).inMinutes / 1440;
    final vals = readings.map((r) => r.percent).toList();
    final lo = (vals.reduce(math.min) - 1.5).floorToDouble();
    final hi = (vals.reduce(math.max) + 1.5).ceilToDouble();
    final interval = math.max(1.0, ((hi - lo) / 3).ceilToDouble());
    final span = math.max(x(now), 1.0);
    final o = t.bodyO;
    final hasEstimate = readings.any((r) => r.source.isEstimate);
    final hasMeasured = readings.any((r) => !r.source.isEstimate);

    final chart = SizedBox(
      height: 150,
      child: RepaintBoundary(
        child: LineChart(
          duration: Motion.of(context, Motion.slow),
          curve: Motion.standard,
          LineChartData(
            minX: 0,
            maxX: span,
            minY: lo,
            maxY: hi,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (_) => FlLine(color: t.border.withValues(alpha: 0.5), strokeWidth: 0.6),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: math.max(1, span / 3),
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
                      '${v.toStringAsFixed(0)}%',
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
                      '${_pct(s.y)}%\n',
                      tt.titleSmall!.copyWith(fontFeatures: tabular),
                      children: [
                        TextSpan(
                          text:
                              '${DateFormat('EEE, d MMM').format(readings[s.spotIndex].at)}'
                              '${readings[s.spotIndex].source.isEstimate ? ' · estimate' : ''}',
                          style: tt.bodySmall,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (final r in readings) FlSpot(x(r.at), r.percent)],
                isCurved: true,
                curveSmoothness: 0.3,
                preventCurveOverShooting: true,
                barWidth: 2,
                isStrokeCapRound: true,
                color: o.toColor(),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: oklchStops([o.withAlpha(0.14), o.withAlpha(0)], steps: 6),
                  ),
                ),
                dotData: FlDotData(
                  getDotPainter: (spot, _, _, i) => readings[i].source.isEstimate
                      ? FlDotCirclePainter(radius: 3.5, color: t.surface, strokeWidth: 2, strokeColor: o.toColor())
                      : FlDotCirclePainter(radius: 4, color: o.toColor(), strokeWidth: 2, strokeColor: t.surface),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!(hasEstimate && hasMeasured)) return chart;
    Widget key(bool hollow, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hollow ? null : o.toColor(),
            border: hollow ? Border.all(color: o.toColor(), width: 1.5) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: tt.labelSmall!.copyWith(color: t.muted)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: S.lg, children: [key(false, 'Measured'), key(true, 'Photo estimate')]),
        const SizedBox(height: S.md),
        chart,
      ],
    );
  }
}

// ---- Logging ----

Future<void> showBodyFatSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => const _BodyFatSheet(),
  );
}

enum _Step { choose, tips, working, review }

class _BodyFatSheet extends StatefulWidget {
  const _BodyFatSheet();

  @override
  State<_BodyFatSheet> createState() => _BodyFatSheetState();
}

class _BodyFatSheetState extends State<_BodyFatSheet> {
  _Step _step = _Step.choose;
  BodyFatSource _source = BodyFatSource.typed;
  Uint8List? _photo;
  String? _error;
  bool _hasKey = false;

  double? _value;
  DateTime _date = DateTime.now();
  BodyReportReading? _report;
  BodyFatEstimate? _estimate;
  bool _logWeight = true;

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    state.keys.read(state.visionProvider.keyName).then((k) {
      if (mounted) setState(() => _hasKey = k.trim().isNotEmpty);
    });
  }

  void _go(_Step s) => setState(() {
    _step = s;
    _error = null;
  });

  void _fail(String message) => setState(() {
    _step = _source == BodyFatSource.photo ? _Step.tips : _Step.choose;
    _error = message;
  });

  Future<XFile?> _pickFile(ImageSource source) async {
    try {
      return await ImagePicker().pickImage(source: source);
    } catch (_) {
      _fail(source == ImageSource.camera ? 'The camera isn’t available.' : 'Couldn’t open the photo.');
      return null;
    }
  }

  // Report: read on the phone first (free, no key); the AI reads it when that fails or off-phone.
  Future<void> _readReport() async {
    _source = BodyFatSource.report;
    final file = await _pickFile(ImageSource.gallery);
    if (file == null || !mounted) return;
    final jpeg = await prepareMealPhoto(await file.readAsBytes());
    if (!mounted) return;
    if (jpeg == null) return _fail('That file couldn’t be read as an image.');
    setState(() {
      _photo = jpeg;
      _step = _Step.working;
      _error = null;
    });
    final state = AppScope.read(context);
    String? ocrError;
    if (BodyReportOcr.isAvailable) {
      try {
        return _showReport(await BodyReportOcr.read(file.path));
      } on VisionException catch (e) {
        ocrError = e.message;
      } catch (_) {
        ocrError = 'Couldn’t read that image.';
      }
    }
    final key = await state.keys.read(state.visionProvider.keyName);
    if (key.trim().isEmpty) {
      return _fail(
        ocrError ?? 'Reading reports here needs an AI key in Settings. The phone app reads them without one.',
      );
    }
    final service = AIVisionService(provider: state.visionProvider, apiKey: key, model: state.visionModel);
    try {
      _showReport(await service.readBodyReport(jpeg));
    } on VisionException catch (e) {
      if (mounted) _fail(e.message);
    } finally {
      state.recordAiUsage('body', service.calls);
    }
  }

  void _showReport(BodyReportReading r) {
    if (!mounted) return;
    setState(() {
      _report = r;
      _value = (r.percent * 10).round() / 10;
      final d = r.measuredOn;
      _date = d == null ? DateTime.now() : DateTime(d.year, d.month, d.day, 9);
      _logWeight = r.weightKg != null;
      _step = _Step.review;
    });
  }

  Future<void> _estimateFrom(ImageSource source) async {
    final file = await _pickFile(source);
    if (file == null || !mounted) return;
    final jpeg = await prepareMealPhoto(await file.readAsBytes());
    if (!mounted) return;
    if (jpeg == null) return _fail('That file couldn’t be read as a photo.');
    setState(() {
      _photo = jpeg;
      _step = _Step.working;
      _error = null;
    });
    final state = AppScope.read(context);
    final key = await state.keys.read(state.visionProvider.keyName);
    final p = state.profile;
    final about = p == null
        ? 'no details given'
        : '${p.sex.title}, ${p.age} years, ${whole(p.heightCm)} cm, ${oneDecimal(state.weightNear(DateTime.now()) ?? p.weightKg)} kg';
    final service = AIVisionService(provider: state.visionProvider, apiKey: key, model: state.visionModel);
    try {
      final e = await service.estimateBodyFat(jpeg, context: about);
      if (!mounted) return;
      setState(() {
        _estimate = e;
        _value = e.percent.roundToDouble();
        _date = DateTime.now();
        _step = _Step.review;
      });
    } on VisionException catch (e) {
      if (mounted) _fail(e.message);
    } finally {
      state.recordAiUsage('body', service.calls);
    }
  }

  Future<void> _save() async {
    final v = _value;
    if (v == null || v < 2 || v > 70) return;
    final state = AppScope.read(context);
    final est = _source == BodyFatSource.photo ? _estimate : null;
    final entry = BodyFatEntry(
      id: newId(),
      at: _date,
      percent: v,
      source: _source,
      low: est?.low,
      high: est?.high,
      device: _source == BodyFatSource.report ? _report?.device : null,
    );
    final w = _source == BodyFatSource.report && _logWeight ? _report?.weightKg : null;
    Navigator.pop(context);
    // The reading is added before the first await, so the toast's Undo can always find it.
    final saving = state.logBodyFat(entry, weightKg: w);
    showToast(
      context,
      w == null ? 'Body fat logged' : 'Body fat and weight logged',
      actionLabel: 'Undo',
      onAction: () => state.undoBodyFat(entry.id),
    );
    await saving;
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_step) {
      _Step.choose => _choose(context),
      _Step.tips => _tips(context),
      _Step.working => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.xl),
        child: Center(
          child: ReadingPhoto(
            photo: _photo,
            steps: _source == BodyFatSource.report
                ? const ['Reading the report', 'Finding body fat %', 'Checking the date']
                : const ['Reading the photo', 'Comparing with references', 'Narrowing the range'],
          ),
        ),
      ),
      _Step.review => _review(context),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
        child: AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: BlurSwitcher(
            child: KeyedSubtree(key: ValueKey(_step), child: body),
          ),
        ),
      ),
    );
  }

  Widget _error_(BuildContext context) => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: S.md),
          child: Text(_error!, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: FT.of(context).over)),
        );

  Widget _icon(BuildContext context, IconData icon) {
    final t = FT.of(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: t.inset, borderRadius: BorderRadius.circular(S.radiusControl)),
      child: Center(
        child: FIcon(icon, size: 20, color: t.fg, weight: FontWeight.w500),
      ),
    );
  }

  Widget _choose(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final state = AppScope.read(context);
    final canReadReport = BodyReportOcr.isAvailable || _hasKey;
    // An option that can't be used here is dimmed and loses its arrow, with the reason as its subtitle.
    Widget option(IconData icon, String label, String sub, VoidCallback? onTap) => Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: FRow(
        leading: _icon(context, icon),
        label: label,
        sub: sub,
        trailing: onTap == null ? null : const FIcon(Symbols.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Log body fat', style: tt.headlineSmall),
        const SizedBox(height: S.xs),
        Text(
          'Compare readings from the same method: scales, scans and photos each read differently.',
          style: tt.bodyMedium,
        ),
        const SizedBox(height: S.lg),
        FGroup(
          children: [
            option(
              Symbols.description,
              'Read a report',
              canReadReport
                  ? 'Screenshot from InBody, DEXA or a smart-scale app'
                  : 'Needs an AI key in Settings, or the phone app',
              canReadReport ? _readReport : null,
            ),
            option(
              Symbols.accessibility_new,
              'Estimate from a photo',
              _hasKey ? 'A rough guide, give or take a few %' : 'Needs an AI key in Settings',
              _hasKey
                  ? () {
                      _source = BodyFatSource.photo;
                      _go(_Step.tips);
                    }
                  : null,
            ),
            option(Symbols.edit, 'Type it in', 'From a scale, callipers or a clinic', () {
              _source = BodyFatSource.typed;
              final last = state.bodyFatByDate.lastOrNull;
              _value = last == null ? null : (last.percent * 10).round() / 10;
              _date = DateTime.now();
              _go(_Step.review);
            }),
          ],
        ),
        _error_(context),
      ],
    );
  }

  Widget _tips(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final state = AppScope.read(context);
    Widget tip(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FIcon(icon, size: 20, color: t.muted, weight: FontWeight.w500),
          const SizedBox(width: S.md),
          Expanded(child: Text(text, style: tt.bodyMedium)),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Estimate from a photo', style: tt.headlineSmall),
        const SizedBox(height: S.xs),
        Text('A photo gives a range, not an exact number. For the steadiest estimate:', style: tt.bodyMedium),
        const SizedBox(height: S.md),
        tip(Symbols.light_mode, 'Even light from the front, not overhead'),
        tip(Symbols.accessibility_new, 'Stand straight, facing the camera, with your whole torso in frame'),
        tip(Symbols.checkroom, 'Fitted clothes or shirtless, so your waist shows'),
        tip(Symbols.compare, 'Same pose and light each time, so estimates compare fairly'),
        const SizedBox(height: S.md),
        Text(
          'The photo goes to ${state.visionProvider.displayName} for the estimate and isn’t saved in FitTrack.',
          style: tt.bodySmall,
        ),
        const SizedBox(height: S.xl),
        if (PlatformCaps.hasCamera) ...[
          FilledButton.icon(
            onPressed: () => _estimateFrom(ImageSource.camera),
            icon: const FIcon(Symbols.photo_camera, size: 20, weight: FontWeight.w600),
            label: const Text('Take a photo'),
          ),
          const SizedBox(height: S.sm),
          OutlinedButton(onPressed: () => _estimateFrom(ImageSource.gallery), child: const Text('Choose a photo')),
        ] else
          FilledButton.icon(
            onPressed: () => _estimateFrom(ImageSource.gallery),
            icon: const FIcon(Symbols.image, size: 20, weight: FontWeight.w600),
            label: const Text('Choose a photo'),
          ),
        _error_(context),
      ],
    );
  }

  Widget _review(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final state = AppScope.read(context);
    final sex = state.profile?.sex ?? BiologicalSex.female;
    final metric = state.profile?.usesMetric ?? true;
    final est = _source == BodyFatSource.photo ? _estimate : null;
    final report = _source == BodyFatSource.report ? _report : null;
    final v = _value;
    final valid = v != null && v >= 2 && v <= 70;

    String? note;
    if (report != null) {
      final by = report.answeredBy.isEmpty ? 'on your phone' : 'by ${AiModel.nameOf(report.answeredBy)}';
      note = 'Read ${report.device.isNotEmpty ? 'from ${report.device} ' : ''}$by. Check it matches the report.';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          est != null
              ? 'Your estimate'
              : report != null
              ? 'Check the reading'
              : 'Type in a reading',
          style: tt.headlineSmall,
        ),
        if (est != null) ...[
          const SizedBox(height: S.xs),
          Text(
            'Likely ${est.low.round()}–${est.high.round()}%, best guess ${est.percent.round()}%.',
            style: tt.bodyMedium!.copyWith(fontFeatures: tabular),
          ),
          const SizedBox(height: S.lg),
          _BandScale(percent: v ?? est.percent, low: est.low, high: est.high, sex: sex),
          if (est.notes.isNotEmpty) ...[const SizedBox(height: S.sm), Text(est.notes, style: tt.bodySmall)],
        ] else if (note != null) ...[
          const SizedBox(height: S.xs),
          Text(note, style: tt.bodyMedium),
        ],
        const SizedBox(height: S.lg),
        FGroup(
          children: [
            FRow(
              label: 'Body fat',
              trailing: NumberInput(value: v, unit: '%', maxDigits: 1, onChanged: (x) => setState(() => _value = x)),
            ),
            FRow(
              label: 'Date',
              trailing: Text(
                DateFormat('EEE, d MMM').format(_date),
                style: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, 9));
              },
            ),
            if (report?.weightKg != null)
              FRow(
                label: 'Also log weight',
                sub:
                    '${oneDecimal(metric ? report!.weightKg! : report!.weightKg! * poundsPerKilogram)} '
                    '${metric ? 'kg' : 'lb'} from the report',
                trailing: Switch(value: _logWeight, onChanged: (x) => setState(() => _logWeight = x)),
                onTap: () => setState(() => _logWeight = !_logWeight),
              ),
          ],
        ),
        if (v != null && !valid) ...[
          const SizedBox(height: S.sm),
          Text('Enter a value between 2 and 70%.', style: tt.bodySmall!.copyWith(color: t.over)),
        ],
        const SizedBox(height: S.xl),
        FilledButton(onPressed: valid ? _save : null, child: const Text('Save')),
        const SizedBox(height: S.sm),
        TextButton(onPressed: () => _go(_Step.choose), child: const Text('Back')),
      ],
    );
  }
}
