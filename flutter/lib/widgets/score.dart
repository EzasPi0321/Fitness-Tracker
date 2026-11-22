import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/app_state.dart';
import '../services/ai_vision.dart' show VisionException;
import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/food.dart';
import '../models/health_score.dart';
import 'common.dart';

extension FoodEntryScore on FoodEntry {
  HealthScore? get healthScore =>
      HealthScore.of(nutrients, grams: grams, detailChecked: detailChecked, fruitVeg: fruitVeg, kind: kind, name: name);
}

/// A meal or a day, weighted by calories.
int? averageScore(Iterable<FoodEntry> entries) =>
    HealthScore.average([for (final e in entries) (e.healthScore, e.nutrients.calories)]);

/// Status colours only: green for good and up, amber for fair, red for poor. The number and
/// the word always travel with the colour, so it never carries the meaning alone.
Color scoreColor(FT t, int score) => switch (ScoreBand.of(score)) {
  ScoreBand.excellent || ScoreBand.good => t.good,
  ScoreBand.fair => t.warn,
  ScoreBand.poor => t.over,
};

/// The score as a small ring filled to it, with the number beside: readable at a glance in a
/// list row, and tappable for the breakdown.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge(this.score, {super.key, this.size = 16, this.onTap, this.label, this.textColor});
  final int score;
  final double size;
  final VoidCallback? onTap;

  /// Shown after the number (e.g. "Good").
  final String? label;

  /// For dark surfaces in light mode, such as the snack bar.
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final badge = Semantics(
      label: 'Health score',
      value: '$score out of 100, ${ScoreBand.of(score).label}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size,
            child: CustomPaint(painter: _ArcPainter(score / 100, scoreColor(t, score), t.inset)),
          ),
          const SizedBox(width: 5),
          Text(
            '$score',
            style: tt.labelMedium!.copyWith(color: textColor ?? t.fg, fontFeatures: tabular),
          ),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(label!, style: tt.labelMedium!.copyWith(color: textColor?.withValues(alpha: 0.75))),
          ],
        ],
      ),
    );
    if (onTap == null) return badge;
    return Squishy(onTap: onTap, feel: PressFeel.subtle, hitSlop: 10, child: badge);
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.frac, this.color, this.track);
  final double frac;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.17;
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = track);
    if (frac > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        math.pi * 2 * frac.clamp(0.0, 1.0),
        false,
        p..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter o) => o.frac != frac || o.color != color || o.track != track;
}

/// Why a food scored what it did: the four parts with their points and the numbers behind them.
Future<void> showScoreSheet(
  BuildContext context, {
  required String name,
  required HealthScore score,
  FoodEntry? entry,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (context) {
      final t = FT.of(context);
      final tt = Theme.of(context).textTheme;
      final color = scoreColor(t, score.score);
      return Padding(
        padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: tt.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: S.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 44,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: score.score / 100),
                    duration: Motion.of(context, Motion.slow),
                    curve: Motion.settle,
                    builder: (context, f, _) => CustomPaint(painter: _ArcPainter(f, color, t.inset)),
                  ),
                ),
                const SizedBox(width: S.md),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${score.score}',
                        style: tt.displaySmall!.copyWith(fontSize: 40, height: 1, fontFeatures: tabular),
                      ),
                      TextSpan(
                        text: ' / 100',
                        style: tt.titleMedium!.copyWith(color: t.muted),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                StatusPill(text: score.band.label, color: color),
              ],
            ),
            const SizedBox(height: S.xl),
            // The two or three things that moved the score most, nothing more.
            for (final (i, f) in score.factors.indexed) ...[if (i > 0) const SizedBox(height: S.sm), _FactorRow(f)],
            const SizedBox(height: S.xl),
            Text(
              'Based on FSANZ’s nutrient profiling (the Australian health-claims standard), per 100 g, '
              'and weighted for your goal.',
              style: tt.bodySmall,
            ),
            if (entry != null && entry.missingDetail) ...[
              const SizedBox(height: S.lg),
              _FillDetailButton(entry: entry),
            ],
          ],
        ),
      );
    },
  );
}

class _FactorRow extends StatelessWidget {
  const _FactorRow(this.factor);
  final ScoreFactor factor;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    // Status colours with an icon, so the meaning never rests on colour alone.
    final color = factor.good ? t.good : t.over;
    return Row(
      children: [
        FIcon(factor.good ? Symbols.check : Symbols.remove, size: 18, color: color, weight: FontWeight.w700),
        const SizedBox(width: S.sm),
        Text(factor.label, style: tt.bodyLarge),
      ],
    );
  }
}

/// "Fill in missing data": asks the AI for the food's weight, fibre and sugar, then reopens
/// the sheet with the complete score.
class _FillDetailButton extends StatefulWidget {
  const _FillDetailButton({required this.entry});
  final FoodEntry entry;

  @override
  State<_FillDetailButton> createState() => _FillDetailButtonState();
}

class _FillDetailButtonState extends State<_FillDetailButton> {
  bool _busy = false;
  String? _error;

  Future<void> _fill() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = AppScope.read(context);
    try {
      await state.fillMissingDetail(widget.entry);
      if (!mounted) return;
      final nav = Navigator.of(context);
      final host = nav.context;
      nav.pop();
      final s = widget.entry.healthScore;
      if (s != null && host.mounted) await showScoreSheet(host, name: widget.entry.name, score: s, entry: widget.entry);
    } on VisionException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This food was saved without some details (weight, fibre, sugar, saturated fat or sodium), so the '
          'score is partly estimated.',
          style: tt.bodySmall,
        ),
        const SizedBox(height: S.sm),
        OutlinedButton(
          onPressed: _busy ? null : _fill,
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Fill in missing data'),
        ),
        if (_error != null) ...[
          const SizedBox(height: S.sm),
          Text(_error!, style: tt.bodySmall!.copyWith(color: t.over)),
        ],
      ],
    );
  }
}
