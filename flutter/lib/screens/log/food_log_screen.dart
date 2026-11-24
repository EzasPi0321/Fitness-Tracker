import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_state.dart';
import '../../data/common_foods.dart';
import '../../design/motion.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../models/food.dart';
import '../../models/nutrients.dart';
import '../../models/util.dart';
import '../../services/open_food_facts.dart';
import '../../services/platform_caps.dart';
import '../../widgets/score.dart';
import '../../widgets/common.dart';
import '../today/edit_entry_sheet.dart';
import '../today/today_screen.dart' show DayCarousel;
import 'log_flows.dart';
import 'product_sheet.dart';

/// The day as an hourly timeline: each hour has its own add button, foods sit at the time they
/// were eaten, and a search bar at the bottom finds anything (My Foods, past meals, Open Food
/// Facts) without opening a menu first.
class FoodLogScreen extends StatefulWidget {
  const FoodLogScreen({super.key});

  @override
  State<FoodLogScreen> createState() => _FoodLogScreenState();
}

class _FoodLogScreenState extends State<FoodLogScreen> {
  DateTime _day = startOfDay(DateTime.now());
  final _nowKey = GlobalKey();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  /// When adding from an hour's +, results log at that hour.
  DateTime? _pendingAt;

  final _scroll = SmoothScrollController();
  ValueNotifier<({DateTime day, DateTime at})?>? _searchRequest;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = AppScope.read(context).foodSearchRequest;
    if (r != _searchRequest) {
      _searchRequest?.removeListener(_onSearchRequest);
      _searchRequest = r..addListener(_onSearchRequest);
    }
  }

  /// Search asked for from a meal on Today: open it on that day, logging at the meal's time.
  /// Focus and clear after the frame, once the shell has switched to this tab.
  void _onSearchRequest() {
    final req = _searchRequest?.value;
    if (req == null) return;
    setState(() {
      _day = req.day;
      _pendingAt = req.at;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      _searchRequest?.value = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  @override
  void dispose() {
    _searchRequest?.removeListener(_onSearchRequest);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Opens on the current hour, not at midnight. The hour list is lazy, so the current hour
  /// may not exist yet: jump to an estimate (every hour is at least ~52 px tall), let it
  /// build, then line it up exactly.
  void _scrollToNow([int attempt = 0]) {
    if (!mounted) return;
    final c = _nowKey.currentContext;
    if (c != null) {
      Scrollable.ensureVisible(c, alignment: 0.25, duration: Duration.zero);
      return;
    }
    if (attempt >= 3 || !_scroll.hasClients) return;
    final p = _scroll.position;
    _scroll.jumpTo((DateTime.now().hour * 52.0).clamp(p.minScrollExtent, p.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow(attempt + 1));
  }

  void _select(DateTime d) {
    setState(() => _day = startOfDay(d));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  DateTime _atHour(int hour) => DateTime(
    _day.year,
    _day.month,
    _day.day,
    hour,
    hour == DateTime.now().hour && sameDay(_day, DateTime.now()) ? DateTime.now().minute : 0,
  );

  Future<void> _addAtHour(int hour) async {
    final at = _atHour(hour);
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (c) => _AddAtSheet(at: at),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'search':
        setState(() => _pendingAt = at);
        _searchFocus.requestFocus();
      case 'barcode':
        PlatformCaps.hasCamera
            ? await openBarcodeScanner(context, day: _day, at: at)
            : await openBarcodeEntry(context, day: _day, at: at);
      case 'photo':
        await openSnapMeal(context, day: _day, at: at);
      case 'manual':
        await openManualEntry(context, day: _day, at: at);
    }
  }

  void _closeSearch() {
    _search.clear();
    _searchFocus.unfocus();
    setState(() => _pendingAt = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 840 ? S.xxl : S.lg;
    final entries = state.entriesOn(_day);
    final consumed = Nutrients.sum(entries.map((e) => e.nutrients));
    final isToday = sameDay(_day, DateTime.now());
    final nowHour = DateTime.now().hour;

    final byHour = <int, List<FoodEntry>>{};
    for (final e in entries) {
      byHour.putIfAbsent(e.consumedAt.hour, () => []).add(e);
    }
    // The whole day, midnight to 11 PM, so late-night and early-morning meals have a place.
    const first = 0, last = 23;
    final searching = _search.text.trim().isNotEmpty || _searchFocus.hasFocus;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, S.lg, gutter, 0),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: BlurSwitcher(
                                    child: Align(
                                      key: ValueKey(_day),
                                      alignment: Alignment.centerLeft,
                                      child: Text(isToday ? 'Food log' : dayTitle(_day), style: tt.headlineMedium),
                                    ),
                                  ),
                                ),
                                if (!isToday)
                                  TextButton(
                                    onPressed: () => _select(DateTime.now()),
                                    child: const Text('Back to today'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: S.md),
                            DayCarousel(selected: _day, onSelect: _select),
                            const SizedBox(height: S.md),
                            _MacroBars(consumed: consumed, targets: state.targets),
                            const SizedBox(height: S.xl),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 140),
                  // All 24 hours are built up front (cheap), so the current hour exists to scroll
                  // to on open; a lazy list hadn't built it yet and the log opened at midnight.
                  sliver: SliverList.list(
                    children: [
                      for (var hour = first; hour <= last; hour++)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: _HourBlock(
                              key: isToday && hour == nowHour ? _nowKey : null,
                              hour: hour,
                              entries: byHour[hour] ?? const [],
                              isNow: isToday && hour == nowHour,
                              isLast: hour == last,
                              onAdd: () => _addAtHour(hour),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Keyed layers: the results panel comes and goes between the scrim and the search bar,
          // and without keys Flutter would rebuild the bar in its place, dropping focus and the keyboard.
          if (searching)
            Positioned.fill(
              key: const ValueKey('scrim'),
              child: GestureDetector(
                onTap: _closeSearch,
                child: ColoredBox(color: Colors.black.withValues(alpha: t.dark ? 0.6 : 0.3)),
              ),
            ),
          // Results only once something's typed: an empty search shows nothing over the log.
          if (_search.text.trim().isNotEmpty)
            Positioned(
              key: const ValueKey('results'),
              left: gutter,
              right: gutter,
              top: MediaQuery.paddingOf(context).top + S.lg,
              bottom: 96 + MediaQuery.paddingOf(context).bottom,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: _SearchResults(
                    query: _search.text,
                    onPick: (p) async {
                      final at = _pendingAt;
                      _closeSearch();
                      await showProductSheet(context, p, day: _day, at: at);
                    },
                  ),
                ),
              ),
            ),
          Positioned(
            key: const ValueKey('searchBar'),
            left: 0,
            right: 0,
            bottom: 0,
            // The timeline fades out behind the search bar instead of showing through around it.
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [t.bg.withValues(alpha: 0), t.bg, t.bg],
                  stops: const [0, 0.4, 1],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, S.xl, gutter, S.md),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: _SearchBar(
                        controller: _search,
                        focus: _searchFocus,
                        pendingAt: _pendingAt,
                        onClose: _closeSearch,
                        onBarcode: () => PlatformCaps.hasCamera
                            ? openBarcodeScanner(context, day: _day, at: _pendingAt)
                            : openBarcodeEntry(context, day: _day, at: _pendingAt),
                        onPhoto: () => openSnapMeal(context, day: _day, at: _pendingAt),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Energy and the three macros as thin progress bars, one glance (Miller: four chunks).
class _MacroBars extends StatelessWidget {
  const _MacroBars({required this.consumed, required this.targets});
  final Nutrients consumed;
  final Nutrients targets;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    Widget bar(String label, double v, double target, Color color, {bool energy = false}) {
      final over = target > 0 && v > target * 1.1;
      final frac = target > 0 ? (v / target).clamp(0.0, 1.0) : 0.0;
      final shown = energy
          ? '${whole(Energy.toDisplay(v))} / ${whole(Energy.toDisplay(target))}'
          : '${whole(v)} / ${whole(target)}';
      return Expanded(
        child: Semantics(
          label: label,
          value: energy ? '${Energy.format(v)} of ${Energy.format(target)}' : '${whole(v)} of ${whole(target)} grams',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tt.labelSmall!.copyWith(color: color)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  shown,
                  maxLines: 1,
                  style: tt.labelMedium!.copyWith(color: over ? t.over : t.fg, fontFeatures: tabular),
                ),
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(end: frac),
                duration: Motion.of(context, Motion.slow),
                curve: Motion.settle,
                builder: (context, f, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: f.clamp(0, 1),
                    minHeight: 5,
                    backgroundColor: t.inset,
                    color: over ? t.over : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        bar(Energy.label, consumed.calories, targets.calories, t.calories, energy: true),
        const SizedBox(width: S.md),
        bar('Protein', consumed.protein, targets.protein, t.protein),
        const SizedBox(width: S.md),
        bar('Carbs', consumed.carbs, targets.carbs, t.carbs),
        const SizedBox(width: S.md),
        bar('Fat', consumed.fat, targets.fat, t.fat),
      ],
    );
  }
}

class _HourBlock extends StatelessWidget {
  const _HourBlock({
    super.key,
    required this.hour,
    required this.entries,
    required this.isNow,
    required this.isLast,
    required this.onAdd,
  });

  final int hour;
  final List<FoodEntry> entries;
  final bool isNow;
  final bool isLast;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final label = DateFormat('h a').format(DateTime(2000, 1, 1, hour));
    final total = Nutrients.sum(entries.map((e) => e.nutrients));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The rail: a thin line joining the hours.
          SizedBox(
            width: 72,
            child: Stack(
              children: [
                Positioned(
                  left: 35,
                  top: 0,
                  bottom: isLast ? null : 0,
                  height: isLast ? 20 : null,
                  child: Container(width: 1, color: t.border),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isNow ? t.accent : t.inset,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: tt.labelMedium!.copyWith(color: isNow ? t.onAccent : t.fg, fontFeatures: tabular),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      // Big hit area, small visual: the whole 48 px square adds at this hour.
                      Squishy(
                        onTap: onAdd,
                        feel: PressFeel.normal,
                        hitSlop: 4,
                        semanticLabel: 'Add food at $label',
                        child: SizedBox(
                          width: 44,
                          height: 40,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(color: t.inset, shape: BoxShape.circle),
                              child: Center(
                                child: FIcon(Symbols.add, size: 18, color: t.fg, weight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        // One entry already shows its own numbers: the hour total only earns
                        // its place when it adds something up.
                        child: entries.length < 2
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(right: S.xs),
                                child: Text(
                                  '${Energy.format(total.calories)}  ·  ${whole(total.protein)}P ${whole(total.carbs)}C ${whole(total.fat)}F',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: tt.labelMedium!.copyWith(fontFeatures: tabular),
                                ),
                              ),
                      ),
                    ],
                  ),
                  for (final e in entries) ...[const SizedBox(height: S.sm), _LogCard(entry: e)],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});
  final FoodEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final n = entry.nutrients;
    final grams = entry.grams;
    const radius = 18.0;
    // Two short lines instead of one long one, so nothing is cut off on a phone.
    final detail = [
      Energy.format(n.calories),
      if (grams != null) '${whole(grams)} ${entry.unit == 'ml' ? 'ml' : 'g'}' else entry.portionDescription,
    ].join('  ·  ');
    final macros = '${whole(n.protein)}P  ${whole(n.carbs)}C  ${whole(n.fat)}F';

    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      // A frequently used row: a quick ink tint, no squash.
      child: InkWell(
        onTap: () => showEditEntrySheet(context, entry),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.md, S.md, S.sm, S.md),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  DateFormat('H:mm').format(entry.consumedAt),
                  style: tt.labelMedium!.copyWith(fontFeatures: tabular),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: t.inset,
                  // Nested radius: card radius minus its 12 px padding.
                  borderRadius: BorderRadius.circular(S.inner(radius, S.md) + 4),
                ),
                child: Center(
                  child: FIcon(mealIcon(entry.meal), size: 20, color: t.fg, weight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(entry.name, style: tt.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (entry.trust != null) ...[const SizedBox(width: 4), TrustTag(entry.trust!, compact: true)],
                      ],
                    ),
                    Text(
                      detail,
                      style: tt.bodySmall!.copyWith(fontFeatures: tabular),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            macros,
                            style: tt.labelSmall!.copyWith(color: t.muted, fontFeatures: tabular),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.healthScore case final score?) ...[
                          const SizedBox(width: S.sm),
                          ScoreBadge(
                            score.score,
                            size: 12,
                            onTap: () => showScoreSheet(context, name: entry.name, score: score, entry: entry),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit ${entry.name}',
                onPressed: () => showEditEntrySheet(context, entry),
                icon: FIcon(Symbols.edit, size: 18, color: t.muted, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddAtSheet extends StatelessWidget {
  const _AddAtSheet({required this.at});
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    Widget option(String value, IconData icon, String label) => FRow(
      leading: FIcon(icon, color: t.fg, weight: FontWeight.w500),
      label: label,
      onTap: () => Navigator.pop(context, value),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add at ${DateFormat.jm().format(at)}', style: tt.headlineSmall),
          const SizedBox(height: S.lg),
          FGroup(
            children: [
              option('search', Symbols.search, 'Search foods'),
              option(
                'barcode',
                PlatformCaps.hasCamera ? Symbols.barcode_scanner : Symbols.keyboard,
                PlatformCaps.hasCamera ? 'Scan barcode' : 'Enter barcode',
              ),
              option('photo', Symbols.photo_camera, PlatformCaps.hasCamera ? 'Snap meal' : 'Photo estimate'),
              option('manual', Symbols.edit_note, 'Manual entry'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focus,
    required this.pendingAt,
    required this.onClose,
    required this.onBarcode,
    required this.onPhoto,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final DateTime? pendingAt;
  final VoidCallback onClose;
  final VoidCallback onBarcode;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final hint = pendingAt == null ? 'Search for a food' : 'Search · logs at ${DateFormat.jm().format(pendingAt!)}';
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                const SizedBox(width: S.lg),
                FIcon(Symbols.search, color: t.muted, weight: FontWeight.w500),
                const SizedBox(width: S.sm),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: hint,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                BlurSwitcher(
                  child: controller.text.isEmpty
                      ? IconButton(
                          key: const ValueKey('barcode'),
                          tooltip: PlatformCaps.hasCamera ? 'Scan barcode' : 'Enter barcode',
                          onPressed: onBarcode,
                          icon: FIcon(Symbols.barcode_scanner, color: t.fg, weight: FontWeight.w500),
                        )
                      : IconButton(
                          key: const ValueKey('clear'),
                          tooltip: 'Clear search',
                          onPressed: onClose,
                          icon: FIcon(Symbols.close, color: t.fg, weight: FontWeight.w500),
                        ),
                ),
                const SizedBox(width: S.xs),
              ],
            ),
          ),
        ),
        const SizedBox(width: S.sm),
        Squishy(
          onTap: onPhoto,
          feel: PressFeel.bold,
          semanticLabel: PlatformCaps.hasCamera ? 'Snap meal' : 'Photo estimate',
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border),
            ),
            child: Center(
              child: FIcon(Symbols.photo_camera, color: t.fg, weight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}

/// Local matches appear instantly (Doherty threshold); Open Food Facts results follow after a
/// short pause in typing.
class _SearchResults extends StatefulWidget {
  const _SearchResults({required this.query, required this.onPick});
  final String query;
  final ValueChanged<FoodProduct> onPick;

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  static final _off = OpenFoodFactsService();
  Timer? _debounce;
  List<FoodProduct> _online = const [];
  bool _loading = false;
  String? _error;
  String _lastQuery = '';

  @override
  void didUpdateWidget(_SearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _schedule();
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    final q = widget.query.trim();
    if (q.length < 2) {
      setState(() {
        _online = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      _lastQuery = q;
      try {
        final r = await _off.search(q);
        if (mounted && _lastQuery == q) {
          setState(() {
            _online = r;
            _loading = false;
            _error = null;
          });
        }
      } on FoodLookupException catch (e) {
        if (mounted && _lastQuery == q) {
          setState(() {
            _online = const [];
            _loading = false;
            _error = e.message;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// My Foods and foods logged before that match what's typed, each once, most recent first.
  /// Kept short so they sit in the results rather than crowding them.
  static const _maxRecent = 4;
  List<FoodProduct> _local(AppState state, String q) {
    final out = <FoodProduct>[];
    final seen = <String>{};
    if (q.isEmpty) return out;
    bool match(String name, String? brand) =>
        name.toLowerCase().contains(q) || (brand?.toLowerCase().contains(q) ?? false);
    for (final f in state.customFoodsByRecent) {
      if (out.length >= _maxRecent) return out;
      if (match(f.name, f.brand) && seen.add(f.name.toLowerCase())) out.add(FoodProduct.fromCustomFood(f));
    }
    final recent = [...state.entries]..sort((a, b) => b.consumedAt.compareTo(a.consumedAt));
    for (final e in recent) {
      if (out.length >= _maxRecent) break;
      if (!match(e.name, e.brand) || !seen.add(e.name.toLowerCase()) || e.quantity <= 0) continue;
      final per = e.nutrients * (1 / e.quantity);
      final byAmount = e.unit == 'g' || e.unit == 'ml';
      out.add(
        FoodProduct(
          barcode: e.barcode ?? 'recent-${e.id}',
          name: e.name,
          brand: e.brand,
          servingDescription: byAmount ? null : e.unit,
          servingGrams: byAmount ? null : (e.grams == null ? null : e.grams! / e.quantity),
          per100g: byAmount ? per * 100 : null,
          perServingReported: byAmount ? null : per,
          source: e.source,
          trust: e.trust,
          liquid: e.unit == 'ml',
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final q = widget.query.trim().toLowerCase();
    final local = _local(state, q);
    // Built-in everyday foods, minus any you've already got under the same name.
    final common = [
      for (final p in searchCommonFoods(q))
        if (!local.any((l) => l.name.toLowerCase() == p.name.toLowerCase())) p,
    ];

    final children = <Widget>[
      if (local.isNotEmpty) ...[
        const SectionLabel('Recently added'),
        for (final p in local) _ResultRow(product: p, onTap: () => widget.onPick(p)),
        const SizedBox(height: S.md),
      ],
      if (common.isNotEmpty) ...[
        const SectionLabel('Common foods'),
        for (final p in common) _ResultRow(product: p, onTap: () => widget.onPick(p)),
        const SizedBox(height: S.md),
      ],
      if (q.length >= 2) ...[
        const SectionLabel('Packaged foods · Open Food Facts'),
        if (_loading)
          for (var i = 0; i < 3; i++) const _SkeletonRow()
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(S.md),
            child: Text(_error!, style: tt.bodyMedium!.copyWith(color: t.muted)),
          )
        else if (_online.isEmpty)
          Padding(
            padding: const EdgeInsets.all(S.md),
            child: Text(
              common.isEmpty && local.isEmpty
                  ? 'No matches. Try a simpler name, scan the barcode, or add it with Manual entry.'
                  : 'No packaged matches.',
              style: tt.bodyMedium!.copyWith(color: t.muted),
            ),
          )
        else
          for (final p in _online) _ResultRow(product: p, onTap: () => widget.onPick(p)),
      ],
    ];
    if (children.isEmpty) return const SizedBox.shrink();

    return Rise(
      distance: 14,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(S.radiusCard),
          border: Border.all(color: t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(S.sm, S.lg, S.sm, S.sm),
          children: children,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.product, required this.onTap});
  final FoodProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    final tt = Theme.of(context).textTheme;
    final serving = product.perServing;
    final per = serving != null
        ? '${Energy.format(serving.calories)} per ${product.servingLabel}'
        : product.per100g != null
        ? '${Energy.format(product.per100g!.calories)} per 100 ${product.amountUnit}'
        : '';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: tt.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [?product.brand, per].where((s) => s.isNotEmpty).join(' · '),
                    style: tt.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (product.trust != null) ...[const SizedBox(width: S.sm), TrustTag(product.trust!)],
            const SizedBox(width: S.xs),
            FIcon(Symbols.chevron_right, color: t.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final t = FT.of(context);
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: t.inset, borderRadius: BorderRadius.circular(6)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(180, 14), const SizedBox(height: 6), bar(120, 10)],
      ),
    );
  }
}
