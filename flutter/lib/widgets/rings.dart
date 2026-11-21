import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/oklch.dart';
import '../design/tokens.dart';
import '../models/util.dart';

/// The hero of the dashboard: a slim calorie ring on a flat track, filled along a subtle
/// OKLCH gradient. It eases to new values with a slight overshoot, and when food is
/// logged it swells and its tip flares, then settles (exaggerated feedback + follow-through).
class CalorieRing extends StatefulWidget {
  const CalorieRing({
    super.key,
    required this.consumed,
    required this.budget,
    this.pulse,
    this.size = 180,
    this.stroke = 18,
    this.showCenter = true,
  });

  final double consumed;
  final double budget;
  final Listenable? pulse;
  final double size;
  final double stroke;

  /// False when the number is shown beside the ring instead of inside it.
  final bool showCenter;

  @override
  State<CalorieRing> createState() => _CalorieRingState();
}

class _CalorieRingState extends State<CalorieRing> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    widget.pulse?.addListener(_onPulse);
  }

  @override
  void didUpdateWidget(CalorieRing old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse) {
      old.pulse?.removeListener(_onPulse);
      widget.pulse?.addListener(_onPulse);
    }
  }

  void _onPulse() {
    if (!mounted || Motion.reduced(context)) return;
    _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    widget.pulse?.removeListener(_onPulse);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final progress = widget.budget > 0 ? widget.consumed / widget.budget : 0.0;
    final remaining = widget.budget - widget.consumed;

    return Semantics(
      label: 'Calories',
      value:
          '${whole(widget.consumed)} of ${whole(widget.budget)} kilocalories eaten, '
          '${whole(remaining.abs())} ${remaining >= 0 ? 'remaining' : 'over'}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: progress.isFinite ? progress.clamp(0, 2) : 0),
          duration: Motion.of(context, Motion.slow),
          curve: Motion.settle,
          builder: (context, p, _) => AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              // 0 → 1 → 0 swell with a quick attack and a soft release.
              final v = _pulse.value;
              final swell = v < 0.3
                  ? Curves.easeOut.transform(v / 0.3)
                  : 1 - Curves.easeInOut.transform((v - 0.3) / 0.7);
              return CustomPaint(
                painter: _RingPainter(progress: p, stroke: widget.stroke * (1 + 0.1 * swell), flare: swell, t: t),
                child: !widget.showCenter
                    ? null
                    : Center(
                        child: Transform.scale(
                          scale: 1 + 0.05 * swell,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CountUp(
                                value: remaining.abs(),
                                format: (v) => whole(Energy.toDisplay(v)),
                                style: tt.displaySmall!.copyWith(fontFeatures: tabular, fontSize: widget.size * 0.2),
                              ),
                              BlurSwitcher(
                                child: Text(
                                  remaining >= 0 ? '${Energy.label} left' : '${Energy.label} over',
                                  key: ValueKey(remaining >= 0),
                                  style: tt.labelMedium!.copyWith(color: remaining >= 0 ? t.muted : t.over),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.stroke, required this.flare, required this.t});
  final double progress;
  final double stroke;
  final double flare;
  final FT t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.shortestSide - stroke) / 2 - 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    const start = -math.pi / 2;

    // Flat, quiet track: the fill carries the colour.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = t.inset,
    );

    final lap1 = progress.clamp(0.0, 1.0);
    if (lap1 > 0.001) {
      final o = t.caloriesO;
      final sweep = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: const GradientRotation(start),
        colors: oklchStops([o.withL(o.l + 0.04).withC(o.c * 0.85), o, o.withL(o.l - 0.03).withH(o.h - 8)], steps: 24),
      );
      final startColor = o.withL(o.l + 0.04).withC(o.c * 0.85).toColor();
      _arc(canvas, rect, start, lap1 * math.pi * 2, Paint()..shader = sweep.createShader(rect), r, c);
      // The sweep gradient wraps at 12 o'clock, so the rounded start cap would pick up the end
      // colour. Repaint the cap in the start colour.
      canvas.drawCircle(Offset(c.dx, c.dy - r), stroke / 2, Paint()..color = startColor);
    }

    final lap2 = (progress - 1).clamp(0.0, 1.0);
    if (lap2 > 0.001) {
      // Second lap in the warning colour, with a soft shadow so it sits on top of the first.
      canvas.drawArc(
        rect,
        start,
        lap2 * math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      _arc(canvas, rect, start, lap2 * math.pi * 2, Paint()..color = t.over, r, c);
    }
  }

  void _arc(Canvas canvas, Rect rect, double start, double sweep, Paint body, double r, Offset c) {
    body
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, body);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.progress != progress || o.stroke != stroke || o.flare != flare || o.t != t;
}

extension on Oklch {
  Oklch withH(double v) => Oklch(l, c, v % 360, alpha);
}

/// A small capacity gauge for one macro.
class MacroGauge extends StatelessWidget {
  const MacroGauge({super.key, required this.label, required this.consumed, required this.target, required this.color});
  final String label;
  final double consumed;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final over = consumed > target * 1.1;
    final c = over ? t.over : color;
    final frac = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    return Semantics(
      label: label,
      value: '${whole(consumed)} of ${whole(target)} grams',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 64,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: frac),
              duration: Motion.of(context, Motion.slow),
              curve: Motion.settle,
              builder: (context, f, _) => CustomPaint(
                painter: _GaugePainter(f, c, t),
                child: Center(
                  child: Text(whole(consumed), style: tt.titleSmall!.copyWith(fontFeatures: tabular)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: tt.labelLarge!.copyWith(fontSize: 13)),
          Text('${whole(consumed)} / ${whole(target)} g', style: tt.bodySmall!.copyWith(fontFeatures: tabular)),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.frac, this.color, this.t);
  final double frac;
  final Color color;
  final FT t;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final c = size.center(Offset.zero);
    final r = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    // A 270° gauge, open at the bottom like a dial.
    const start = math.pi * 0.75, total = math.pi * 1.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, total, false, base..color = t.inset);
    if (frac > 0.001) {
      canvas.drawArc(rect, start, total * frac, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.frac != frac || o.color != color || o.t != t;
}

/// A tiny ring for the day carousel.
class MiniRing extends StatelessWidget {
  const MiniRing({super.key, required this.progress, this.size = 30});
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MiniPainter(progress, t)),
    );
  }
}

class _MiniPainter extends CustomPainter {
  _MiniPainter(this.p, this.t);
  final double p;
  final FT t;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final c = size.center(Offset.zero);
    final r = (size.shortestSide - stroke) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, paint..color = t.inset);
    if (p > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        math.pi * 2 * p.clamp(0.0, 1.0),
        false,
        paint..color = p > 1.1 ? t.over : t.calories,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniPainter o) => o.p != p || o.t != t;
}
