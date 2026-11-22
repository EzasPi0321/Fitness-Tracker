import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../design/tokens.dart';
import '../../models/food.dart';
import '../../models/nutrients.dart';
import '../../models/util.dart';
import '../../widgets/common.dart';
import 'log_flows.dart';

enum _Unit { servings, grams }

Future<void> showProductSheet(BuildContext context, FoodProduct product, {required DateTime day, DateTime? at}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _ProductSheet(product: product, day: day, at: at),
  );
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.product, required this.day, this.at});
  final FoodProduct product;
  final DateTime day;
  final DateTime? at;

  DateTime get logTime => at ?? logTimestamp(day);

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late _Unit _unit = widget.product.perServing != null ? _Unit.servings : _Unit.grams;
  double? _servings = 1;
  late double? _grams = widget.product.servingGrams ?? 100;
  late MealType _meal = MealType.suggested(widget.logTime);

  List<_Unit> get _units => [
    if (widget.product.perServing != null) _Unit.servings,
    if (widget.product.supportsGrams) _Unit.grams,
  ];

  Nutrients? get _nutrients => switch (_unit) {
    _Unit.servings => _servings == null ? null : widget.product.nutrientsForServings(_servings!),
    _Unit.grams => _grams == null ? null : widget.product.nutrientsForGrams(_grams!),
  };

  Future<void> _log() async {
    final n = _nutrients;
    if (n == null) return;
    final p = widget.product;
    final state = AppScope.read(context);
    final servings = _unit == _Unit.servings;
    final entry = FoodEntry(
      id: newId(),
      name: p.name,
      brand: p.brand,
      barcode: p.source == EntrySource.customFood && p.customFoodId == p.barcode ? null : p.barcode,
      meal: _meal,
      source: p.source,
      consumedAt: widget.logTime,
      quantity: servings ? _servings! : _grams!,
      unit: servings ? p.servingLabel : p.amountUnit,
      grams: servings ? (p.servingGrams == null ? null : p.servingGrams! * _servings!) : _grams,
      nutrients: n,
      trust: p.trust,
    );
    if (p.customFoodId != null) state.markCustomFoodUsed(p.customFoodId!);
    final nav = Navigator.of(context);
    nav.pop();
    nav.popUntil((r) => r.isFirst);
    await logAndCelebrate(nav.context, [entry]);
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final p = widget.product;
    final n = _nutrients;
    final step = _unit == _Unit.servings ? 0.25 : 5.0;
    final value = _unit == _Unit.servings ? _servings : _grams;
    void set(double? v) => setState(() => _unit == _Unit.servings ? _servings = v : _grams = v);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (p.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: S.md),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        p.imageUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: tt.headlineSmall),
                      if (p.brand != null) Text(p.brand!, style: tt.bodyMedium!.copyWith(color: t.muted)),
                    ],
                  ),
                ),
              ],
            ),
            if (p.trust != null) ...[
              const SizedBox(height: S.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TrustTag(p.trust!),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(p.trust!.note, style: tt.bodySmall),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: S.xl),
            if (_units.length > 1) ...[
              SegmentedButton<_Unit>(
                segments: [
                  const ButtonSegment(value: _Unit.servings, label: Text('Servings')),
                  ButtonSegment(value: _Unit.grams, label: Text(p.liquid ? 'Millilitres' : 'Grams')),
                ],
                selected: {_unit},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _unit = s.first),
              ),
              const SizedBox(height: S.md),
            ],
            FGroup(
              children: [
                FRow(
                  label: _unit == _Unit.grams
                      ? (p.liquid ? 'Millilitres' : 'Grams')
                      : (p.servingLabel == 'serving' ? 'Servings' : 'Servings · ${p.servingLabel}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NumberInput(value: value, maxDigits: 2, width: 90, onChanged: set),
                      const SizedBox(width: S.sm),
                      Stepper2(
                        minusEnabled: (value ?? 0) > step,
                        onMinus: () => set(((value ?? 0) - step).clamp(step, 5000)),
                        onPlus: () => set(((value ?? 0) + step).clamp(step, 5000)),
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
                  trailing: Text(
                    n == null ? '—' : Energy.format(n.calories),
                    style: tt.titleSmall!.copyWith(fontFeatures: tabular),
                  ),
                ),
                for (final m in Macro.values)
                  FRow(
                    leading: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: t.macro(m), shape: BoxShape.circle),
                    ),
                    label: m.title,
                    trailing: Text(
                      n == null ? '—' : '${oneDecimal(n.of(m))} g',
                      style: tt.bodyLarge!.copyWith(fontFeatures: tabular),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.xl),
            const SectionLabel('Meal'),
            SegmentedButton<MealType>(
              segments: [for (final m in MealType.values) ButtonSegment(value: m, label: Text(m.title))],
              selected: {_meal},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _meal = s.first),
            ),
            const SizedBox(height: S.xl),
            FilledButton(
              onPressed: n == null || (value ?? 0) <= 0 ? null : _log,
              child: Text(n == null ? 'Log' : 'Log ${Energy.format(n.calories)}'),
            ),
            if (p.source == EntrySource.barcode) ...[
              const SizedBox(height: S.md),
              Text('Product data: Open Food Facts (ODbL)', style: tt.bodySmall, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
