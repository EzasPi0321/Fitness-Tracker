import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/app_state.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/sleep.dart';
import '../models/util.dart';
import 'common.dart';

/// Last night's sleep on Today: hours asleep against the goal, the bed and wake times, and
/// where it came from. A night logged by hand wins over the health store's, so a missed or
/// wrong reading can always be fixed.
class SleepCard extends StatelessWidget {
  const SleepCard({super.key, required this.day, required this.healthNight, required this.canConnect});

  /// The day being shown; its night is the one that ended that morning.
  final DateTime day;
  final SleepNight? healthNight;
  final bool canConnect;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final night = state.loggedNights[startOfDay(day)] ?? healthNight;
    final goal = Duration(minutes: (state.sleepGoalHours * 60).round());
    final frac = night == null ? 0.0 : night.asleep.inMinutes / goal.inMinutes;
    final isToday = sameDay(day, DateTime.now());
    // Neutral, like steps and the calorie bars: green only means calories against the goal.
    final barColor = t.fg.withValues(alpha: t.dark ? 0.86 : 0.78);
    final time = DateFormat.jm();

    return FCard(
      padding: EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, night == null ? S.xl : S.xl - 12),
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
                  child: FIcon(Symbols.bed, size: 24, color: t.fg, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: S.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sleep', style: tt.titleMedium),
                    if (night != null)
                      Semantics(
                        label: 'Sleep',
                        value: '${formatSleep(night.asleep)} of ${formatSleep(goal)}',
                        excludeSemantics: true,
                        child: _Duration(night.asleep, goal: goal),
                      )
                    else
                      Text(isToday ? 'Nothing for last night yet' : 'Nothing for this night', style: tt.bodySmall),
                  ],
                ),
              ),
              if (night != null && frac >= 1) StatusPill(text: 'Goal reached', color: t.fg, icon: Symbols.check),
            ],
          ),
          if (night != null) ...[
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
            const SizedBox(height: S.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${time.format(night.start)} – ${time.format(night.end)}  ·  '
                    '${night.logged ? 'Logged' : state.health.storeName}',
                    style: tt.bodySmall!.copyWith(fontFeatures: tabular),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(12, 0),
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                    padding: EdgeInsets.zero,
                    tooltip: night.logged ? 'Edit sleep' : 'Log a different time',
                    onPressed: () => showSleepSheet(context, day: day, night: night),
                    icon: FIcon(Symbols.edit, size: 20, color: t.muted, weight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: S.lg),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => showSleepSheet(context, day: day),
                  icon: const FIcon(Symbols.add, size: 18, weight: FontWeight.w600),
                  label: const Text('Log sleep'),
                ),
                if (canConnect) ...[
                  const SizedBox(width: S.sm),
                  Flexible(
                    child: TextButton(
                      onPressed: () => state.setHealthEnabled(true),
                      child: Text('Sync from ${state.health.storeName}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "7 h 25 min  of 8 h": numbers in the title size, units small and grey, like a label.
class _Duration extends StatelessWidget {
  const _Duration(this.value, {required this.goal});
  final Duration value;
  final Duration goal;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final big = tt.titleLarge!.copyWith(fontFeatures: tabular);
    final unit = tt.bodySmall!.copyWith(color: t.muted);
    final h = value.inMinutes ~/ 60, m = value.inMinutes % 60;
    return Text.rich(
      TextSpan(
        children: [
          if (h > 0) ...[TextSpan(text: '$h', style: big), TextSpan(text: ' h ', style: unit)],
          if (m > 0 || h == 0) ...[TextSpan(text: '$m', style: big), TextSpan(text: ' min', style: unit)],
          TextSpan(text: '   of ${formatSleep(goal)}', style: unit),
        ],
      ),
    );
  }
}

/// Log or change a night: bedtime and wake-up time, with the hours asleep worked out live.
Future<void> showSleepSheet(BuildContext context, {required DateTime day, SleepNight? night}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => _SleepSheet(day: startOfDay(day), night: night),
  );
}

class _SleepSheet extends StatefulWidget {
  const _SleepSheet({required this.day, this.night});
  final DateTime day;
  final SleepNight? night;

  @override
  State<_SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends State<_SleepSheet> {
  late TimeOfDay _bed;
  late TimeOfDay _wake;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = widget.night;
    if (n != null) {
      _bed = TimeOfDay.fromDateTime(n.start);
      _wake = TimeOfDay.fromDateTime(n.end);
    } else {
      // Start from the last logged night, so a regular schedule is one tap.
      final last = AppScope.read(context).sleep
          .fold<SleepNight?>(null, (a, e) => a == null || e.end.isAfter(a.end) ? SleepNight.fromEntry(e) : a);
      _bed = last == null ? const TimeOfDay(hour: 22, minute: 30) : TimeOfDay.fromDateTime(last.start);
      _wake = last == null ? const TimeOfDay(hour: 6, minute: 30) : TimeOfDay.fromDateTime(last.end);
    }
  }

  /// Bedtimes from noon on belong to the evening before the wake-up day; earlier ones are
  /// after midnight on the wake-up day itself.
  DateTime get _start {
    final d = _bed.hour >= 12 ? addDays(widget.day, -1) : widget.day;
    return DateTime(d.year, d.month, d.day, _bed.hour, _bed.minute);
  }

  DateTime get _end => DateTime(widget.day.year, widget.day.month, widget.day.day, _wake.hour, _wake.minute);

  Future<void> _pick(bool bed) async {
    final picked = await showTimePicker(context: context, initialTime: bed ? _bed : _wake);
    if (picked == null) return;
    setState(() {
      if (bed) {
        _bed = picked;
      } else {
        _wake = picked;
      }
      _error = null;
    });
  }

  void _save() {
    final state = AppScope.read(context);
    final error = state.logSleep(_start, _end, replaceId: widget.night?.entryId);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context);
    showToast(context, 'Sleep logged: ${formatSleep(_end.difference(_start))}');
  }

  void _delete() {
    final state = AppScope.read(context);
    final removed = state.removeSleep(widget.night!.entryId!);
    Navigator.pop(context);
    if (removed != null) {
      showToast(context, 'Sleep removed', actionLabel: 'Undo', onAction: () => state.restoreSleep(removed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final span = _end.difference(_start);
    final valid = span > Duration.zero;
    final isToday = sameDay(widget.day, DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isToday ? 'Last night' : 'Night before ${DateFormat('EEE d MMM').format(widget.day)}',
            style: tt.headlineSmall,
          ),
          const SizedBox(height: S.xs),
          BlurSwitcher(
            child: Align(
              key: ValueKey(valid ? span.inMinutes : -1),
              alignment: Alignment.centerLeft,
              child: Text(
                valid ? '${formatSleep(span)} asleep' : 'Wake-up must be after bedtime',
                style: tt.bodyMedium!.copyWith(color: valid ? t.muted : t.over, fontFeatures: tabular),
              ),
            ),
          ),
          const SizedBox(height: S.lg),
          FGroup(
            children: [
              FRow(
                leading: FIcon(Symbols.bedtime, size: 20, color: t.muted),
                label: 'Went to sleep',
                trailing: Text(_bed.format(context), style: tt.titleMedium!.copyWith(fontFeatures: tabular)),
                onTap: () => _pick(true),
              ),
              FRow(
                leading: FIcon(Symbols.wb_twilight, size: 20, color: t.muted),
                label: 'Woke up',
                trailing: Text(_wake.format(context), style: tt.titleMedium!.copyWith(fontFeatures: tabular)),
                onTap: () => _pick(false),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: S.md),
            StatusPill(text: _error!, color: t.over, icon: Symbols.info),
          ],
          const SizedBox(height: S.xl),
          FilledButton(onPressed: valid ? _save : null, child: const Text('Save')),
          if (widget.night?.logged ?? false) ...[
            const SizedBox(height: S.sm),
            TextButton(
              onPressed: _delete,
              child: Text('Remove this night', style: TextStyle(color: t.over)),
            ),
          ],
        ],
      ),
    );
  }
}
