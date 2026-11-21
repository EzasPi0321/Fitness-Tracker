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

  Future<void> _custom(BuildContext context, bool metric) async {
    double? value;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add water'),
        content: NumberInput(
          value: null,
          unit: Volume.unit(metric: metric),
          hint: metric ? '330' : '12',
          maxDigits: 0,
          width: 200,
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && value != null && context.mounted) {
      await AppScope.read(context).addWater(Volume.fromDisplay(value!, metric: metric), logTimestamp(day));
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

    Widget add(double ml) => Expanded(
      child: Squishy(
        onTap: () {
          HapticFeedback.lightImpact();
          state.addWater(ml, logTimestamp(day));
        },
        feel: PressFeel.bold,
        semanticLabel: 'Add ${Volume.format(ml, metric: metric)} of water',
        child: Container(
          height: S.minTarget,
          decoration: BoxDecoration(
            color: t.inset,
            borderRadius: BorderRadius.circular(S.inner(S.radiusCard, S.lg) + 6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: S.sm),
          child: Center(
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
    );

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The glass: fills from the bottom with a slight overshoot each time water is added.
              TweenAnimationBuilder<double>(
                tween: Tween(end: frac.clamp(0, 1.0)),
                duration: Motion.of(context, Motion.slow),
                curve: Motion.settle,
                builder: (context, f, _) => CustomPaint(size: const Size(44, 60), painter: _GlassPainter(f, water, t)),
              ),
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
                tooltip: 'Other amount',
                onPressed: () => _custom(context, metric),
                icon: FIcon(Symbols.edit, size: 20, weight: FontWeight.w500),
              ),
              IconButton(
                constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                padding: EdgeInsets.zero,
                tooltip: 'Undo last drink',
                onPressed: hasAny
                    ? () {
                        final removed = state.undoWater(day);
                        if (removed != null) {
                          showToast(context, 'Removed ${Volume.format(removed.ml, metric: metric)} of water');
                        }
                      }
                    : null,
                icon: FIcon(Symbols.undo, size: 20, weight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(this.fill, this.water, this.t);
  final double fill;
  final Oklch water;
  final FT t;

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
    if (fill > 0.001) {
      final top = h * (1 - fill.clamp(0.0, 1.0));
      canvas.save();
      canvas.clipPath(glass);
      final rect = Rect.fromLTRB(0, top, w, h);
      canvas.drawRect(rect, Paint()..color = water.toColor());
      canvas.restore();
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
  bool shouldRepaint(_GlassPainter o) => o.fill != fill || o.t != t;
}
