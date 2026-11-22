import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../models/food.dart';
import '../../models/nutrients.dart';
import '../../models/util.dart';
import '../../services/ai_vision.dart';
import '../../widgets/common.dart';
import 'log_flows.dart';

class ManualPrefill {
  const ManualPrefill({this.barcode, this.name, this.brand, this.label});
  final String? barcode;
  final String? name;
  final String? brand;

  /// Values read from a photo of the nutrition label, for the user to check.
  final LabelReading? label;
}

/// Manual entry. Also the fallback for unknown barcodes: "Save to My Foods" caches the barcode
/// so the next scan resolves instantly, offline.
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key, required this.day, this.meal, this.prefill, this.at});
  final DateTime day;
  final MealType? meal;
  final ManualPrefill? prefill;

  /// Exact time to log at (the Food Log's per-hour add); defaults to now / midday.
  final DateTime? at;

  DateTime get logTime => at ?? logTimestamp(day);

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  late final LabelReading? _label = widget.prefill?.label;
  late final _name = TextEditingController(
    text: widget.prefill?.name ?? ((_label?.name.isNotEmpty ?? false) ? _label!.name : ''),
  );
  late final _brand = TextEditingController(
    text: widget.prefill?.brand ?? ((_label?.brand.isNotEmpty ?? false) ? _label!.brand : ''),
  );
  late final _serving = TextEditingController(text: _label?.servingDescription ?? 'serving');
  late double? _servingGrams = _label?.servingGrams;
  double? _servings = 1;
  late double? _cal = _label?.perServing.calories,
      _p = _label?.perServing.protein,
      _c = _label?.perServing.carbs,
      _f = _label?.perServing.fat,
      _fi = _nz(_label?.perServing.fiber),
      _su = _nz(_label?.perServing.sugar);

  /// Optional extras start blank rather than 0 when the source didn't have them.
  static double? _nz(double? v) => (v == null || v <= 0) ? null : v;
  late MealType _meal = widget.meal ?? MealType.suggested(widget.logTime);
  late bool _saveToMyFoods = widget.prefill?.barcode != null;
  CustomFood? _picked;
  int _formKey = 0; // rebuilds the number fields after picking a saved food

  Nutrients get _perServing =>
      Nutrients(calories: _cal ?? 0, protein: _p ?? 0, carbs: _c ?? 0, fat: _f ?? 0, fiber: _fi ?? 0, sugar: _su ?? 0);

  /// Numbers read from the label and checked by the user count as verified; if the photo was
  /// hard to read, or the numbers don't add up, they stay unverified.
  NutritionTrust? get _trust {
    if (_label == null) return _picked?.trust;
    if (!_label.readable) return const NutritionTrust.unverified('The label photo was hard to read');
    if (!NutritionTrust.caloriesMatchMacros(_perServing)) {
      return const NutritionTrust.unverified("Calories don’t match the protein, carbs and fat");
    }
    return const NutritionTrust.verified('Read from the label you photographed and checked');
  }

  bool get _valid => _name.text.trim().isNotEmpty && (_cal ?? -1) >= 0 && (_servings ?? 0) > 0;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _serving.dispose();
    super.dispose();
  }

  Future<void> _chooseSaved() async {
    final food = await Navigator.of(context).push<CustomFood>(MaterialPageRoute(builder: (_) => const MyFoodsScreen()));
    if (food == null) return;
    setState(() {
      _picked = food;
      _name.text = food.name;
      _brand.text = food.brand ?? '';
      _serving.text = food.servingDescription;
      _servingGrams = food.servingGrams;
      _cal = food.perServing.calories;
      _p = food.perServing.protein;
      _c = food.perServing.carbs;
      _f = food.perServing.fat;
      _fi = _nz(food.perServing.fiber);
      _su = _nz(food.perServing.sugar);
      _saveToMyFoods = false;
      _formKey++;
    });
  }

  Future<void> _add() async {
    if (!_valid) return;
    final state = AppScope.read(context);
    final name = _name.text.trim();
    final brand = _brand.text.trim().isEmpty ? null : _brand.text.trim();
    final unit = _serving.text.trim().isEmpty ? 'serving' : _serving.text.trim();
    final servings = _servings!;
    final barcode = widget.prefill?.barcode;
    final entry = FoodEntry(
      id: newId(),
      name: name,
      brand: brand,
      barcode: barcode,
      meal: _meal,
      source: _picked != null ? EntrySource.customFood : (barcode != null ? EntrySource.barcode : EntrySource.manual),
      consumedAt: widget.logTime,
      quantity: servings,
      unit: unit,
      grams: _servingGrams == null ? null : _servingGrams! * servings,
      nutrients: _perServing * servings,
      trust: _trust,
    );
    if (_saveToMyFoods) {
      state.upsertCustomFood(
        barcode: barcode,
        name: name,
        brand: brand,
        serving: unit,
        servingGrams: _servingGrams,
        perServing: _perServing,
        trust: _trust,
      );
    }
    if (_picked != null) state.markCustomFoodUsed(_picked!.id);
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    await logAndCelebrate(nav.context, [entry]);
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    final total = _perServing * (_servings ?? 0);

    Widget field(TextEditingController c, String hint, {bool autofocus = false}) => TextField(
      controller: c,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(hintText: hint),
      onChanged: (_) => setState(() {}),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Manual entry')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, 120),
            children: [
              if (_label != null) ...[
                Container(
                  padding: const EdgeInsets.all(S.md),
                  decoration: BoxDecoration(
                    color: t.inset,
                    borderRadius: BorderRadius.circular(S.radiusControl),
                    border: Border.all(color: t.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FIcon(Symbols.document_scanner, color: t.fg, weight: FontWeight.w500),
                      const SizedBox(width: S.sm),
                      Expanded(
                        child: Text(
                          'Filled in from your label photo${_label.printedUnit != Energy.unit ? ' (converted from ${_label.printedUnit == EnergyUnit.kJ ? 'kJ' : 'kcal'})' : ''}. '
                          'Check each number against the package, then log it.',
                          style: tt.bodyMedium,
                        ),
                      ),
                      if (_trust != null) ...[const SizedBox(width: S.sm), TrustTag(_trust!)],
                    ],
                  ),
                ),
                const SizedBox(height: S.xl),
              ],
              if (widget.prefill?.barcode == null && state.customFoods.isNotEmpty) ...[
                FGroup(
                  children: [
                    FRow(
                      leading: FIcon(Symbols.star, color: t.warn, fill: true, weight: FontWeight.w500),
                      label: 'Choose from My Foods',
                      sub: '${state.customFoods.length} saved',
                      trailing: FIcon(Symbols.chevron_right, color: t.muted),
                      onTap: _chooseSaved,
                    ),
                  ],
                ),
                const SizedBox(height: S.xl),
              ],
              const SectionLabel('Food'),
              field(_name, 'Name (required)', autofocus: widget.prefill?.name == null),
              const SizedBox(height: S.sm),
              field(_brand, 'Brand'),
              if (widget.prefill?.barcode != null) ...[
                const SizedBox(height: S.sm),
                Text('Barcode ${widget.prefill!.barcode}', style: tt.bodySmall!.copyWith(fontFeatures: tabular)),
              ],
              const SizedBox(height: S.xl),
              KeyedSubtree(
                key: ValueKey(_formKey),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FGroup(
                      label: 'Serving',
                      children: [
                        FRow(
                          label: 'Serving',
                          trailing: SizedBox(
                            width: 160,
                            child: TextField(
                              controller: _serving,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(hintText: 'e.g. 1 cup'),
                            ),
                          ),
                        ),
                        FRow(
                          label: 'Serving weight',
                          trailing: NumberInput(
                            value: _servingGrams,
                            unit: 'g',
                            onChanged: (v) => setState(() => _servingGrams = v),
                          ),
                        ),
                        FRow(
                          label: 'Servings eaten',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              NumberInput(
                                value: _servings,
                                maxDigits: 2,
                                width: 80,
                                onChanged: (v) => setState(() => _servings = v),
                              ),
                              const SizedBox(width: S.sm),
                              Stepper2(
                                minusEnabled: (_servings ?? 0) > 0.25,
                                onMinus: () => setState(() => _servings = ((_servings ?? 1) - 0.25).clamp(0.25, 50)),
                                onPlus: () => setState(() => _servings = ((_servings ?? 0) + 0.25).clamp(0.25, 50)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: S.xl),
                    FGroup(
                      label: 'Nutrition per serving',
                      footer: (_servings ?? 1) != 1 && _cal != null
                          ? Text('Total: ${Energy.format(total.calories)} for ${formatAmount(_servings ?? 0)} servings')
                          : const Text('Typing "6,3" or "1 1/2" works too.'),
                      children: [
                        FRow(
                          label: Energy.fieldName,
                          trailing: NumberInput(
                            value: _cal == null ? null : Energy.toDisplay(_cal!).roundToDouble(),
                            unit: Energy.label,
                            maxDigits: 0,
                            onChanged: (v) => setState(() => _cal = v == null ? null : Energy.fromDisplay(v)),
                          ),
                        ),
                        FRow(
                          label: 'Protein',
                          trailing: NumberInput(value: _p, unit: 'g', onChanged: (v) => setState(() => _p = v)),
                        ),
                        FRow(
                          label: 'Carbs',
                          trailing: NumberInput(value: _c, unit: 'g', onChanged: (v) => setState(() => _c = v)),
                        ),
                        FRow(
                          label: 'Fat',
                          trailing: NumberInput(value: _f, unit: 'g', onChanged: (v) => setState(() => _f = v)),
                        ),
                        FRow(
                          label: 'Fibre',
                          sub: 'Optional · for the health score',
                          trailing: NumberInput(
                            value: _fi,
                            unit: 'g',
                            hint: '–',
                            onChanged: (v) => setState(() => _fi = v),
                          ),
                        ),
                        FRow(
                          label: 'Sugars',
                          sub: 'Optional',
                          trailing: NumberInput(
                            value: _su,
                            unit: 'g',
                            hint: '–',
                            onChanged: (v) => setState(() => _su = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                    label: 'Save to My Foods',
                    sub: 'Find it again in one tap',
                    trailing: Switch(value: _saveToMyFoods, onChanged: (v) => setState(() => _saveToMyFoods = v)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.lg),
          child: Align(
            heightFactor: 1, // without this the bar takes the whole screen
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Squishy(
                onTap: _valid ? _add : null,
                feel: PressFeel.bold,
                haptic: true,
                child: IgnorePointer(
                  child: FilledButton(
                    onPressed: _valid ? () {} : null,
                    child: Text(
                      _valid
                          ? 'Log ${Energy.format(total.calories)}'
                          : 'Add a name and ${Energy.fieldName.toLowerCase()}',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyFoodsScreen extends StatefulWidget {
  const MyFoodsScreen({super.key});

  @override
  State<MyFoodsScreen> createState() => _MyFoodsScreenState();
}

class _MyFoodsScreenState extends State<MyFoodsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final q = _query.trim().toLowerCase();
    final foods = state.customFoodsByRecent
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q) || (f.brand?.toLowerCase().contains(q) ?? false))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('My Foods')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.md),
                child: TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Search My Foods',
                    prefixIcon: FIcon(Symbols.search, color: t.muted, weight: FontWeight.w400),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: foods.isEmpty
                    ? Center(
                        child: Text(
                          q.isEmpty ? 'No saved foods yet.' : 'No matches for "$_query".',
                          style: tt.bodyMedium!.copyWith(color: t.muted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
                        itemCount: foods.length,
                        separatorBuilder: (_, _) => const SizedBox(height: S.sm),
                        itemBuilder: (context, i) {
                          final f = foods[i];
                          return Dismissible(
                            key: ValueKey(f.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              decoration: BoxDecoration(color: t.over, borderRadius: BorderRadius.circular(18)),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: S.xl),
                              child: const FIcon(Symbols.delete, color: Colors.white, weight: FontWeight.w600),
                            ),
                            onDismissed: (_) => state.deleteCustomFood(f.id),
                            child: FGroup(
                              children: [
                                FRow(
                                  label: f.name,
                                  sub: '${f.servingDescription} · ${Energy.format(f.perServing.calories)}',
                                  trailing: MacroInline(f.perServing),
                                  onTap: () => Navigator.pop(context, f),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
