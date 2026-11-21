import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

import '../models/food.dart';
import '../models/nutrients.dart';
import '../models/profile.dart';
import '../models/util.dart';
import '../services/ai_vision.dart';
import '../services/health_service.dart';
import '../services/key_store.dart';
import '../services/updates.dart';
import 'sample_data.dart';
import 'storage.dart';

String newId() {
  final r = Random();
  return DateTime.now().microsecondsSinceEpoch.toRadixString(36) + r.nextInt(1 << 32).toRadixString(36);
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
      if (last != null && DateTime.now().difference(last) < const Duration(hours: 20)) return availableUpdate;
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

  /// Set by the user; when null the goal follows body weight.
  double? waterGoalOverride;

  int stepGoal = 10000;

  /// Example step counts shown with sample data (no health store on desktop).
  final Map<DateTime, int> sampleSteps = {};

  /// Black by default; light and system are options in Settings.
  ThemeMode appearance = ThemeMode.dark;

  /// kcal or kJ for everything shown and typed; storage is always kcal.
  EnergyUnit get energyUnit => Energy.unit;

  bool healthEnabled = false;
  bool addActiveEnergy = false;
  VisionProvider visionProvider = VisionProvider.claude;
  String visionModel = VisionProvider.claude.defaultModel;

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
    if (profile == null && seedSampleIfEmpty) loadSampleData(save: false);
    if (isSample && sampleSteps.isEmpty) sampleSteps.addAll(SampleData.generate().steps);
    loaded = true;
    unawaited(checkForUpdates());
    notifyListeners();
  }

  // ---- Queries ----

  List<FoodEntry> entriesOn(DateTime day) {
    final list = entries.where((e) => sameDay(e.consumedAt, day)).toList()
      ..sort((a, b) => a.consumedAt.compareTo(b.consumedAt));
    return list;
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
      sampleSteps.clear();
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

  Future<void> addWeight(double kilograms, DateTime date) async {
    final latest = weights.isEmpty ? null : weightsByDate.last.date;
    weights.add(WeightEntry(id: newId(), date: date, kilograms: kilograms));
    if (latest == null || !date.isBefore(latest)) profile?.weightKg = kilograms;
    _changed();
    if (_syncHealth) await health.saveWeight(kilograms, date);
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
      healthError = '${health.storeName} access wasn\'t granted. You can allow it in the ${health.storeName} app.';
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
    visionModel = m.id;
    visionProvider = m.provider;
    _changed();
  }

  bool get _syncHealth => healthEnabled && health.isSupported;

  // ---- Sample data ----

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
    'settings': {
      'health': healthEnabled,
      'addActive': addActiveEnergy,
      'provider': visionProvider.name,
      'model': visionModel,
      'sample': isSample,
      'appearance': appearance.name,
      'energy': Energy.unit.name,
      'waterGoal': waterGoalOverride,
      'stepGoal': stepGoal,
      'lastUpdateCheck': _lastUpdateCheck?.millisecondsSinceEpoch,
      'dismissedUpdate': _dismissedUpdateBuild,
    },
  };

  void _fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) =>
        (j[k] is List ? j[k] as List : const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
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
    final s = j['settings'] is Map ? (j['settings'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    healthEnabled = (s['health'] as bool?) ?? false;
    waterGoalOverride = (s['waterGoal'] as num?)?.toDouble();
    stepGoal = ((s['stepGoal'] as num?) ?? 10000).toInt();
    final lastCheck = s['lastUpdateCheck'] as num?;
    _lastUpdateCheck = lastCheck == null ? null : DateTime.fromMillisecondsSinceEpoch(lastCheck.toInt());
    _dismissedUpdateBuild = (s['dismissedUpdate'] as num?)?.toInt();
    addActiveEnergy = (s['addActive'] as bool?) ?? false;
    visionProvider = VisionProvider.values.firstWhere(
      (v) => v.name == s['provider'],
      orElse: () => VisionProvider.gemini,
    );
    final model = AiModel.byId((s['model'] as String?) ?? AiModel.all.first.id);
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
