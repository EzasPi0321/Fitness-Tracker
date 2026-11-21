import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/tokens.dart';
import '../../models/food.dart';
import '../../models/nutrients.dart';
import '../../models/util.dart';
import '../../services/ai_vision.dart';
import '../../services/platform_caps.dart';
import '../../widgets/common.dart';
import 'log_flows.dart';

/// Resizes to 1024 px on the long edge and re-encodes as JPEG (~900 KB max), off the UI thread.
Future<Uint8List?> prepareMealPhoto(Uint8List bytes) => compute(_prepare, bytes);

Uint8List? _prepare(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final longEdge = oriented.width > oriented.height ? oriented.width : oriented.height;
  final resized = longEdge > 1024
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 1024 : null,
          height: oriented.height > oriented.width ? 1024 : null,
          interpolation: img.Interpolation.average,
        )
      : oriented;
  var quality = 82;
  var out = img.encodeJpg(resized, quality: quality);
  while (out.length > 900 * 1024 && quality > 40) {
    quality -= 12;
    out = img.encodeJpg(resized, quality: quality);
  }
  return out;
}

enum _Phase { pick, working, review }

class SnapMealScreen extends StatefulWidget {
  const SnapMealScreen({super.key, required this.day, this.at});
  final DateTime day;
  final DateTime? at;

  DateTime get logTime => at ?? logTimestamp(day);

  @override
  State<SnapMealScreen> createState() => _SnapMealScreenState();
}

class _SnapMealScreenState extends State<SnapMealScreen> {
  _Phase _phase = _Phase.pick;
  Uint8List? _photo;
  final _hint = TextEditingController();
  String? _error;
  MealAnalysis? _analysis;
  final _include = <int>{};
  late MealType _meal = MealType.suggested(widget.logTime);

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      final file = await ImagePicker().pickImage(source: source);
      if (file == null) return;
      final raw = await file.readAsBytes();
      final jpeg = await prepareMealPhoto(raw);
      if (jpeg == null) {
        setState(() => _error = 'That file couldn\'t be read as a photo.');
        return;
      }
      setState(() => _photo = jpeg);
    } catch (_) {
      setState(
        () => _error = source == ImageSource.camera ? 'The camera isn\'t available.' : 'Couldn\'t open the photo.',
      );
    }
  }

  Future<void> _analyze() async {
    final photo = _photo;
    if (photo == null) return;
    final state = AppScope.read(context);
    final key = await state.keys.read(state.visionProvider.keyName);
    setState(() {
      _phase = _Phase.working;
      _error = null;
    });
    try {
      final service = AIVisionService(provider: state.visionProvider, apiKey: key, model: state.visionModel);
      final result = await service.analyzeMeal(photo, hint: _hint.text);
      if (!mounted) return;
      setState(() {
        _analysis = result;
        _include
          ..clear()
          ..addAll(List.generate(result.items.length, (i) => i));
        _phase = result.items.isEmpty ? _Phase.pick : _Phase.review;
        if (result.items.isEmpty) _error = 'No food was found in that photo. Try another angle or add a hint.';
      });
    } on VisionException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.pick;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _log() async {
    final a = _analysis;
    if (a == null) return;
    final at = widget.logTime;
    final entries = [
      for (final (i, item) in a.items.indexed)
        if (_include.contains(i))
          FoodEntry(
            id: newId(),
            name: item.name,
            meal: _meal,
            source: EntrySource.photoAI,
            consumedAt: at,
            quantity: item.grams,
            unit: 'g',
            grams: item.grams,
            nutrients: item.nutrients,
          ),
    ];
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    await logAndCelebrate(nav.context, entries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(PlatformCaps.hasCamera ? 'Snap meal' : 'Photo estimate')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.slow),
            switchInCurve: Motion.enter,
            child: switch (_phase) {
              _Phase.pick => _pickView(context),
              _Phase.working => _workingView(context),
              _Phase.review => _reviewView(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _pickView(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    return ListView(
      key: const ValueKey('pick'),
      padding: const EdgeInsets.all(S.lg),
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.inset,
              borderRadius: BorderRadius.circular(S.radiusCard),
              border: Border.all(color: t.border),
            ),
            child: _photo == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FIcon(Symbols.photo_camera, size: 40, color: t.muted, weight: FontWeight.w300),
                      const SizedBox(height: S.sm),
                      Text('Photograph the whole plate from above', style: tt.bodyMedium!.copyWith(color: t.muted)),
                    ],
                  )
                : Image.memory(_photo!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: S.lg),
        Row(
          children: [
            if (PlatformCaps.hasCamera) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const FIcon(Symbols.photo_camera, size: 20, weight: FontWeight.w600),
                  label: const Text('Take photo'),
                ),
              ),
              const SizedBox(width: S.sm),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const FIcon(Symbols.photo_library, size: 20, weight: FontWeight.w600),
                label: Text(PlatformCaps.isPhone ? 'From library' : 'Choose file'),
              ),
            ),
          ],
        ),
        const SizedBox(height: S.lg),
        TextField(
          controller: _hint,
          decoration: const InputDecoration(hintText: 'Optional hint, e.g. "cooked in butter, large plate"'),
        ),
        if (_error != null) ...[
          const SizedBox(height: S.md),
          StatusPill(text: _error!, color: t.over, icon: Symbols.info),
        ],
        const SizedBox(height: S.xl),
        FilledButton.icon(
          onPressed: _photo == null ? null : _analyze,
          icon: const FIcon(Symbols.auto_awesome, size: 20, weight: FontWeight.w600),
          label: Text('Estimate with ${AiModel.byId(state.visionModel).label}'),
        ),
        const SizedBox(height: S.sm),
        Text(
          'Estimates are approximate. You can edit every item before logging.',
          style: tt.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _workingView(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('working'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(S.radiusCard),
            child: Image.memory(_photo!, width: 220, height: 165, fit: BoxFit.cover),
          ),
        const SizedBox(height: S.xl),
        const SizedBox(width: 220, child: LinearProgressIndicator()),
        const SizedBox(height: S.md),
        Text('Identifying foods and portions…', style: tt.bodyMedium),
      ],
    );
  }

  Widget _reviewView(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final a = _analysis!;
    final total = Nutrients.sum([
      for (final (i, item) in a.items.indexed)
        if (_include.contains(i)) item.nutrients,
    ]);
    return Column(
      key: const ValueKey('review'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(S.lg),
            children: [
              Text('${a.items.length} items found', style: tt.headlineSmall),
              if (a.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(a.notes, style: tt.bodySmall),
                ),
              const SizedBox(height: S.lg),
              for (final (i, item) in a.items.indexed) ...[
                _DetectedCard(
                  item: item,
                  included: _include.contains(i),
                  onInclude: (v) => setState(() => v ? _include.add(i) : _include.remove(i)),
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: S.sm),
              ],
              const SizedBox(height: S.lg),
              const SectionLabel('Meal'),
              SegmentedButton<MealType>(
                segments: [for (final m in MealType.values) ButtonSegment(value: m, label: Text(m.title))],
                selected: {_meal},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _meal = s.first),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Energy.format(total.calories), style: tt.titleLarge!.copyWith(fontFeatures: tabular)),
                      MacroInline(total),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _include.isEmpty ? null : _log,
                  child: Text('Log ${_include.length} item${_include.length == 1 ? '' : 's'}'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetectedCard extends StatelessWidget {
  const _DetectedCard({required this.item, required this.included, required this.onInclude, required this.onChanged});
  final DetectedFood item;
  final bool included;
  final ValueChanged<bool> onInclude;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final c = item.confidence;
    final (label, color) = c >= 0.75
        ? ('Confident', t.good)
        : c >= 0.45
        ? ('Check portion', t.warn)
        : ('Unsure', t.over);

    return AnimatedOpacity(
      opacity: included ? 1 : 0.5,
      duration: Motion.of(context, Motion.fast),
      child: FCard(
        padding: const EdgeInsets.fromLTRB(S.sm, S.sm, S.lg, S.md),
        radius: S.radiusCard - 4,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: included, onChanged: (v) => onInclude(v ?? false)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: Text(item.name, style: tt.titleMedium)),
                      StatusPill(text: label, color: color),
                    ],
                  ),
                  const SizedBox(height: S.sm),
                  Row(
                    children: [
                      NumberInput(
                        value: item.grams,
                        unit: 'g',
                        width: 100,
                        maxDigits: 0,
                        onChanged: (v) {
                          if (v == null || v <= 0 || item.grams <= 0) return;
                          // Rescale the item linearly with its portion.
                          final f = v / item.grams;
                          item
                            ..grams = v
                            ..calories *= f
                            ..protein *= f
                            ..carbs *= f
                            ..fat *= f;
                          onChanged();
                        },
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(Energy.format(item.calories), style: tt.titleSmall!.copyWith(fontFeatures: tabular)),
                          MacroInline(item.nutrients),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
