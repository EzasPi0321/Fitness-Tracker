import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/app_state.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/util.dart';
import '../services/platform_caps.dart';
import 'common.dart';

/// Daily steps. On Android they come from Samsung Health via Health Connect. On iPhone,
/// where a free-signed app can't read Apple Health, a Shortcuts automation reads them and
/// sends them in each time FitTrack opens, or they're typed in ([manual]).
/// [steps] is null when there's nothing yet; the card then says how to get some.
class StepsCard extends StatelessWidget {
  const StepsCard({super.key, required this.steps, required this.canConnect, required this.day, this.manual = false});
  final int? steps;
  final bool canConnect;
  final DateTime day;

  /// No health store: steps come from the shortcut or are typed in.
  final bool manual;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final goal = state.stepGoal;
    final count = steps;
    // Neutral, like the calorie bars: green only ever means calories against the goal.
    final barColor = t.fg.withValues(alpha: t.dark ? 0.86 : 0.78);
    final frac = count == null || goal <= 0 ? 0.0 : count / goal;
    final at = state.stepsFromShortcutAt;
    final viaShortcut = manual && at != null && sameDay(at, day) && sameDay(day, DateTime.now());

    return FCard(
      padding: EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, manual ? S.xl - 12 : S.xl),
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
                        manual
                            ? 'Bring them in from Apple Health with a shortcut, or type them in'
                            : canConnect
                            ? 'Connect ${state.health.storeName} to count your steps'
                            : 'Steps come from Apple Health or Samsung Health on your phone',
                        style: tt.bodySmall,
                      ),
                  ],
                ),
              ),
              if (frac >= 1) StatusPill(text: 'Goal reached', color: t.fg, icon: Symbols.check),
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
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: barColor),
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
          if (manual) ...[
            SizedBox(height: count != null ? S.sm : S.xs),
            // Where the number came from, how to bring it in, and a way to type it.
            Row(
              children: [
                Expanded(
                  child: count != null
                      ? Text(
                          viaShortcut ? 'From Apple Health · ${DateFormat.jm().format(at)}' : 'Typed in',
                          style: tt.bodySmall!.copyWith(fontFeatures: tabular),
                        )
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44)),
                            onPressed: () => showStepsShortcutGuide(context),
                            child: const Text('Set up the shortcut'),
                          ),
                        ),
                ),
                Transform.translate(
                  offset: const Offset(12, 0),
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                    padding: EdgeInsets.zero,
                    tooltip: 'Type steps',
                    onPressed: () => showStepsSheet(context, day: day, current: count),
                    icon: FIcon(Symbols.edit, size: 20, color: t.muted, weight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Type a day's steps by hand.
Future<void> showStepsSheet(BuildContext context, {required DateTime day, int? current}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => _StepsSheet(day: startOfDay(day), current: current),
  );
}

class _StepsSheet extends StatefulWidget {
  const _StepsSheet({required this.day, this.current});
  final DateTime day;
  final int? current;

  @override
  State<_StepsSheet> createState() => _StepsSheetState();
}

class _StepsSheetState extends State<_StepsSheet> {
  late double? _value = widget.current?.toDouble();

  void _save() {
    final v = _value;
    if (v == null || v < 0) return;
    AppScope.read(context).setLoggedSteps(widget.day, v.round());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isToday = sameDay(widget.day, DateTime.now());
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Steps', style: tt.headlineSmall),
            const SizedBox(height: S.xs),
            Text(isToday ? 'Today' : DateFormat('EEEE d MMMM').format(widget.day), style: tt.bodyMedium),
            const SizedBox(height: S.lg),
            FGroup(
              children: [
                FRow(
                  label: 'Steps',
                  trailing: NumberInput(
                    value: _value,
                    unit: 'steps',
                    maxDigits: 0,
                    width: 150,
                    onChanged: (v) => setState(() => _value = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.xl),
            FilledButton(onPressed: (_value ?? -1) >= 0 ? _save : null, child: const Text('Save')),
            if (PlatformCaps.hideHealth) ...[
              const SizedBox(height: S.sm),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  showStepsShortcutGuide(context);
                },
                child: const Text('Bring them in from Apple Health instead'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How to make the Shortcuts automation that sends Apple Health steps in each time
/// FitTrack opens.
Future<void> showStepsShortcutGuide(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (context) {
      final t = FT.of(context);
      final tt = Theme.of(context).textTheme;
      Widget step(int n, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: S.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$n',
                style: tt.titleMedium!.copyWith(color: t.muted, fontFeatures: tabular),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tt.titleSmall),
                  const SizedBox(height: 2),
                  Text(body, style: tt.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
          children: [
            Text('Steps from Apple Health', style: tt.headlineSmall),
            const SizedBox(height: S.xs),
            Text(
              'Shortcuts can read Apple Health even though this install of FitTrack can’t. Set this up once and '
              'your steps come in every time you open FitTrack.',
              style: tt.bodyMedium,
            ),
            const SizedBox(height: S.xl),
            step(
              1,
              'Make the shortcut',
              'In the Shortcuts app, tap + on the Shortcuts tab and name it “FitTrack steps”.',
            ),
            step(
              2,
              'Find Health Samples',
              'Add Find Health Samples. Set Type to Steps, then add the filter Start Date is Today.',
            ),
            step(3, 'Calculate Statistics', 'Add Calculate Statistics and set it to Sum of Health Samples.'),
            step(
              4,
              'URL',
              'Add URL and type fittrack://steps?count= then insert the Statistics Result variable right after it.',
            ),
            step(5, 'Open URLs', 'Add Open URLs. It opens the URL from step 4. Tap Done.'),
            step(
              6,
              'Run it when FitTrack opens',
              'On the Automation tab, tap + › App › FitTrack › Is Opened › Run Immediately, and pick “FitTrack steps”. '
                  'Turn off Notify When Run to skip the banner.',
            ),
            step(
              7,
              'Allow it once',
              'The first run asks to read your steps and to open FitTrack. Tap Allow. After that it’s automatic.',
            ),
            Text(
              'If FitTrack shows more steps than Health, your iPhone and Apple Watch are both being counted: add '
              'one filter, Source is your Apple Watch (or your iPhone if you have no Watch). Each run replaces '
              'today’s count, and you can still type steps in with the pencil on the Steps card.',
              style: tt.bodySmall,
            ),
          ],
        ),
      );
    },
  );
}
