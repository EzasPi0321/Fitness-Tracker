import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/app_state.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../models/gym.dart';
import '../models/util.dart';
import 'common.dart';

/// Today's training. One tap on a type logs it; the pencil adds duration and a note.
class GymCard extends StatelessWidget {
  const GymCard({super.key, required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final sessions = state.gymOn(day);
    final week = state.gymThisWeek(day);
    final isToday = sameDay(day, DateTime.now());

    void quickLog(TrainingType type) {
      final now = DateTime.now();
      // A past day logs at a plain 6 PM; today logs now.
      final at = isToday ? now : DateTime(day.year, day.month, day.day, 18);
      state.logGym(type, at);
      final added = state.gymOn(day).lastWhere((g) => g.type == type);
      showToast(context, '${type.label} logged', actionLabel: 'Undo', onAction: () => state.removeGym(added.id));
    }

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
                  child: FIcon(Symbols.fitness_center, size: 24, color: t.fg, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: S.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gym', style: tt.titleMedium),
                    BlurSwitcher(
                      child: Align(
                        key: ValueKey(sessions.length),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          sessions.isEmpty
                              ? (isToday ? 'Not trained yet today' : 'Rest day')
                              : sessions.length == 1
                              ? 'Trained today'
                              : '${sessions.length} sessions',
                          style: tt.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$week',
                      style: tt.titleLarge!.copyWith(fontFeatures: tabular),
                    ),
                    TextSpan(text: ' this week', style: tt.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          // The new row eases in, so the cards below slide down instead of jumping.
          AnimatedSize(
            duration: Motion.of(context, Motion.base),
            // Already on screen and resizing: ease-in-out, no overshoot that would clip.
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in sessions) ...[
                  const SizedBox(height: S.sm),
                  Row(
                    children: [
                      FIcon(Symbols.check, size: 18, color: t.fg, weight: FontWeight.w600),
                      const SizedBox(width: S.sm),
                      Expanded(
                        child: Text(s.summary, style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Transform.translate(
                        offset: const Offset(12, 0),
                        child: IconButton(
                          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                          padding: EdgeInsets.zero,
                          tooltip: 'Edit ${s.type.label}',
                          onPressed: () => showGymSheet(context, day: day, session: s),
                          icon: FIcon(Symbols.edit, size: 20, color: t.muted, weight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: S.lg),
          // The five types are the choice; adding details is a quieter, secondary action.
          Row(
            children: [
              Expanded(child: Text(sessions.isEmpty ? 'What did you train?' : 'Add another', style: tt.labelMedium)),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 36),
                  padding: const EdgeInsets.only(left: 12),
                  alignment: Alignment.centerRight,
                  foregroundColor: t.muted,
                  textStyle: tt.labelMedium,
                ),
                onPressed: () => showGymSheet(context, day: day),
                child: const Text('Add details'),
              ),
            ],
          ),
          const SizedBox(height: S.xs),
          // One row of equal buttons: five choices read as one set, and none wraps alone.
          Row(
            children: [
              for (final (i, type) in TrainingType.values.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _TypeButton(type: type, onTap: () => quickLog(type)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.type, required this.onTap, this.selected = false, this.onTapOnly = true});
  final TrainingType type;
  final VoidCallback onTap;

  /// In the sheet, one type is chosen; on the card every button is an action.
  final bool selected;
  final bool onTapOnly;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    return Squishy(
      onTap: onTap,
      semanticLabel: onTapOnly ? 'Log ${type.label}' : type.label,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? t.inset : t.raised,
          borderRadius: BorderRadius.circular(S.radiusControl),
          // Selected: a ring in the text colour, not a white fill, so Save stays the one
          // bright slab on the sheet.
          border: Border.all(color: selected ? t.fg.withValues(alpha: 0.9) : t.border, width: selected ? 1.5 : 1),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            type.label,
            style: tt.labelLarge!.copyWith(color: selected || onTapOnly ? t.fg : t.muted),
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

/// Log or edit a session: what you trained, for how long, and a note.
Future<void> showGymSheet(BuildContext context, {required DateTime day, GymSession? session}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => _GymSheet(day: startOfDay(day), session: session),
  );
}

class _GymSheet extends StatefulWidget {
  const _GymSheet({required this.day, this.session});
  final DateTime day;
  final GymSession? session;

  @override
  State<_GymSheet> createState() => _GymSheetState();
}

class _GymSheetState extends State<_GymSheet> {
  late TrainingType _type = widget.session?.type ?? TrainingType.push;
  late double? _minutes = widget.session?.minutes?.toDouble();
  late final _note = TextEditingController(text: widget.session?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final state = AppScope.read(context);
    final s = widget.session;
    final now = DateTime.now();
    final at =
        s?.at ?? (sameDay(widget.day, now) ? now : DateTime(widget.day.year, widget.day.month, widget.day.day, 18));
    state.logGym(_type, at, minutes: _minutes?.round(), note: _note.text, replaceId: s?.id);
    Navigator.pop(context);
    showToast(context, s == null ? '${_type.label} logged' : 'Workout updated');
  }

  void _delete() {
    final state = AppScope.read(context);
    final removed = state.removeGym(widget.session!.id);
    Navigator.pop(context);
    if (removed != null) {
      showToast(context, 'Workout removed', actionLabel: 'Undo', onAction: () => state.restoreGym(removed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
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
            Text(widget.session == null ? 'Log workout' : 'Edit workout', style: tt.headlineSmall),
            const SizedBox(height: S.xs),
            Text(isToday ? 'Today' : DateFormat('EEEE d MMMM').format(widget.day), style: tt.bodyMedium),
            const SizedBox(height: S.lg),
            Row(
              children: [
                for (final (i, type) in TrainingType.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _TypeButton(
                      type: type,
                      selected: _type == type,
                      onTapOnly: false,
                      onTap: () => setState(() => _type = type),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: S.sm),
            BlurSwitcher(
              child: Align(
                key: ValueKey(_type),
                alignment: Alignment.centerLeft,
                child: Text(_type.detail, style: tt.bodySmall),
              ),
            ),
            const SizedBox(height: S.lg),
            FGroup(
              children: [
                FRow(
                  label: 'Duration',
                  sub: 'Optional',
                  trailing: NumberInput(
                    value: _minutes,
                    unit: 'min',
                    maxDigits: 0,
                    hint: '–',
                    onChanged: (v) => setState(() => _minutes = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.lg, S.xs, S.lg, S.md),
                  child: TextField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Note',
                      hintText: _type == TrainingType.sport
                          ? 'e.g. Basketball'
                          : _type == TrainingType.cardio
                          ? 'e.g. 5 km run'
                          : 'e.g. New bench PR',
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.xl),
            FilledButton(onPressed: _save, child: const Text('Save')),
            if (widget.session != null) ...[
              const SizedBox(height: S.sm),
              TextButton(
                onPressed: _delete,
                child: Text('Remove this workout', style: TextStyle(color: t.over)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
