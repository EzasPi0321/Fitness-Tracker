import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../models/ai_usage.dart';
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

  /// What the user says the estimate got wrong, and the corrections applied so far.
  final _fix = TextEditingController();
  final _corrections = <String>[];
  bool _refining = false;
  String? _fixError;

  @override
  void dispose() {
    _hint.dispose();
    _fix.dispose();
    super.dispose();
  }

  /// Sends the photo, the items as they stand (including any edits) and the correction, and
  /// replaces the estimate with the answer. The cost adds to this photo's.
  Future<void> _refine() async {
    final text = _fix.text.trim();
    final photo = _photo, current = _analysis;
    if (text.isEmpty || photo == null || current == null || _refining) return;
    FocusScope.of(context).unfocus();
    final state = AppScope.read(context);
    final key = await state.keys.read(state.visionProvider.keyName);
    setState(() {
      _refining = true;
      _fixError = null;
    });
    final service = AIVisionService(provider: state.visionProvider, apiKey: key, model: state.visionModel);
    try {
      final result = await service.refineMeal(photo, previous: current, correction: text);
      if (!mounted) return;
      setState(() {
        if (result.items.isEmpty) {
          _fixError = 'That correction left nothing to log. Try wording it differently.';
          return;
        }
        final usd = service.calls.isEmpty ? null : AiUsage.ofCalls('meal', service.calls).usd;
        if (usd != null) _photoUsd = (_photoUsd ?? 0) + usd;
        _analysis = result;
        _include
          ..clear()
          ..addAll(List.generate(result.items.length, (i) => i));
        _corrections.add(text);
        _fix.clear();
      });
    } on VisionException catch (e) {
      if (mounted) setState(() => _fixError = e.message);
    } finally {
      state.recordAiUsage('meal', service.calls);
      if (mounted) setState(() => _refining = false);
    }
  }

  Widget _correctBox(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _fix,
          enabled: !_refining,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _refine(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Correct the estimate',
            hintText: 'e.g. "large bowl", "no dressing"',
            suffixIcon: _refining
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Re-estimate',
                    onPressed: _fix.text.trim().isEmpty ? null : _refine,
                    icon: const FIcon(Symbols.arrow_upward, size: 20, weight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: S.xs),
        Text(
          _refining
              ? 'Re-estimating with your correction…'
              : PlatformCaps.isPhone
              ? 'Type it, or tap the microphone on your keyboard and say it.'
              : 'Say what the photo got wrong, and it re-estimates the meal.',
          style: tt.bodySmall,
        ),
        if (_fixError != null) ...[
          const SizedBox(height: S.xs),
          Text(_fixError!, style: tt.bodySmall!.copyWith(color: t.over)),
        ],
      ],
    );
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      final file = await ImagePicker().pickImage(source: source);
      if (file == null) return;
      final raw = await file.readAsBytes();
      final jpeg = await prepareMealPhoto(raw);
      if (jpeg == null) {
        setState(() => _error = 'That file couldn’t be read as a photo.');
        return;
      }
      setState(() => _photo = jpeg);
    } catch (_) {
      setState(
        () => _error = source == ImageSource.camera ? 'The camera isn’t available.' : 'Couldn’t open the photo.',
      );
    }
  }

  /// What the last estimate cost, when the provider's price is known.
  double? _photoUsd;

  Future<void> _analyze() async {
    final photo = _photo;
    if (photo == null) return;
    final state = AppScope.read(context);
    final key = await state.keys.read(state.visionProvider.keyName);
    setState(() {
      _phase = _Phase.working;
      _error = null;
    });
    final service = AIVisionService(provider: state.visionProvider, apiKey: key, model: state.visionModel);
    try {
      final result = await service.analyzeMeal(photo, hint: _hint.text);
      if (!mounted) return;
      setState(() {
        _photoUsd = service.calls.isEmpty ? null : AiUsage.ofCalls('meal', service.calls).usd;
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
    } finally {
      // Counted even when the answer was unusable: the provider still bills the request.
      state.recordAiUsage('meal', service.calls);
    }
  }

  Future<void> _log() async {
    final a = _analysis;
    if (a == null) return;
    final at = widget.logTime;
    final state = AppScope.read(context);
    final waterMl = [
      for (final (i, item) in a.items.indexed)
        if (_include.contains(i) && item.isPlainWater) item.grams,
    ].fold<double>(0, (x, y) => x + y);
    final entries = [
      for (final (i, item) in a.items.indexed)
        if (_include.contains(i) && !item.isPlainWater)
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
    // Confirmations go up before any await, so they never use a context across a gap.
    final host = nav.context;
    final metric = state.profile?.usesMetric ?? true;
    if (entries.isNotEmpty) {
      final logging = logAndCelebrate(host, entries);
      if (waterMl > 0) await state.addWater(waterMl, at);
      await logging;
    } else if (waterMl > 0) {
      showToast(host, 'Added ${Volume.format(waterMl, metric: metric)} of water');
      await state.addWater(waterMl, at);
    }
  }

  /// "Log 2 items", or "Add 600 ml water" when everything ticked is water.
  String _logLabel(MealAnalysis a) {
    final picked = [
      for (final (i, item) in a.items.indexed)
        if (_include.contains(i)) item,
    ];
    final foods = picked.where((f) => !f.isPlainWater).length;
    if (foods == 0 && picked.isNotEmpty) {
      final ml = picked.fold<double>(0, (x, f) => x + f.grams);
      final metric = AppScope.read(context).profile?.usesMetric ?? true;
      return 'Add ${Volume.format(ml, metric: metric)} water';
    }
    return 'Log $foods item${foods == 1 ? '' : 's'}';
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
          icon: const FIcon(Symbols.scale, size: 20, weight: FontWeight.w600),
          label: Text(
            AiModel.byId(state.visionModel).isSmart
                ? 'Estimate with AI'
                : 'Estimate with ${AiModel.byId(state.visionModel).label}',
          ),
        ),
        const SizedBox(height: S.sm),
        Text(
          'Estimates are approximate. You can edit every item before logging.',
          style: tt.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: S.xs),
        _CostLine(state: state),
      ],
    );
  }

  Widget _workingView(BuildContext context) {
    return Center(
      key: const ValueKey('working'),
      child: ReadingPhoto(photo: _photo),
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
              Text('${a.items.length} item${a.items.length == 1 ? '' : 's'} found', style: tt.headlineSmall),
              if (a.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(a.notes, style: tt.bodySmall),
                ),
              if (a.answeredBy.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    a.escalated
                        ? 'Checked by ${AiModel.nameOf(a.answeredBy)}: the quick model wasn’t sure about this one.'
                        : 'Estimated by ${AiModel.nameOf(a.answeredBy)}'
                              '${_photoUsd == null ? '' : ' · this photo cost ${formatUsd(_photoUsd!)}'}.',
                    style: tt.bodySmall!.copyWith(color: FT.of(context).muted),
                  ),
                ),
              if (_corrections.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Updated for ${_corrections.map((c) => '“$c”').join(', ')}.', style: tt.bodySmall),
                ),
              const SizedBox(height: S.lg),
              for (final (i, item) in a.items.indexed) ...[
                AnimatedOpacity(
                  opacity: _refining ? 0.5 : 1,
                  duration: Motion.of(context, Motion.base),
                  child: _DetectedCard(
                    item: item,
                    included: _include.contains(i),
                    onInclude: (v) => setState(() => v ? _include.add(i) : _include.remove(i)),
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(height: S.sm),
              ],
              const SizedBox(height: S.sm),
              _correctBox(context),
              const SizedBox(height: S.xl),
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
                FilledButton(onPressed: _include.isEmpty || _refining ? null : _log, child: Text(_logLabel(a))),
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
    final water = item.isPlainWater;
    final (label, color) = water
        ? ('Goes to Water', t.bodyO.toColor())
        : c >= 0.75
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
                        unit: water ? 'ml' : 'g',
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
                            ..fat *= f
                            ..fiber *= f
                            ..sugar *= f;
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

/// Waiting for an estimate: a reading line passes down the photo (the photo is what's being
/// read), and the steps underneath tick off on a timer so the wait says what it's doing.
/// Reduced motion keeps the steps and drops the moving line.
/// The photo with a scanner line passing over it and timed steps underneath, so a wait of a
/// few seconds shows the work being done. Shared by meal photos and body fat.
class ReadingPhoto extends StatefulWidget {
  const ReadingPhoto({
    super.key,
    required this.photo,
    this.steps = const ['Reading the photo', 'Finding each food', 'Weighing portions'],
  });
  final Uint8List? photo;

  /// Three steps, shown at 0 s, 1.4 s and 3.2 s.
  final List<String> steps;

  @override
  State<ReadingPhoto> createState() => _ReadingPhotoState();
}

class _ReadingPhotoState extends State<ReadingPhoto> with SingleTickerProviderStateMixin {
  List<String> get _steps => widget.steps;
  static const _at = [Duration.zero, Duration(milliseconds: 1400), Duration(milliseconds: 3200)];

  late final _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  final _timers = <Timer>[];
  int _step = 0;

  @override
  void initState() {
    super.initState();
    for (var i = 1; i < _at.length; i++) {
      _timers.add(Timer(_at[i], () => mounted ? setState(() => _step = i) : null));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _scan.stop();
    } else if (!_scan.isAnimating) {
      _scan.repeat();
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    const w = 240.0, h = 180.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(S.radiusCard),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(widget.photo!, fit: BoxFit.cover),
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _scan,
                      builder: (context, _) {
                        if (!_scan.isAnimating) return const SizedBox.shrink();
                        // Eased so the line slows at the edges, like a scanner head.
                        final y = Curves.easeInOutSine.transform(_scan.value) * (h + 40) - 20;
                        return Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: y - 28,
                              height: 28,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.18)],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: y,
                              height: 1.5,
                              child: ColoredBox(color: t.fg),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: S.xl),
        for (final (i, label) in _steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: SizedBox(
              width: w,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: BlurSwitcher(
                      child: i < _step
                          ? FIcon(
                              Symbols.check,
                              key: const ValueKey('done'),
                              size: 18,
                              color: t.fg,
                              weight: FontWeight.w600,
                            )
                          : i == _step
                          ? Container(
                              key: const ValueKey('now'),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: t.fg, shape: BoxShape.circle),
                            )
                          : const SizedBox(key: ValueKey('later')),
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: Motion.of(context, Motion.base),
                      style: tt.bodyMedium!.copyWith(color: i <= _step ? t.fg : t.muted),
                      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Before sending: what a photo costs and, when a balance was entered, how many are left.
/// Turns amber when the credit is nearly gone, so it never runs out by surprise.
class _CostLine extends StatelessWidget {
  const _CostLine({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final per = state.costPerPhotoUsd;
    if (per == null) return const SizedBox.shrink();
    final left = state.photosLeft;
    final low = left != null && left < 20;
    final text = [
      per < 0.01
          ? 'Less than US\$0.01 a photo'
          : '${state.costPerPhotoIsMeasured ? '' : 'About '}${formatUsd(per)} a photo',
      if (left != null) 'about $left left',
    ].join(' · ');
    if (low) {
      return Center(
        child: StatusPill(text: left == 0 ? 'Credit used up: top up in your Anthropic Console' : text, color: t.warn),
      );
    }
    return Text(
      text,
      style: tt.bodySmall!.copyWith(fontFeatures: tabular),
      textAlign: TextAlign.center,
    );
  }
}
