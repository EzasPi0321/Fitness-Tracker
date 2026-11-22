import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
import 'snap_meal_screen.dart' show DetectedCard;

/// When a meal said without a time is logged on another day, or before its usual hour.
DateTime mealTime(DateTime day, MealType meal, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (sameDay(day, n) && MealType.suggested(n) == meal) return n;
  final (h, m) = switch (meal) {
    MealType.breakfast => (8, 0),
    MealType.lunch => (12, 30),
    MealType.snack => (15, 30),
    MealType.dinner => (18, 30),
  };
  return DateTime(day.year, day.month, day.day, h, m);
}

Future<void> openVoiceEntry(BuildContext context, {required DateTime day}) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => VoiceEntryScreen(day: startOfDay(day))));
}

enum _Phase { speak, working, review }

/// Say what you ate ("for breakfast I had two eggs on toast, lunch was a chicken salad...")
/// and the AI splits it into meals and items to check before logging. The words appear as
/// you speak and can be edited; typing works too.
class VoiceEntryScreen extends StatefulWidget {
  const VoiceEntryScreen({super.key, required this.day});
  final DateTime day;

  @override
  State<VoiceEntryScreen> createState() => _VoiceEntryScreenState();
}

class _VoiceEntryScreenState extends State<VoiceEntryScreen> {
  final _speech = SpeechToText();
  final _text = TextEditingController();
  _Phase _phase = _Phase.speak;
  bool _speechReady = false;
  bool _listening = false;
  String _before = ''; // what was in the box when listening started
  String? _error;
  SpokenMeals? _result;
  final _include = <int>{};
  double? _usd;

  @override
  void initState() {
    super.initState();
    if (PlatformCaps.isPhone) _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) setState(() => _listening = false);
        },
        onError: (e) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechReady = ok);
    } catch (_) {
      if (mounted) setState(() => _speechReady = false);
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      await _initSpeech();
      if (!_speechReady) {
        setState(
          () => _error =
              'Speech recognition isn’t available. Allow the microphone and speech recognition for FitTrack in '
              'Settings, or type it instead.',
        );
        return;
      }
    }
    _before = _text.text.trim();
    setState(() {
      _listening = true;
      _error = null;
    });
    await _speech.listen(
      onResult: _onWords,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        autoPunctuation: true,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(minutes: 2),
      ),
    );
  }

  void _onWords(SpeechRecognitionResult r) {
    final words = r.recognizedWords;
    _text.text = _before.isEmpty ? words : '$_before $words';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    setState(() {});
  }

  Future<void> _analyze() async {
    if (_listening) {
      await _speech.stop();
      _listening = false;
    }
    final said = _text.text.trim();
    if (said.isEmpty) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    final state = AppScope.read(context);
    final key = await state.keys.read(state.visionProvider.keyName);
    setState(() {
      _phase = _Phase.working;
      _error = null;
    });
    final service = AIVisionService(provider: state.visionProvider, apiKey: key, model: state.visionModel);
    try {
      final result = await service.analyzeSpokenMeals(said, now: DateTime.now());
      if (!mounted) return;
      setState(() {
        _usd = service.calls.isEmpty ? null : AiUsage.ofCalls('voice', service.calls).usd;
        if (result.items.isEmpty) {
          _phase = _Phase.speak;
          _error = 'No foods found in that. Try naming what you ate and roughly how much.';
          return;
        }
        _result = result;
        _include
          ..clear()
          ..addAll(List.generate(result.items.length, (i) => i));
        _phase = _Phase.review;
      });
    } on VisionException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.speak;
          _error = e.message;
        });
      }
    } finally {
      state.recordAiUsage('voice', service.calls);
    }
  }

  Future<void> _log() async {
    final r = _result;
    if (r == null) return;
    final state = AppScope.read(context);
    final now = DateTime.now();
    var waterMl = 0.0;
    final entries = <FoodEntry>[];
    for (final (i, it) in r.items.indexed) {
      if (!_include.contains(i)) continue;
      final f = it.food;
      if (f.isPlainWater) {
        waterMl += f.grams;
        continue;
      }
      entries.add(
        FoodEntry(
          id: newId(),
          name: f.name,
          meal: it.meal,
          source: EntrySource.voice,
          consumedAt: mealTime(widget.day, it.meal, now: now),
          quantity: f.grams,
          unit: 'g',
          grams: f.grams,
          nutrients: f.nutrients,
        ),
      );
    }
    final nav = Navigator.of(context);
    nav.popUntil((route) => route.isFirst);
    final host = nav.context;
    if (entries.isNotEmpty) {
      final logging = logAndCelebrate(host, entries);
      if (waterMl > 0) await state.addWater(waterMl, now);
      await logging;
    } else if (waterMl > 0) {
      showToast(host, 'Added ${Volume.format(waterMl, metric: state.profile?.usesMetric ?? true)} of water');
      await state.addWater(waterMl, now);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice entry')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.slow),
            switchInCurve: Motion.enter,
            child: switch (_phase) {
              _Phase.speak => _speakView(context),
              _Phase.working => const _Working(key: ValueKey('working')),
              _Phase.review => _reviewView(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _speakView(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final canSpeak = PlatformCaps.isPhone;
    final hasText = _text.text.trim().isNotEmpty;
    return ListView(
      key: const ValueKey('speak'),
      padding: const EdgeInsets.all(S.lg),
      children: [
        Text('What did you eat?', style: tt.headlineSmall),
        const SizedBox(height: S.xs),
        Text(
          'Say it the way you’d tell someone: “For breakfast I had two eggs on toast, lunch was a chicken '
          'salad, and dinner was spaghetti bolognese.”',
          style: tt.bodyMedium,
        ),
        const SizedBox(height: S.xl),
        if (canSpeak) ...[
          Center(
            child: _MicButton(listening: _listening, onTap: _toggleListening),
          ),
          const SizedBox(height: S.sm),
          Center(
            child: BlurSwitcher(
              child: Text(
                _listening ? 'Listening… tap to stop' : (hasText ? 'Tap to add more' : 'Tap and speak'),
                key: ValueKey('$_listening$hasText'),
                style: tt.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: S.xl),
        ],
        TextField(
          controller: _text,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: canSpeak ? 'What you said' : 'What you ate',
            hintText: canSpeak ? 'Your words appear here. You can edit them.' : 'For breakfast I had…',
            alignLabelWithHint: true,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: S.md),
          Text(_error!, style: tt.bodyMedium!.copyWith(color: t.over)),
        ],
        const SizedBox(height: S.xl),
        FilledButton(onPressed: hasText ? _analyze : null, child: const Text('Find the foods')),
        const SizedBox(height: S.sm),
        Text(
          'Uses your AI key. Estimates are approximate, and you can edit every item before logging.',
          style: tt.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _reviewView(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final r = _result!;
    final picked = [
      for (final (i, it) in r.items.indexed)
        if (_include.contains(i)) it.food,
    ];
    final total = Nutrients.sum(picked.map((f) => f.nutrients));
    final count = picked.length;
    return Column(
      key: const ValueKey('review'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(S.lg),
            children: [
              Text('${r.items.length} item${r.items.length == 1 ? '' : 's'} found', style: tt.headlineSmall),
              if (r.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(r.notes, style: tt.bodySmall),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Estimated by ${AiModel.nameOf(r.answeredBy)}'
                  '${_usd == null ? '' : ' · this cost ${formatUsd(_usd!)}'}.',
                  style: tt.bodySmall!.copyWith(color: t.muted),
                ),
              ),
              // Grouped by meal, in the day's order. Each item can move to another meal.
              for (final meal in MealType.values)
                if (r.items.any((it) => it.meal == meal)) ...[
                  const SizedBox(height: S.lg),
                  SectionLabel(meal.title),
                  for (final (i, it) in r.items.indexed)
                    if (it.meal == meal) ...[
                      DetectedCard(
                        item: it.food,
                        included: _include.contains(i),
                        onInclude: (v) => setState(() => v ? _include.add(i) : _include.remove(i)),
                        onChanged: () => setState(() {}),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: PopupMenuButton<MealType>(
                          tooltip: 'Move to another meal',
                          onSelected: (m) => setState(() => it.meal = m),
                          itemBuilder: (_) => [
                            for (final m in MealType.values)
                              if (m != it.meal) PopupMenuItem(value: m, child: Text('Move to ${m.title}')),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.sm),
                            child: Text('Move', style: tt.labelMedium!.copyWith(color: t.muted)),
                          ),
                        ),
                      ),
                    ],
                ],
              const SizedBox(height: S.md),
              TextButton(
                onPressed: () => setState(() => _phase = _Phase.speak),
                child: const Text('Change what I said'),
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
                  onPressed: count == 0 ? null : _log,
                  child: Text('Log $count item${count == 1 ? '' : 's'}'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The record button. While listening it breathes slowly, since it is live, and the
/// microphone becomes a stop square.
class _MicButton extends StatefulWidget {
  const _MicButton({required this.listening, required this.onTap});
  final bool listening;
  final VoidCallback onTap;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didUpdateWidget(_MicButton old) {
    super.didUpdateWidget(old);
    if (widget.listening && !Motion.reduced(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    return Squishy(
      onTap: widget.onTap,
      feel: PressFeel.bold,
      haptic: true,
      semanticLabel: widget.listening ? 'Stop listening' : 'Start speaking',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.listening ? t.fg : t.raised,
            border: Border.all(
              color: widget.listening ? t.fg.withValues(alpha: 0.25 + 0.35 * _pulse.value) : t.border,
              width: widget.listening ? 6 : 1,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
          child: child,
        ),
        child: Center(
          child: BlurSwitcher(
            child: FIcon(
              widget.listening ? Symbols.stop : Symbols.mic,
              key: ValueKey(widget.listening),
              size: 40,
              color: widget.listening ? t.bg : t.fg,
              fill: widget.listening,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reading the words: timed steps, so the few seconds show work being done.
class _Working extends StatefulWidget {
  const _Working({super.key});

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working> {
  static const _steps = ['Reading what you said', 'Finding each food', 'Estimating portions'];
  int _step = 0;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _timers.add(Timer(const Duration(milliseconds: 1200), () => mounted ? setState(() => _step = 1) : null));
    _timers.add(Timer(const Duration(milliseconds: 2800), () => mounted ? setState(() => _step = 2) : null));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    return Center(
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, label) in _steps.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
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
                    Text(label, style: tt.bodyMedium!.copyWith(color: i <= _step ? t.fg : t.muted)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
