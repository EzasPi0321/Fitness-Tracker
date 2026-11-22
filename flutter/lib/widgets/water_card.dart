import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/app_state.dart';
import '../design/motion.dart';
import '../design/oklch.dart';
import '../design/tokens.dart';
import '../models/util.dart';
import 'common.dart';

/// Water for the day: a glass that fills, two one-tap sizes (Hick: two choices, plus "other"),
/// and undo. Adding water is a small win, so the fill springs past its level and settles.
class WaterCard extends StatelessWidget {
  const WaterCard({super.key, required this.day});
  final DateTime day;

  /// Takes back the latest drink and says what was removed.
  void _undo(BuildContext context, bool metric) {
    final removed = AppScope.read(context).undoWater(day);
    if (removed != null) showToast(context, 'Removed ${Volume.format(removed.ml, metric: metric)} of water');
  }

  /// Adds water, with Undo in the toast: a mistaken tap is fixed where the eye already is.
  void _add(BuildContext context, double ml, bool metric) {
    AppScope.read(context).addWater(ml, logTimestamp(day));
    showToast(
      context,
      'Added ${Volume.format(ml, metric: metric)} of water',
      actionLabel: 'Undo',
      onAction: () {
        if (context.mounted) AppScope.read(context).undoWater(day);
      },
    );
  }

  /// Another amount, and the place to take back an earlier drink once the toast has gone.
  Future<void> _custom(BuildContext context, bool metric, {required bool hasAny}) async {
    double? value;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add water'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NumberInput(
              value: null,
              unit: Volume.unit(metric: metric),
              hint: metric ? '330' : '12',
              maxDigits: 0,
              width: 200,
              onChanged: (v) => value = v,
            ),
            if (hasAny) ...[
              const SizedBox(height: S.md),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(c, false);
                  _undo(context, metric);
                },
                icon: const FIcon(Symbols.undo, size: 20),
                label: const Text('Remove last drink'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && value != null && value! > 0 && context.mounted) {
      _add(context, Volume.fromDisplay(value!, metric: metric), metric);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final metric = state.profile?.usesMetric ?? true;
    final total = state.waterTotalOn(day);
    final goal = state.waterGoal;
    final frac = goal > 0 ? total / goal : 0.0;
    final hasAny = state.waterOn(day).isNotEmpty;
    final water = t.bodyO;

    // Sized to their labels, not stretched: the row stays clear of the add button's corner.
    Widget add(double ml) => Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 96),
        child: Squishy(
          onTap: () {
            HapticFeedback.lightImpact();
            _add(context, ml, metric);
          },
          feel: PressFeel.bold,
          semanticLabel: 'Add ${Volume.format(ml, metric: metric)} of water',
          child: Container(
            height: S.minTarget,
            decoration: BoxDecoration(
              color: t.inset,
              borderRadius: BorderRadius.circular(S.inner(S.radiusCard, S.lg) + 6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: S.lg),
            child: Center(
              widthFactor: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FIcon(Symbols.add, size: 18, color: t.fg, weight: FontWeight.w600),
                    const SizedBox(width: 4),
                    Text(
                      Volume.format(ml, metric: metric),
                      style: tt.labelLarge!.copyWith(fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The glass: a drop falls in, splashes, and the surface sloshes as the level rises.
              _Glass(frac: frac.clamp(0.0, 1.0).toDouble(), water: water),
              const SizedBox(width: S.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Water', style: tt.titleMedium),
                    const SizedBox(height: 2),
                    Semantics(
                      label: 'Water',
                      value: '${Volume.format(total, metric: metric)} of ${Volume.format(goal, metric: metric)}',
                      excludeSemantics: true,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: Volume.format(total, metric: metric),
                              style: tt.titleLarge!.copyWith(fontFeatures: tabular),
                            ),
                            TextSpan(
                              text: '  of ${Volume.format(goal, metric: metric)}',
                              style: tt.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (frac >= 1) StatusPill(text: 'Goal reached', color: water.toColor(), icon: Symbols.check),
            ],
          ),
          const SizedBox(height: S.lg),
          Row(
            children: [
              for (final ml in Volume.quickAdds(metric: metric)) ...[add(ml), const SizedBox(width: S.sm)],
              IconButton.filledTonal(
                constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                padding: EdgeInsets.zero,
                // Same shape as the amounts beside it: one radius family in the row.
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.inner(S.radiusCard, S.lg) + 6)),
                ),
                tooltip: 'Other amount or remove',
                onPressed: () => _custom(context, metric, hasAny: hasAny),
                icon: FIcon(Symbols.edit, size: 20, weight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* Pouring a glass, 750 ms, started each time water is added:
   0 ms     a drop appears above the glass and falls, stretching as it speeds up
   260 ms   it hits the surface: two droplets splash up and out on arcs
   260 ms+  the level rises with a slight overshoot while the surface sloshes and settles
   Undo or a smaller total just lowers the level (340 ms). Reduced motion: no drop, no wave. */
class _Glass extends StatefulWidget {
  const _Glass({required this.frac, required this.water});
  final double frac;
  final Oklch water;

  @override
  State<_Glass> createState() => _GlassState();
}

class _GlassState extends State<_Glass> with SingleTickerProviderStateMixin {
  static const _pourMs = 750, _impact = 0.35;
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _pourMs),
    value: 1,
  );
  late double _from = widget.frac, _to = widget.frac;
  bool _pour = false;

  @override
  void didUpdateWidget(_Glass old) {
    super.didUpdateWidget(old);
    if ((widget.frac - _to).abs() < 1e-6) return;
    final rising = widget.frac > _to;
    _from = _level(_c.value); // start from wherever the surface is right now (interruptible)
    _to = widget.frac;
    if (Motion.reduced(context)) {
      _pour = false;
      _c.value = 1;
      return;
    }
    _pour = rising;
    _c.duration = Duration(milliseconds: rising ? _pourMs : 340);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Level along the run: after the drop lands when pouring, straight away when lowering.
  double _level(double t) {
    final p = _pour
        ? Motion.settle.transform(((t - _impact + 0.02) / (1 - _impact)).clamp(0.0, 1.0))
        : Curves.easeOutCubic.transform(t);
    return _from + (_to - _from) * p;
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = _c.value;
          final pouring = _pour && _c.isAnimating;
          // Falling: accelerates like gravity (ease-in), visible until it meets the surface.
          final fall = pouring && v < _impact ? Curves.easeIn.transform(v / _impact) : null;
          // After impact: splash for the first third, slosh for the rest, both fading out.
          final after = pouring && v >= _impact ? (v - _impact) / (1 - _impact) : null;
          return CustomPaint(
            size: const Size(44, 60),
            painter: _GlassPainter(
              _level(v),
              widget.water,
              t,
              drop: fall,
              splash: after == null ? null : (after / 0.35).clamp(0.0, 1.0),
              wave: after == null ? 0 : math.pow(1 - after, 1.6).toDouble(),
              phase: v * math.pi * 6,
            ),
          );
        },
      ),
    );
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(this.fill, this.water, this.t, {this.drop, this.splash, this.wave = 0, this.phase = 0});
  final double fill;
  final Oklch water;
  final FT t;

  /// 0→1 while a drop falls (null when there's none).
  final double? drop;

  /// 0→1 while two droplets splash up from the impact (null when there's none).
  final double? splash;

  /// Slosh height, 1 at impact easing to 0; [phase] moves the wave along.
  final double wave;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    // A tumbler that narrows towards the base.
    final w = size.width, h = size.height;
    final glass = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w * 0.86, h)
      ..lineTo(w * 0.14, h)
      ..close();
    canvas.drawPath(glass, Paint()..color = t.inset);
    final top = h * (1 - fill.clamp(0.0, 1.0));
    final paint = Paint()..color = water.toColor();
    if (fill > 0.001) {
      canvas.save();
      canvas.clipPath(glass);
      // The surface: flat at rest, a decaying slosh after a drop lands (follow-through).
      final amp = 2.6 * wave;
      final surface = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w; x += 2) {
        final y = top + amp * math.sin(phase + x / w * math.pi * 2.2) * (0.6 + 0.4 * math.cos(x / w * math.pi));
        surface.lineTo(x, y);
      }
      surface
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(surface, paint);
      canvas.restore();
    }
    // The drop: a teardrop that stretches as it falls (squash and stretch).
    final d = drop;
    if (d != null) {
      final cy = -10 + (top + 2) * d;
      final stretch = 1 + 0.45 * d;
      canvas.save();
      canvas.translate(w / 2, cy);
      canvas.scale(1 / math.sqrt(stretch), stretch);
      final tear = Path()
        ..moveTo(0, -5)
        ..quadraticBezierTo(3.6, -0.5, 3.2, 1.6)
        ..arcToPoint(const Offset(-3.2, 1.6), radius: const Radius.circular(3.2))
        ..quadraticBezierTo(-3.6, -0.5, 0, -5)
        ..close();
      canvas.drawPath(tear, paint);
      canvas.restore();
    }
    // The splash: two droplets thrown up and out on arcs, fading as they fall back.
    final sp = splash;
    if (sp != null && sp < 1) {
      final fade = Paint()..color = water.toColor().withValues(alpha: 1 - sp);
      for (final dir in [-1.0, 1.0]) {
        final x = w / 2 + dir * 9 * sp;
        final y = top - 9 * math.sin(math.pi * sp);
        canvas.drawCircle(Offset(x, y), 1.7 * (1 - 0.4 * sp), fade);
      }
    }
    canvas.drawPath(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = t.border,
    );
  }

  @override
  bool shouldRepaint(_GlassPainter o) =>
      o.fill != fill || o.drop != drop || o.splash != splash || o.wave != wave || o.phase != phase || o.t != t;
}
