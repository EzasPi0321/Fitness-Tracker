import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/app_state.dart';
import '../design/motion.dart';
import '../design/oklch.dart';
import '../design/tokens.dart';
import '../models/util.dart';
import 'common.dart';

/// Daily steps from Apple Health (iPhone) or Samsung Health via Health Connect (Android).
/// [steps] is null when there's no source yet; the card then offers to connect one.
class StepsCard extends StatelessWidget {
  const StepsCard({super.key, required this.steps, required this.canConnect});
  final int? steps;
  final bool canConnect;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final goal = state.stepGoal;
    final count = steps;
    const hue = Oklch(0.72, 0.15, 160);
    final frac = count == null || goal <= 0 ? 0.0 : count / goal;

    return FCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.inset,
                  borderRadius: BorderRadius.circular(S.inner(S.radiusCard, S.xl) + 8),
                ),
                child: Center(
                  child: FIcon(Symbols.directions_walk, size: 24, color: t.fg, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: S.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Steps', style: tt.titleMedium),
                    if (count != null)
                      Semantics(
                        label: 'Steps',
                        value: '${whole(count.toDouble())} of ${whole(goal.toDouble())}',
                        excludeSemantics: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            CountUp(
                              value: count.toDouble(),
                              format: whole,
                              style: tt.titleLarge!.copyWith(fontFeatures: tabular),
                            ),
                            Text('  of ${whole(goal.toDouble())}', style: tt.bodySmall),
                          ],
                        ),
                      )
                    else
                      Text(
                        canConnect
                            ? 'Connect ${state.health.storeName} to count your steps'
                            : 'Steps come from Apple Health or Samsung Health on your phone',
                        style: tt.bodySmall,
                      ),
                  ],
                ),
              ),
              if (frac >= 1) StatusPill(text: 'Goal reached', color: hue.toColor(), icon: Symbols.check),
            ],
          ),
          if (count != null) ...[
            const SizedBox(height: S.lg),
            TweenAnimationBuilder<double>(
              tween: Tween(end: frac.clamp(0.0, 1.0)),
              duration: Motion.of(context, Motion.slow),
              curve: Motion.settle,
              builder: (context, f, _) => Container(
                height: 6,
                decoration: BoxDecoration(color: t.inset, borderRadius: BorderRadius.circular(3)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: f.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: hue.toColor(),
                    ),
                  ),
                ),
              ),
            ),
          ] else if (canConnect) ...[
            const SizedBox(height: S.md),
            OutlinedButton.icon(
              onPressed: () => state.setHealthEnabled(true),
              icon: const FIcon(Symbols.favorite, size: 18, weight: FontWeight.w600),
              label: Text('Connect ${state.health.storeName}'),
            ),
          ],
        ],
      ),
    );
  }
}
