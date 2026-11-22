import 'dart:io' show Platform;

import 'package:health/health.dart' as hc;

import '../models/nutrients.dart';
import '../models/sleep.dart';
import '../models/util.dart';
import 'health_service.dart';

HealthService createHealthService() =>
    (Platform.isIOS || Platform.isAndroid) ? _MobileHealthService() : UnsupportedHealthService();

class _MobileHealthService implements HealthService {
  final _health = hc.Health();
  bool _configured = false;

  static const _common = [
    hc.HealthDataType.ACTIVE_ENERGY_BURNED,
    hc.HealthDataType.WORKOUT,
    hc.HealthDataType.WEIGHT,
    hc.HealthDataType.BODY_FAT_PERCENTAGE,
    hc.HealthDataType.HEIGHT,
    hc.HealthDataType.NUTRITION,
    hc.HealthDataType.WATER,
    hc.HealthDataType.STEPS,
  ];

  // Sleep is stored differently: Apple Health keeps each stage as its own sample, while
  // Health Connect (where Samsung Health shares sleep) keeps whole sessions.
  static const _sleepIOS = [
    hc.HealthDataType.SLEEP_ASLEEP,
    hc.HealthDataType.SLEEP_LIGHT,
    hc.HealthDataType.SLEEP_DEEP,
    hc.HealthDataType.SLEEP_REM,
  ];
  static const _sleepAndroid = [hc.HealthDataType.SLEEP_SESSION];

  /// The type a logged night is written as: a whole session in Health Connect (which
  /// Samsung Health reads), plain "asleep" in Apple Health.
  static hc.HealthDataType get _sleepWrite =>
      Platform.isIOS ? hc.HealthDataType.SLEEP_ASLEEP : hc.HealthDataType.SLEEP_SESSION;

  List<hc.HealthDataType> get _read => [..._common, ...(Platform.isIOS ? _sleepIOS : _sleepAndroid)];

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
    hc.HealthDataType.BODY_FAT_PERCENTAGE: 'Body fat',
    hc.HealthDataType.HEIGHT: 'Height',
    hc.HealthDataType.NUTRITION: 'Nutrition',
    hc.HealthDataType.WATER: 'Water',
    hc.HealthDataType.SLEEP_ASLEEP: 'Sleep',
    hc.HealthDataType.SLEEP_LIGHT: 'Sleep',
    hc.HealthDataType.SLEEP_DEEP: 'Sleep',
    hc.HealthDataType.SLEEP_REM: 'Sleep',
    hc.HealthDataType.SLEEP_SESSION: 'Sleep',
  };

  @override
  List<String> get readNames => {for (final t in _read) _names[t]!}.toList();

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
          (t) =>
              (t == hc.HealthDataType.NUTRITION ||
                  t == hc.HealthDataType.WEIGHT ||
                  t == hc.HealthDataType.BODY_FAT_PERCENTAGE ||
                  t == hc.HealthDataType.WATER ||
                  t == _sleepWrite)
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
  Future<List<SleepNight>> sleep(DateTime from, DateTime to) async {
    // Nights can start the evening before [from], so look back half a day.
    final since = from.subtract(const Duration(hours: 14));
    if (Platform.isAndroid) {
      final points = await _points(hc.HealthDataType.SLEEP_SESSION, since, to);
      return [
        for (final p in points)
          if (p.dateTo.isAfter(p.dateFrom) && !p.dateTo.isBefore(from))
            SleepNight(
              start: p.dateFrom,
              end: p.dateTo,
              // The session's value is minutes asleep when the source records it.
              asleep: _numeric(p) > 0 ? Duration(minutes: _numeric(p).round()) : p.dateTo.difference(p.dateFrom),
            ),
      ];
    }
    final segments = <({DateTime start, DateTime end})>[];
    for (final t in _sleepIOS) {
      for (final p in await _points(t, since, to)) {
        segments.add((start: p.dateFrom, end: p.dateTo));
      }
    }
    return mergeSegments(segments).where((n) => !n.end.isBefore(from)).toList();
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

  // Health Connect stores body fat as 0–100; Apple Health as a fraction (0.2 for 20%).
  @override
  Future<List<WeightSample>> bodyFatHistory(DateTime since) async {
    final points = await _points(hc.HealthDataType.BODY_FAT_PERCENTAGE, since, DateTime.now());
    return points.map((p) {
      final v = _numeric(p);
      return WeightSample(p.dateFrom, v <= 1 ? v * 100 : v);
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Future<bool> saveBodyFat(double percent, DateTime at) async {
    await _ensure();
    try {
      return await _health.writeHealthData(
        value: Platform.isIOS ? percent / 100 : percent,
        type: hc.HealthDataType.BODY_FAT_PERCENTAGE,
        startTime: at,
        endTime: at,
        unit: hc.HealthDataUnit.PERCENT,
      );
    } catch (_) {
      return false;
    }
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
  Future<bool> saveSleep(DateTime start, DateTime end) async {
    await _ensure();
    try {
      return await _health.writeHealthData(
        value: end.difference(start).inMinutes.toDouble(),
        type: _sleepWrite,
        startTime: start,
        endTime: end,
        recordingMethod: hc.RecordingMethod.manual,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deleteSleep(DateTime start, DateTime end) async {
    await _ensure();
    try {
      await _health.delete(type: _sleepWrite, startTime: start, endTime: end);
    } catch (_) {}
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
