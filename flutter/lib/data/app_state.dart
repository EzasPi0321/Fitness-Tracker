import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

import '../models/ai_usage.dart';
import '../models/body_fat.dart';
import '../models/food.dart';
import '../models/nutrients.dart';
import '../models/gym.dart';
import '../models/health_score.dart';
import '../models/profile.dart';
import '../models/sleep.dart';
import '../models/util.dart';
import '../services/ai_vision.dart';
import '../services/health_service.dart';
import '../services/key_store.dart';
import '../services/updates.dart';
import 'sample_data.dart';
import 'storage.dart';

String newId() {
  final r = Random();
  // Not 1 << 32: on the web shifts are 32-bit, so that is 0 and nextInt throws.
  return DateTime.now().microsecondsSinceEpoch.toRadixString(36) + r.nextInt(0x3fffffff).toRadixString(36);
}

/// The single source of truth. Every write goes through here so the local log and the
/// health store stay in step, and every change is saved right away (Doherty threshold:
/// the UI never waits on disk or network).
class AppState extends ChangeNotifier {
  AppState({DocumentStore? store, HealthService? health, KeyStore? keys, UpdateService? updates})
    : _store = store ?? DocumentStore(),
      health = health ?? HealthService(),
      keys = keys ?? KeyStore(),
      updates = updates ?? UpdateService();

  final UpdateService updates;

  /// A newer release, when one has been found.
  AppUpdate? availableUpdate;
  DateTime? _lastUpdateCheck;
  int? _dismissedUpdateBuild;

  /// True when the banner on Today should offer [availableUpdate].
  bool get showUpdateBanner => availableUpdate != null && availableUpdate!.build != _dismissedUpdateBuild;

  /// Looks for a newer release. Automatic checks run at most once a day and only on builds
  /// made by CI (local builds have no number to compare). Returns the update, or null.
  Future<AppUpdate?> checkForUpdates({bool manual = false}) async {
    if (!manual) {
      if (kIsWeb || appBuild == 0) return null;
      final last = _lastUpdateCheck;
      // At most hourly: often enough that a new release shows up the same day, while
      // staying far under GitHub's 60-requests-an-hour limit for unsigned calls.
      if (last != null && DateTime.now().difference(last) < const Duration(hours: 1)) return availableUpdate;
    }
    AppUpdate? found;
    try {
      found = await updates.check();
    } on UpdateCheckException {
      if (manual) rethrow;
      return availableUpdate;
    }
    _lastUpdateCheck = DateTime.now();
    availableUpdate = found;
    _changed();
    return found;
  }

  void dismissUpdate() {
    _dismissedUpdateBuild = availableUpdate?.build;
    _changed();
  }

  final DocumentStore _store;
  final HealthService health;
  final KeyStore keys;

  bool loaded = false;
  UserProfile? profile;
  final List<FoodEntry> entries = [];
  final List<CustomFood> customFoods = [];
  final List<WeightEntry> weights = [];
  final List<WaterEntry> water = [];
  final List<SleepEntry> sleep = [];
  final List<GymSession> gym = [];

  /// Body fat readings: typed, read from a report, or estimated from a photo.
  final List<BodyFatEntry> bodyFat = [];

  /// Every photo or label sent to an AI model, with its tokens and cost (newest last).
  final List<AiUsage> aiUsage = [];

  /// The credit balance the user typed in from their provider's console, and when. The API
  /// key can't read the balance itself, so FitTrack counts down from this.
  double? aiBalanceUsd;
  DateTime? aiBalanceAt;

  /// Hours of sleep to aim for each night.
  double sleepGoalHours = 8;

  /// Set by the user; when null the goal follows body weight.
  double? waterGoalOverride;

  int stepGoal = 10000;

  /// Example step counts shown with sample data (no health store on desktop).
  final Map<DateTime, int> sampleSteps = {};

  /// Steps without a health store (iPhone): sent in by a Shortcuts automation that reads
  /// Apple Health, or typed in. Keyed by day.
  final Map<DateTime, int> loggedSteps = {};

  /// When the shortcut last sent steps in, to say so on the card.
  DateTime? stepsFromShortcutAt;

  /// Black by default; light and system are options in Settings.
  ThemeMode appearance = ThemeMode.dark;

  /// kcal or kJ for everything shown and typed; storage is always kcal.
  EnergyUnit get energyUnit => Energy.unit;

  bool healthEnabled = false;
  bool addActiveEnergy = false;
  VisionProvider visionProvider = VisionProvider.claude;
  String visionModel = VisionProvider.claude.defaultModel;
  bool _modelChosen = false;

  /// True while the log holds generated sample data.
  bool isSample = false;
  String? healthError;

  /// Bumped whenever food is logged, so the dashboard can celebrate the moment.
  final logPulse = ValueNotifier<int>(0);

  Future<void> load({bool seedSampleIfEmpty = false}) async {
    final raw = await _store.read();
    if (raw != null) {
      try {
        _fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {
        // A damaged document shouldn't brick the app; start clean.
      }
    }
    // The live apps (phone, Windows) never carry example data; only the web preview does.
    // An install that picked up sample data from an older version gets it removed here.
    if (isSample && !demoAllowed) _removeSampleData();
    if (profile == null && seedSampleIfEmpty) loadSampleData(save: false);
    if (isSample && sampleSteps.isEmpty) sampleSteps.addAll(SampleData.generate().steps);
    loaded = true;
    unawaited(checkForUpdates());
    notifyListeners();
  }

  // ---- Queries ----

  /// Entries grouped by day, built once and reused until something changes. Screens ask for
  /// many days at once (the day strip, a 90-day chart), so scanning the whole log for each day
  /// was the main cost of a rebuild.
  Map<DateTime, List<FoodEntry>>? _byDay;

  List<FoodEntry> entriesOn(DateTime day) {
    final index = _byDay ??= () {
      final m = <DateTime, List<FoodEntry>>{};
      for (final e in entries) {
        m.putIfAbsent(startOfDay(e.consumedAt), () => []).add(e);
      }
      for (final l in m.values) {
        l.sort((a, b) => a.consumedAt.compareTo(b.consumedAt));
      }
      return m;
    }();
    return List.of(index[startOfDay(day)] ?? const []);
  }

  @override
  void notifyListeners() {
    _byDay = null; // every change goes through here, so the index can never go stale
    HealthScore.goal = profile?.goal ?? WeightGoal.maintain;
    super.notifyListeners();
  }

  Nutrients consumedOn(DateTime day) => Nutrients.sum(entriesOn(day).map((e) => e.nutrients));

  Nutrients get targets => profile?.targets ?? const Nutrients(calories: 2000, protein: 140, carbs: 220, fat: 65);

  CustomFood? customFoodForBarcode(String barcode) {
    for (final f in customFoods) {
      if (f.barcode == barcode) return f;
    }
    return null;
  }

  List<CustomFood> get customFoodsByRecent => [...customFoods]..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));

  List<WeightEntry> get weightsByDate => [...weights]..sort((a, b) => a.date.compareTo(b.date));

  // ---- Profile ----

  void completeOnboarding(UserProfile p) {
    profile = p;
    if (isSample) {
      entries.clear();
      weights.clear();
      customFoods.clear();
      water.clear();
      sleep.clear();
      gym.clear();
      bodyFat.clear();
      sampleSteps.clear();
      loggedSteps.clear();
      isSample = false;
    }
    if (weights.isEmpty) weights.add(WeightEntry(id: newId(), date: DateTime.now(), kilograms: p.weightKg));
    _changed();
  }

  /// Changes a profile field and recalculates the daily targets from it (Mifflin–St Jeor).
  void updateProfileAndPlan(void Function(UserProfile p) change) {
    final p = profile;
    if (p == null) return;
    change(p);
    if (p.isBodyValid) p.targets = p.plan.targets;
    _changed();
  }

  void updateProfile(void Function(UserProfile p) change) {
    final p = profile;
    if (p == null) return;
    change(p);
    _changed();
  }

  // ---- Food log ----

  Future<void> logEntries(List<FoodEntry> list) async {
    entries.addAll(list);
    logPulse.value++;
    _changed();
    // Fill in missing weight, fibre and sugar after the fact, so logging never waits on it.
    if (!isSample) unawaited(_fillInBackground(list.where((e) => e.missingDetail).toList()));
    if (_syncHealth) {
      for (final e in list) {
        e.healthSynced = await health.saveFood(
          name: e.name,
          meal: e.meal.name,
          nutrients: e.nutrients,
          at: e.consumedAt,
        );
      }
      _changed();
    }
  }

  /// Call after mutating an entry (portion, meal, time). `previousTime` lets the health
  /// record at the old timestamp be replaced.
  /// Weight, fibre and sugar per calorie for foods the AI has filled in before, by barcode or
  /// by name and brand. Logging the same food again, at any portion, reuses them for free.
  final Map<String, FoodDetailRates> detailCache = {};

  static String detailKey(FoodEntry e) {
    final code = e.barcode?.trim();
    if (code != null && code.isNotEmpty) return 'b:$code';
    String norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return 'n:${norm(e.name)}|${norm(e.brand)}';
  }

  /// Fills [e]'s gaps from an earlier answer for the same food. True when it did.
  bool _applyCachedDetail(FoodEntry e) {
    final r = detailCache[detailKey(e)];
    final kcal = e.nutrients.calories;
    if (r == null || kcal <= 0) return false;
    _mergeDetail(
      e,
      FoodDetail(
        grams: r.gramsPerKcal == null ? null : r.gramsPerKcal! * kcal,
        fiber: r.fiberPerKcal * kcal,
        sugar: r.sugarPerKcal * kcal,
      ),
    );
    return true;
  }

  /// Adds what [e] lacks, never replacing a recorded value.
  void _mergeDetail(FoodEntry e, FoodDetail d) {
    final n = e.nutrients;
    e
      ..grams = e.grams ?? d.grams
      ..nutrients = Nutrients(
        calories: n.calories,
        protein: n.protein,
        carbs: n.carbs,
        fat: n.fat,
        fiber: n.fiber > 0 ? n.fiber : (d.fiber ?? 0),
        sugar: n.sugar > 0 ? n.sugar : (d.sugar ?? 0),
      ).sanitized
      ..detailChecked = true;
  }

  Future<void> _fillInBackground(List<FoodEntry> list) async {
    if (list.isEmpty) return;
    // Foods filled in before cost nothing: no key needed, no request.
    final rest = [
      for (final e in list)
        if (!_applyCachedDetail(e)) e,
    ];
    if (rest.length != list.length) _changed();
    if (rest.isEmpty) return;
    final key = await keys.read(visionProvider.keyName);
    if (key.trim().isEmpty) return;
    for (final e in rest) {
      try {
        await fillMissingDetail(e, apiKey: key);
      } catch (_) {
        // Offline or the AI couldn't say: the score leaves the gaps out, and the score sheet
        // offers to try again.
      }
    }
  }

  /// Asks the AI for a logged food's missing weight, fibre and sugar and saves what's missing.
  /// Recorded values are never replaced. Returns what was added, or throws [VisionException].
  Future<FoodDetail> fillMissingDetail(FoodEntry e, {String? apiKey}) async {
    if (_applyCachedDetail(e)) {
      _changed();
      return FoodDetail(grams: e.grams, fiber: e.nutrients.fiber, sugar: e.nutrients.sugar);
    }
    final key = apiKey ?? await keys.read(visionProvider.keyName);
    final service = AIVisionService(provider: visionProvider, apiKey: key, model: visionModel);
    try {
      final d = await service.fillDetail(name: e.name, brand: e.brand, portion: e.portionDescription, n: e.nutrients);
      _mergeDetail(e, d);
      final kcal = e.nutrients.calories;
      if (kcal > 0) {
        detailCache[detailKey(e)] = FoodDetailRates(
          gramsPerKcal: e.grams == null ? null : e.grams! / kcal,
          fiberPerKcal: e.nutrients.fiber / kcal,
          sugarPerKcal: e.nutrients.sugar / kcal,
        );
        if (detailCache.length > 2000) detailCache.remove(detailCache.keys.first);
      }
      _changed();
      return d;
    } finally {
      recordAiUsage('detail', service.calls);
    }
  }

  Future<void> updateEntry(FoodEntry e, {required DateTime previousTime}) async {
    _changed();
    if (e.healthSynced) await health.deleteFood(previousTime);
    if (_syncHealth) {
      e.healthSynced = await health.saveFood(name: e.name, meal: e.meal.name, nutrients: e.nutrients, at: e.consumedAt);
      _changed();
    }
  }

  Future<void> deleteEntry(FoodEntry e) async {
    entries.removeWhere((x) => x.id == e.id);
    _changed();
    if (e.healthSynced) await health.deleteFood(e.consumedAt);
  }

  /// Puts back an entry removed by swipe-to-delete.
  Future<void> restoreEntry(FoodEntry e) async {
    e.healthSynced = false; // its health record was removed with it
    entries.add(e);
    _changed();
    if (_syncHealth) {
      e.healthSynced = await health.saveFood(name: e.name, meal: e.meal.name, nutrients: e.nutrients, at: e.consumedAt);
      _changed();
    }
  }

  void deleteAllLogs() {
    entries.clear();
    isSample = false;
    _changed();
  }

  // ---- My Foods ----

  CustomFood upsertCustomFood({
    String? barcode,
    required String name,
    String? brand,
    required String serving,
    double? servingGrams,
    required Nutrients perServing,
    NutritionTrust? trust,
  }) {
    final existing = barcode == null ? null : customFoodForBarcode(barcode);
    if (existing != null) {
      existing
        ..name = name
        ..brand = brand
        ..servingDescription = serving
        ..servingGrams = servingGrams
        ..perServing = perServing.sanitized
        ..trust = trust
        ..markUsed();
      _changed();
      return existing;
    }
    final food = CustomFood(
      id: newId(),
      name: name,
      brand: brand,
      barcode: barcode,
      servingDescription: serving,
      servingGrams: servingGrams,
      perServing: perServing,
      trust: trust,
    )..markUsed();
    customFoods.add(food);
    _changed();
    return food;
  }

  void markCustomFoodUsed(String id) {
    for (final f in customFoods) {
      if (f.id == id) f.markUsed();
    }
    _changed();
  }

  void deleteCustomFood(String id) {
    customFoods.removeWhere((f) => f.id == id);
    _changed();
  }

  // ---- Water ----

  /// 35 ml per kg of body weight, rounded to 50 ml (1.5–4 L), unless the user set one.
  double get waterGoal {
    final o = waterGoalOverride;
    if (o != null && o > 0) return o;
    final kg = profile?.weightKg ?? 70;
    return ((kg * 35 / 50).round() * 50).toDouble().clamp(1500, 4000);
  }

  List<WaterEntry> waterOn(DateTime day) =>
      water.where((w) => sameDay(w.at, day)).toList()..sort((a, b) => a.at.compareTo(b.at));

  double waterTotalOn(DateTime day) => waterOn(day).fold(0, (a, w) => a + w.ml);

  Future<void> addWater(double ml, DateTime at) async {
    if (ml <= 0 || !ml.isFinite) return;
    water.add(WaterEntry(id: newId(), at: at, ml: ml));
    _changed();
    if (_syncHealth) await health.saveWater(ml, at);
  }

  /// Removes the most recent drink on [day] (the undo button).
  WaterEntry? undoWater(DateTime day) {
    final list = waterOn(day);
    if (list.isEmpty) return null;
    final last = list.last;
    water.removeWhere((w) => w.id == last.id);
    _changed();
    return last;
  }

  // ---- Sleep ----

  /// Nights logged by hand, by the day you woke up.
  Map<DateTime, SleepNight> get loggedNights => nightsByDay(sleep.map(SleepNight.fromEntry));

  /// Logs a night (or replaces [replaceId]). Returns an error to show, or null when saved.
  String? logSleep(DateTime start, DateTime end, {String? replaceId}) {
    if (!end.isAfter(start)) return 'Wake-up time must be after bedtime.';
    final d = end.difference(start);
    if (d > const Duration(hours: 16)) return 'That’s over 16 hours. Check the times.';
    if (end.isAfter(DateTime.now().add(const Duration(minutes: 5)))) return 'Wake-up time is in the future.';
    // One logged night per morning: a new one (or the edited one) replaces the old.
    final replaced = sleep.where((s) => s.id == replaceId || sameDay(s.end, end)).toList();
    sleep.removeWhere(replaced.contains);
    sleep.add(SleepEntry(id: newId(), start: start, end: end));
    _changed();
    // Mirror it to Samsung Health / Apple Health, replacing what FitTrack wrote before.
    if (_syncHealth) {
      unawaited(() async {
        for (final r in replaced) {
          await health.deleteSleep(r.start, r.end);
        }
        await health.saveSleep(start, end);
      }());
    }
    return null;
  }

  SleepEntry? removeSleep(String id) {
    final i = sleep.indexWhere((s) => s.id == id);
    if (i < 0) return null;
    final removed = sleep.removeAt(i);
    _changed();
    if (_syncHealth) unawaited(health.deleteSleep(removed.start, removed.end));
    return removed;
  }

  void restoreSleep(SleepEntry e) {
    sleep.add(e);
    _changed();
    if (_syncHealth) unawaited(health.saveSleep(e.start, e.end));
  }

  // ---- AI usage ----

  /// Records what a photo or label cost, from the requests the AI service made.
  void recordAiUsage(String kind, List<AiCall> calls) {
    if (calls.isEmpty) return;
    aiUsage.add(AiUsage.ofCalls(kind, calls));
    if (aiUsage.length > 1000) aiUsage.removeRange(0, aiUsage.length - 1000);
    _changed();
  }

  void setAiBalance(double? usd) {
    aiBalanceUsd = (usd == null || usd < 0) ? null : usd;
    aiBalanceAt = aiBalanceUsd == null ? null : DateTime.now();
    _changed();
  }

  double spentSince(DateTime since) => aiUsage.where((u) => !u.at.isBefore(since)).fold(0, (a, u) => a + (u.usd ?? 0));

  Iterable<AiUsage> get aiUsageThisMonth {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    return aiUsage.where((u) => !u.at.isBefore(start));
  }

  /// Average cost of a photo over the last 20 with a known price; before there are any,
  /// an estimate for the chosen model.
  double? get costPerPhotoUsd {
    final priced = [
      for (final u in aiUsage.reversed)
        if (u.usd != null) u.usd!,
    ].take(20).toList();
    if (priced.isNotEmpty) return priced.reduce((a, b) => a + b) / priced.length;
    return estimatedPhotoUsd(visionModel);
  }

  bool get costPerPhotoIsMeasured => aiUsage.any((u) => u.usd != null);

  /// What's left of the typed-in balance after everything sent since.
  double? get aiBalanceLeftUsd {
    final b = aiBalanceUsd, at = aiBalanceAt;
    if (b == null || at == null) return null;
    return (b - spentSince(at)).clamp(0, double.infinity).toDouble();
  }

  /// About how many more photos the balance covers at the current cost per photo.
  int? get photosLeft {
    final left = aiBalanceLeftUsd, per = costPerPhotoUsd;
    if (left == null || per == null || per <= 0) return null;
    return (left / per).floor();
  }

  // ---- Gym ----

  List<GymSession> gymOn(DateTime day) =>
      gym.where((g) => sameDay(g.at, day)).toList()..sort((a, b) => a.at.compareTo(b.at));

  /// Sessions in the Monday-to-Sunday week containing [day].
  int gymThisWeek(DateTime day) {
    final start = weekStart(day);
    final end = addDays(start, 7);
    return gym.where((g) => !g.at.isBefore(start) && g.at.isBefore(end)).length;
  }

  /// Logs a session, or replaces [replaceId] when editing one.
  void logGym(TrainingType type, DateTime at, {int? minutes, String note = '', String? replaceId}) {
    if (replaceId != null) gym.removeWhere((g) => g.id == replaceId);
    gym.add(
      GymSession(
        id: newId(),
        at: at,
        type: type,
        minutes: (minutes != null && minutes > 0) ? minutes.clamp(1, 600) : null,
        note: note.trim(),
      ),
    );
    _changed();
  }

  GymSession? removeGym(String id) {
    final i = gym.indexWhere((g) => g.id == id);
    if (i < 0) return null;
    final removed = gym.removeAt(i);
    _changed();
    return removed;
  }

  void restoreGym(GymSession g) {
    gym.add(g);
    _changed();
  }

  void setSleepGoal(double hours) {
    if (hours < 4 || hours > 12) return;
    sleepGoalHours = hours;
    _changed();
  }

  /// Saves a day's steps. The latest number always wins: each shortcut run reads Health's
  /// current total, so a lower count is a correction (say, after fixing a double-counting
  /// shortcut), not a stale reading.
  void setLoggedSteps(DateTime day, int? steps, {bool fromShortcut = false}) {
    final d = startOfDay(day);
    if (steps == null || steps < 0) {
      loggedSteps.remove(d);
    } else {
      loggedSteps[d] = steps;
      if (fromShortcut) stepsFromShortcutAt = DateTime.now();
    }
    _changed();
  }

  /// Handles fittrack://steps?count=8432 (and an optional &date=2026-11-22) from Shortcuts.
  /// Returns true when the link was understood.
  bool handleLink(Uri uri) {
    if (uri.scheme != 'fittrack') return false;
    final what = uri.host.isNotEmpty ? uri.host : (uri.pathSegments.isEmpty ? '' : uri.pathSegments.first);
    if (what != 'steps') return false;
    final count = parseLenientNumber(uri.queryParameters['count']);
    if (count == null || count < 0 || count > 200000) return false;
    final date = DateTime.tryParse(uri.queryParameters['date'] ?? '');
    setLoggedSteps(date ?? DateTime.now(), count.round(), fromShortcut: true);
    return true;
  }

  void setStepGoal(int steps) {
    if (steps <= 0) return;
    stepGoal = steps;
    _changed();
  }

  void setWaterGoal(double? ml) {
    waterGoalOverride = (ml == null || ml <= 0) ? null : ml;
    _changed();
  }

  // ---- Weight ----

  Future<void> addWeight(double kilograms, DateTime date, {String? id}) async {
    final latest = weights.isEmpty ? null : weightsByDate.last.date;
    weights.add(WeightEntry(id: id ?? newId(), date: date, kilograms: kilograms));
    if (latest == null || !date.isBefore(latest)) profile?.weightKg = kilograms;
    _changed();
    if (_syncHealth) await health.saveWeight(kilograms, date);
  }

  // ---- Body fat ----

  List<BodyFatEntry> get bodyFatByDate => [...bodyFat]..sort((a, b) => a.at.compareTo(b.at));

  /// Saves a reading. A report's weight can come along, logged as a weigh-in at the same time.
  Future<void> logBodyFat(BodyFatEntry e, {double? weightKg}) async {
    bodyFat.add(e);
    _changed();
    if (weightKg != null) await addWeight(weightKg, e.at, id: 'bf-${e.id}');
    // Estimates stay in FitTrack: Health has no way to mark a number as a rough guess.
    if (_syncHealth && !e.source.isEstimate) await health.saveBodyFat(e.percent, e.at);
  }

  BodyFatEntry? removeBodyFat(String id) {
    final i = bodyFat.indexWhere((b) => b.id == id);
    if (i < 0) return null;
    final removed = bodyFat.removeAt(i);
    _changed();
    return removed;
  }

  /// Takes back a reading just logged, with the weigh-in its report added.
  void undoBodyFat(String id) {
    bodyFat.removeWhere((b) => b.id == id);
    weights.removeWhere((w) => w.id == 'bf-$id');
    _changed();
  }

  void restoreBodyFat(BodyFatEntry e) {
    bodyFat.add(e);
    _changed();
  }

  /// The weigh-in nearest to [at], for lean mass; the profile weight when there are none.
  double? weightNear(DateTime at) {
    if (weights.isEmpty) return profile?.weightKg;
    return weights.reduce((a, b) => (a.date.difference(at).abs() <= b.date.difference(at).abs()) ? a : b).kilograms;
  }

  // ---- Settings ----

  Future<void> setHealthEnabled(bool on) async {
    if (!on) {
      healthEnabled = false;
      _changed();
      return;
    }
    healthError = null;
    final ok = await health.requestAuthorization();
    healthEnabled = ok;
    if (!ok) {
      healthError = '${health.storeName} access wasn’t granted. You can allow it in the ${health.storeName} app.';
    }
    await refreshHealthAccess();
    _changed();
    refreshHealth();
  }

  /// Data types the health store hasn't allowed FitTrack to read (Android only; Apple hides it).
  List<String> healthMissing = const [];

  Future<void> refreshHealthAccess() async {
    if (!healthEnabled || !health.isSupported) {
      healthMissing = const [];
      return;
    }
    final granted = await health.grantedReads();
    healthMissing = granted == null
        ? const []
        : [
            for (final n in health.readNames)
              if (!granted.contains(n)) n,
          ];
  }

  /// Bumped when health data should be read again (connected, app reopened, pulled to refresh).
  final healthRefresh = ValueNotifier<int>(0);

  void refreshHealth() => healthRefresh.value++;

  void setEnergyUnit(EnergyUnit u) {
    Energy.unit = u;
    _changed();
  }

  void setAppearance(ThemeMode m) {
    appearance = m;
    _changed();
  }

  void setAddActiveEnergy(bool on) {
    addActiveEnergy = on;
    _changed();
  }

  /// Picking a model also picks its provider (and so which API key is used).
  void setVisionModel(String id) {
    final m = AiModel.byId(id);
    _modelChosen = true;
    visionModel = m.id;
    visionProvider = m.provider;
    _changed();
  }

  bool get _syncHealth => healthEnabled && health.isSupported;

  // ---- Sample data ----

  /// Sample data is offered in the web preview, in debug builds (`flutter run`), and in any
  /// build made with `--dart-define=FITTRACK_DEMO=true`. Release builds from CI never have it.
  static bool get demoAllowed => demoOverride ?? (kIsWeb || kDebugMode || const bool.fromEnvironment('FITTRACK_DEMO'));

  /// Lets tests act as a release build (tests themselves run in debug mode).
  @visibleForTesting
  static bool? demoOverride;

  /// Drops the generated examples (their ids start with "sample-") but keeps anything the
  /// user logged themselves, then sends them to onboarding to set up their own plan.
  void _removeSampleData() {
    bool generated(String id) => id.startsWith('sample-');
    entries.removeWhere((e) => generated(e.id));
    weights.removeWhere((w) => generated(w.id));
    water.removeWhere((w) => generated(w.id));
    sleep.removeWhere((s) => generated(s.id));
    gym.removeWhere((g) => generated(g.id));
    bodyFat.removeWhere((b) => generated(b.id));
    customFoods.removeWhere((f) => generated(f.id));
    sampleSteps.clear();
    profile = null;
    isSample = false;
    _changed();
  }

  void loadSampleData({bool save = true}) {
    final s = SampleData.generate();
    profile = s.profile;
    entries
      ..clear()
      ..addAll(s.entries);
    weights
      ..clear()
      ..addAll(s.weights);
    customFoods
      ..clear()
      ..addAll(s.customFoods);
    water
      ..clear()
      ..addAll(s.water);
    sleep
      ..clear()
      ..addAll(s.sleep);
    gym
      ..clear()
      ..addAll(s.gym);
    bodyFat
      ..clear()
      ..addAll(s.bodyFat);
    sampleSteps
      ..clear()
      ..addAll(s.steps);
    isSample = true;
    if (save) {
      _changed();
    }
  }

  /// Clears everything and returns to onboarding.
  void startFresh() {
    profile = null;
    entries.clear();
    weights.clear();
    customFoods.clear();
    water.clear();
    sleep.clear();
    gym.clear();
    sampleSteps.clear();
    waterGoalOverride = null;
    isSample = false;
    _changed();
  }

  // ---- Persistence ----

  Timer? _saveTimer;

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 150), () => _store.write(jsonEncode(_toJson())));
  }

  /// Writes immediately (used by tests and on app pause).
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _store.write(jsonEncode(_toJson()));
  }

  Map<String, dynamic> _toJson() => {
    'v': 2,
    'profile': profile?.toJson(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'customFoods': customFoods.map((e) => e.toJson()).toList(),
    'weights': weights.map((e) => e.toJson()).toList(),
    'water': water.map((e) => e.toJson()).toList(),
    'sleep': sleep.map((e) => e.toJson()).toList(),
    'gym': gym.map((e) => e.toJson()).toList(),
    'detailCache': {for (final e in detailCache.entries) e.key: e.value.toJson()},
    'steps': {for (final e in loggedSteps.entries) '${e.key.millisecondsSinceEpoch}': e.value},
    if (stepsFromShortcutAt != null) 'stepsAt': stepsFromShortcutAt!.millisecondsSinceEpoch,
    'bodyFat': bodyFat.map((e) => e.toJson()).toList(),
    'aiUsage': aiUsage.map((e) => e.toJson()).toList(),
    'settings': {
      'health': healthEnabled,
      'addActive': addActiveEnergy,
      'provider': visionProvider.name,
      'model': visionModel,
      'modelChosen': _modelChosen,
      'sample': isSample,
      'appearance': appearance.name,
      'energy': Energy.unit.name,
      'waterGoal': waterGoalOverride,
      'stepGoal': stepGoal,
      'sleepGoal': sleepGoalHours,
      'aiBalance': aiBalanceUsd,
      'aiBalanceAt': aiBalanceAt?.millisecondsSinceEpoch,
      'lastUpdateCheck': _lastUpdateCheck?.millisecondsSinceEpoch,
      'dismissedUpdate': _dismissedUpdateBuild,
    },
  };

  void _fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) =>
        (j[k] is List ? j[k] as List : const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    loggedSteps.clear();
    if (j['steps'] is Map) {
      for (final e in (j['steps'] as Map).entries) {
        final ms = int.tryParse('${e.key}');
        if (ms != null && e.value is num) {
          loggedSteps[DateTime.fromMillisecondsSinceEpoch(ms)] = (e.value as num).toInt();
        }
      }
    }
    final stepsAt = j['stepsAt'] as num?;
    stepsFromShortcutAt = stepsAt == null ? null : DateTime.fromMillisecondsSinceEpoch(stepsAt.toInt());
    profile = j['profile'] is Map ? UserProfile.fromJson((j['profile'] as Map).cast<String, dynamic>()) : null;
    entries
      ..clear()
      ..addAll(list('entries').map(FoodEntry.fromJson));
    customFoods
      ..clear()
      ..addAll(list('customFoods').map(CustomFood.fromJson));
    weights
      ..clear()
      ..addAll(list('weights').map(WeightEntry.fromJson));
    water
      ..clear()
      ..addAll(list('water').map(WaterEntry.fromJson));
    sleep
      ..clear()
      ..addAll(list('sleep').map(SleepEntry.fromJson));
    gym
      ..clear()
      ..addAll(list('gym').map(GymSession.fromJson));
    detailCache.clear();
    if (j['detailCache'] is Map) {
      for (final e in (j['detailCache'] as Map).entries) {
        if (e.value is Map)
          detailCache['${e.key}'] = FoodDetailRates.fromJson((e.value as Map).cast<String, dynamic>());
      }
    }
    bodyFat
      ..clear()
      ..addAll(list('bodyFat').map(BodyFatEntry.fromJson));
    aiUsage
      ..clear()
      ..addAll(list('aiUsage').map(AiUsage.fromJson));
    final s = j['settings'] is Map ? (j['settings'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    healthEnabled = (s['health'] as bool?) ?? false;
    waterGoalOverride = (s['waterGoal'] as num?)?.toDouble();
    stepGoal = ((s['stepGoal'] as num?) ?? 10000).toInt();
    sleepGoalHours = ((s['sleepGoal'] as num?) ?? 8).toDouble().clamp(4, 12);
    aiBalanceUsd = (s['aiBalance'] as num?)?.toDouble();
    final balAt = s['aiBalanceAt'] as num?;
    aiBalanceAt = balAt == null ? null : DateTime.fromMillisecondsSinceEpoch(balAt.toInt());
    final lastCheck = s['lastUpdateCheck'] as num?;
    _lastUpdateCheck = lastCheck == null ? null : DateTime.fromMillisecondsSinceEpoch(lastCheck.toInt());
    _dismissedUpdateBuild = (s['dismissedUpdate'] as num?)?.toInt();
    addActiveEnergy = (s['addActive'] as bool?) ?? false;
    visionProvider = VisionProvider.values.firstWhere(
      (v) => v.name == s['provider'],
      orElse: () => VisionProvider.gemini,
    );
    // Installs that never chose a model were on the old default (Opus): move them to Smart.
    var savedModel = (s['model'] as String?) ?? AiModel.smartId;
    if (s['modelChosen'] != true && savedModel == AiModel.carefulModel) savedModel = AiModel.smartId;
    _modelChosen = s['modelChosen'] == true;
    final model = AiModel.byId(savedModel);
    visionModel = model.id;
    visionProvider = model.provider;
    isSample = (s['sample'] as bool?) ?? false;
    Energy.unit = EnergyUnit.values.firstWhere((u) => u.name == s['energy'], orElse: () => EnergyUnit.kcal);
    appearance = ThemeMode.values.firstWhere((m) => m.name == s['appearance'], orElse: () => ThemeMode.dark);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    logPulse.dispose();
    healthRefresh.dispose();
    super.dispose();
  }
}

/// Makes [AppState] available to the widget tree and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to rebuilds (for callbacks).
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}

/// A food's weight, fibre and sugar per calorie, so an earlier fill-in applies to any portion.
class FoodDetailRates {
  const FoodDetailRates({this.gramsPerKcal, required this.fiberPerKcal, required this.sugarPerKcal});
  final double? gramsPerKcal;
  final double fiberPerKcal;
  final double sugarPerKcal;

  Map<String, dynamic> toJson() => {
    if (gramsPerKcal != null) 'g': gramsPerKcal,
    'fi': fiberPerKcal,
    'su': sugarPerKcal,
  };

  factory FoodDetailRates.fromJson(Map<String, dynamic> j) => FoodDetailRates(
    gramsPerKcal: (j['g'] as num?)?.toDouble(),
    fiberPerKcal: ((j['fi'] as num?) ?? 0).toDouble(),
    sugarPerKcal: ((j['su'] as num?) ?? 0).toDouble(),
  );
}
