import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/tokens.dart';
import '../../models/food.dart';
import '../../models/nutrients.dart';
import '../../models/util.dart';
import '../../widgets/common.dart';

Future<void> showEditEntrySheet(BuildContext context, FoodEntry entry) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _EditEntrySheet(entry: entry),
  );
}

class _EditEntrySheet extends StatefulWidget {
  const _EditEntrySheet({required this.entry});
  final FoodEntry entry;

  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
  late double? _qty = widget.entry.quantity;
  late MealType _meal = widget.entry.meal;
  late DateTime _time = widget.entry.consumedAt;
  bool _confirmDelete = false;
  bool _showParts = false;

  /// Logged by weight or volume rather than servings.
  bool get _grams => widget.entry.unit == 'g' || widget.entry.unit == 'ml';
  double get _step => _grams ? 5 : 0.25;

  Nutrients get _preview {
    final e = widget.entry;
    final q = _qty;
    if (q == null || q <= 0 || e.quantity <= 0) return e.nutrients;
    return e.nutrients * (q / e.quantity);
  }

  Future<void> _save() async {
    final q = _qty;
    if (q == null || q <= 0) return;
    final e = widget.entry;
    final previous = e.consumedAt;
    e.rescale(q);
    e.meal = _meal;
    e.consumedAt = _time;
    Navigator.pop(context);
    await AppScope.read(context).updateEntry(e, previousTime: previous);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_time));
    if (picked != null) {
      setState(() => _time = DateTime(_time.year, _time.month, _time.day, picked.hour, picked.minute));
    }
  }

  /// What the dish is made of, folded away until asked for. Follows the portion above.
  Widget _breakdown(BuildContext context, List<FoodComponent> parts) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final e = widget.entry;
    final q = _qty;
    final k = (q == null || q <= 0 || e.quantity <= 0) ? 1.0 : q / e.quantity;
    return FGroup(
      label: 'What’s in it',
      children: [
        FRow(
          label: _showParts ? 'Hide breakdown' : 'Show breakdown',
          sub: '${parts.length} parts, estimated from the photo',
          onTap: () => setState(() => _showParts = !_showParts),
          trailing: AnimatedRotation(
            turns: _showParts ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: FIcon(Symbols.expand_more, size: 22, color: t.muted),
          ),
        ),
        if (_showParts)
          for (final c in parts)
            FRow(
              label: c.name,
              sub:
                  '${whole(c.grams * k)} g · P ${whole(c.nutrients.protein * k)}  '
                  'C ${whole(c.nutrients.carbs * k)}  F ${whole(c.nutrients.fat * k)}',
              trailing: Text(
                Energy.format(c.nutrients.calories * k),
                style: tt.bodyLarge!.copyWith(fontFeatures: tabular),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final e = widget.entry;
    final n = _preview;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(e.name, style: tt.headlineSmall),
            if (e.brand != null) Text(e.brand!, style: tt.bodyMedium!.copyWith(color: t.muted)),
            const SizedBox(height: S.xl),
            FGroup(
              label: 'Portion',
              children: [
                FRow(
                  label: _grams
                      ? (e.unit == 'ml' ? 'Millilitres' : 'Grams')
                      : (e.unit == 'serving' ? 'Servings' : 'Servings · ${e.unit}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NumberInput(value: _qty, maxDigits: 2, width: 90, onChanged: (v) => setState(() => _qty = v)),
                      const SizedBox(width: S.sm),
                      Stepper2(
                        minusEnabled: (_qty ?? 0) > _step,
                        onMinus: () => setState(() => _qty = ((_qty ?? 0) - _step).clamp(_step, 5000)),
                        onPlus: () => setState(() => _qty = ((_qty ?? 0) + _step).clamp(_step, 5000)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.xl),
            FGroup(
              label: 'Nutrition',
              children: [
                FRow(
                  label: Energy.fieldName,
                  trailing: Text(Energy.format(n.calories), style: tt.titleSmall!.copyWith(fontFeatures: tabular)),
                ),
                for (final m in Macro.values)
                  FRow(
                    leading: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: t.macro(m), shape: BoxShape.circle),
                    ),
                    label: m.title,
                    trailing: Text('${oneDecimal(n.of(m))} g', style: tt.bodyLarge!.copyWith(fontFeatures: tabular)),
                  ),
              ],
            ),
            if (e.components case final parts? when parts.isNotEmpty) ...[
              const SizedBox(height: S.xl),
              _breakdown(context, parts),
            ],
            const SizedBox(height: S.xl),
            const SectionLabel('Meal'),
            SegmentedButton<MealType>(
              segments: [for (final m in MealType.values) ButtonSegment(value: m, label: Text(m.title))],
              selected: {_meal},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _meal = s.first),
            ),
            const SizedBox(height: S.md),
            FGroup(
              children: [
                FRow(
                  label: 'Time',
                  onTap: _pickTime,
                  trailing: Text(
                    DateFormat.jm().format(_time),
                    style: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.xl),
            FilledButton(onPressed: (_qty ?? 0) > 0 ? _save : null, child: const Text('Save changes')),
            const SizedBox(height: S.sm),
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.base),
              child: _confirmDelete
                  ? Row(
                      key: const ValueKey('confirm'),
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _confirmDelete = false),
                            child: const Text('Keep'),
                          ),
                        ),
                        const SizedBox(width: S.sm),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: t.over),
                            onPressed: () {
                              Navigator.pop(context);
                              AppScope.read(context).deleteEntry(e);
                            },
                            child: const Text('Delete'),
                          ),
                        ),
                      ],
                    )
                  : TextButton.icon(
                      key: const ValueKey('ask'),
                      style: TextButton.styleFrom(foregroundColor: t.over),
                      onPressed: () => setState(() => _confirmDelete = true),
                      icon: const FIcon(Symbols.delete, size: 18, weight: FontWeight.w600),
                      label: const Text('Delete entry'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
