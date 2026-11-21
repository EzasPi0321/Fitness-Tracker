import 'dart:io' show Platform;

import 'package:health/health.dart' as hc;

import '../models/nutrients.dart';
import '../models/util.dart';
import 'health_service.dart';

HealthService createHealthService() =>
    (Platform.isIOS || Platform.isAndroid) ? _MobileHealthService() : UnsupportedHealthService();

class _MobileHealthService implements HealthService {
  final _health = hc.Health();
  bool _configured = false;

  static const _read = [
    hc.HealthDataType.ACTIVE_ENERGY_BURNED,
    hc.HealthDataType.WORKOUT,
    hc.HealthDataType.WEIGHT,
    hc.HealthDataType.HEIGHT,
    hc.HealthDataType.NUTRITION,
    hc.HealthDataType.WATER,
    hc.HealthDataType.STEPS,
  ];

  @override
  bool get isSupported => true;

  // On Samsung phones, Samsung Health shares its data through Health Connect.
  @override
  String get storeName => Platform.isIOS ? 'Apple Health' : 'Samsung Health / Health Connect';

  Future<void> _ensure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  static const _names = {
    hc.HealthDataType.STEPS: 'Steps',
    hc.HealthDataType.ACTIVE_ENERGY_BURNED: 'Active calories',
    hc.HealthDataType.WORKOUT: 'Exercise',
    hc.HealthDataType.WEIGHT: 'Weight',
    hc.HealthDataType.HEIGHT: 'Height',
    hc.HealthDataType.NUTRITION: 'Nutrition',
    hc.HealthDataType.WATER: 'Water',
  };

  @override
  List<String> get readNames => [for (final t in _read) _names[t]!];

  @override
  Future<bool> requestAuthorization() async {
    await _ensure();
    if (Platform.isAndroid) {
      final available = await _health.isHealthConnectAvailable();
      if (!available) {
        await _health.installHealthConnect();
        return false;
      }
    }
    final permissions = _read
        .map(
          (t) => (t == hc.HealthDataType.NUTRITION || t == hc.HealthDataType.WEIGHT || t == hc.HealthDataType.WATER)
              ? hc.HealthDataAccess.READ_WRITE
              : hc.HealthDataAccess.READ,
        )
        .toList();
    bool all;
    try {
      all = await _health.requestAuthorization(_read, permissions: permissions);
    } catch (_) {
      all = false;
    }
    // Apple Health never says what was allowed; once the sheet has been shown, carry on.
    if (Platform.isIOS) return true;
    if (all) return true;
    // Health Connect: allowing only some types is fine. Use whatever was granted.
    final granted = await grantedReads();
    return granted != null && granted.isNotEmpty;
  }

  @override
  Future<Set<String>?> grantedReads() async {
    if (!Platform.isAndroid) return null;
    await _ensure();
    final granted = <String>{};
    for (final t in _read) {
      try {
        if (await _health.hasPermissions([t], permissions: [hc.HealthDataAccess.READ]) == true) granted.add(_names[t]!);
      } catch (_) {}
    }
    return granted;
  }

  Future<List<hc.HealthDataPoint>> _points(hc.HealthDataType type, DateTime from, DateTime to) async {
    await _ensure();
    try {
      final points = await _health.getHealthDataFromTypes(types: [type], startTime: from, endTime: to);
      return _health.removeDuplicates(points);
    } catch (_) {
      return const [];
    }
  }

  static double _numeric(hc.HealthDataPoint p) {
    final v = p.value;
    return v is hc.NumericHealthValue ? v.numericValue.toDouble() : 0;
  }

  @override
  Future<int?> steps(DateTime day) async {
    await _ensure();
    final start = startOfDay(day);
    final end = sameDay(day, DateTime.now()) ? DateTime.now() : addDays(start, 1);
    int? total;
    try {
      total = await _health.getTotalStepsInInterval(start, end);
    } catch (_) {}
    if (total != null && total > 0) return total;
    // Fallback: add up the individual step records (some sources only show up this way).
    final points = await _points(hc.HealthDataType.STEPS, start, end);
    if (points.isEmpty) return total;
    return points.fold<double>(0, (a, p) => a + _numeric(p)).round();
  }

  @override
  Future<double> activeEnergy(DateTime day) async {
    final start = startOfDay(day);
    final points = await _points(hc.HealthDataType.ACTIVE_ENERGY_BURNED, start, addDays(start, 1));
    return points.fold<double>(0, (a, p) => a + _numeric(p));
  }

  @override
  Future<Map<DateTime, double>> dailyActiveEnergy(DateTime from, DateTime to) async {
    final points = await _points(hc.HealthDataType.ACTIVE_ENERGY_BURNED, startOfDay(from), to);
    final result = <DateTime, double>{};
    for (final p in points) {
      final day = startOfDay(p.dateFrom);
      result[day] = (result[day] ?? 0) + _numeric(p);
    }
    return result;
  }

  @override
  Future<List<WorkoutSummary>> workouts(DateTime day) async {
    final start = startOfDay(day);
    final points = await _points(hc.HealthDataType.WORKOUT, start, addDays(start, 1));
    return points.map((p) {
      final v = p.value;
      String name = 'Workout';
      double? kcal;
      if (v is hc.WorkoutHealthValue) {
        name = _workoutName(v.workoutActivityType.name);
        kcal = v.totalEnergyBurned?.toDouble();
      }
      return WorkoutSummary(
        name: name,
        start: p.dateFrom,
        duration: p.dateTo.difference(p.dateFrom),
        activeCalories: kcal,
      );
    }).toList()..sort((a, b) => b.start.compareTo(a.start));
  }

  static String _workoutName(String raw) {
    final words = raw.toLowerCase().split('_').where((w) => w.isNotEmpty);
    final s = words.join(' ');
    return s.isEmpty ? 'Workout' : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Future<List<WeightSample>> weightHistory(DateTime since) async {
    final points = await _points(hc.HealthDataType.WEIGHT, since, DateTime.now());
    return points.map((p) => WeightSample(p.dateFrom, _numeric(p))).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Future<HealthSnapshot> snapshot() async {
    final since = DateTime.now().subtract(const Duration(days: 3650));
    final w = await _points(hc.HealthDataType.WEIGHT, since, DateTime.now());
    final h = await _points(hc.HealthDataType.HEIGHT, since, DateTime.now());
    double? latest(List<hc.HealthDataPoint> ps) {
      if (ps.isEmpty) return null;
      ps.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
      return _numeric(ps.last);
    }

    final heightM = latest(h);
    return HealthSnapshot(weightKg: latest(w), heightCm: heightM == null ? null : heightM * 100);
  }

  static hc.MealType _meal(String meal) => switch (meal) {
    'breakfast' => hc.MealType.BREAKFAST,
    'lunch' => hc.MealType.LUNCH,
    'dinner' => hc.MealType.DINNER,
    _ => hc.MealType.SNACK,
  };

  // Health Connect needs end > start, so each food record spans one minute.
  @override
  Future<bool> saveFood({
    required String name,
    required String meal,
    required Nutrients nutrients,
    required DateTime at,
  }) async {
    await _ensure();
    try {
      return await _health.writeMeal(
        mealType: _meal(meal),
        startTime: at,
        endTime: at.add(const Duration(minutes: 1)),
        caloriesConsumed: nutrients.calories,
        protein: nutrients.protein,
        carbohydrates: nutrients.carbs,
        fatTotal: nutrients.fat,
        name: name,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deleteFood(DateTime at) async {
    await _ensure();
    try {
      await _health.delete(
        type: hc.HealthDataType.NUTRITION,
        startTime: at,
        endTime: at.add(const Duration(minutes: 1)),
      );
    } catch (_) {}
  }

  @override
  Future<bool> saveWeight(double kilograms, DateTime at) async {
    await _ensure();
    try {
      return await _health.writeHealthData(
        value: kilograms,
        type: hc.HealthDataType.WEIGHT,
        startTime: at,
        endTime: at,
        unit: hc.HealthDataUnit.KILOGRAM,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> saveWater(double ml, DateTime at) async {
    await _ensure();
    try {
      return await _health.writeHealthData(
        value: ml / 1000,
        type: hc.HealthDataType.WATER,
        startTime: at,
        endTime: at.add(const Duration(minutes: 1)),
        unit: hc.HealthDataUnit.LITER,
      );
    } catch (_) {
      return false;
    }
  }
}
