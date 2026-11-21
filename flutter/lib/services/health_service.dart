import '../models/nutrients.dart';
import 'health_service_stub.dart' if (dart.library.io) 'health_service_io.dart' as impl;

class WorkoutSummary {
  const WorkoutSummary({required this.name, required this.start, required this.duration, this.activeCalories});
  final String name;
  final DateTime start;
  final Duration duration;
  final double? activeCalories;
}

class WeightSample {
  const WeightSample(this.date, this.kilograms);
  final DateTime date;
  final double kilograms;
}

class HealthSnapshot {
  const HealthSnapshot({this.heightCm, this.weightKg});
  final double? heightCm;
  final double? weightKg;
}

/// Apple Health (iOS) and Health Connect (Android). On web and desktop every call is a no-op.
abstract class HealthService {
  factory HealthService() => impl.createHealthService();

  /// Whether this platform has a health store at all.
  bool get isSupported;

  /// "Apple Health" or "Samsung Health / Health Connect".
  String get storeName;

  Future<bool> requestAuthorization();
  Future<double> activeEnergy(DateTime day);

  /// Steps for the day, or null when they can't be read.
  Future<int?> steps(DateTime day);
  Future<Map<DateTime, double>> dailyActiveEnergy(DateTime from, DateTime to);
  Future<List<WorkoutSummary>> workouts(DateTime day);
  Future<List<WeightSample>> weightHistory(DateTime since);
  Future<HealthSnapshot> snapshot();

  /// Saves a logged food as a nutrition record. Returns true on success.
  Future<bool> saveFood({
    required String name,
    required String meal,
    required Nutrients nutrients,
    required DateTime at,
  });
  Future<void> deleteFood(DateTime at);
  Future<bool> saveWeight(double kilograms, DateTime at);
  Future<bool> saveWater(double ml, DateTime at);
}

/// No health store (web, Windows, tests).
class UnsupportedHealthService implements HealthService {
  @override
  bool get isSupported => false;
  @override
  String get storeName => 'Health';
  @override
  Future<bool> requestAuthorization() async => false;
  @override
  Future<double> activeEnergy(DateTime day) async => 0;
  @override
  Future<int?> steps(DateTime day) async => null;
  @override
  Future<Map<DateTime, double>> dailyActiveEnergy(DateTime from, DateTime to) async => const {};
  @override
  Future<List<WorkoutSummary>> workouts(DateTime day) async => const [];
  @override
  Future<List<WeightSample>> weightHistory(DateTime since) async => const [];
  @override
  Future<HealthSnapshot> snapshot() async => const HealthSnapshot();
  @override
  Future<bool> saveFood({
    required String name,
    required String meal,
    required Nutrients nutrients,
    required DateTime at,
  }) async => false;
  @override
  Future<void> deleteFood(DateTime at) async {}
  @override
  Future<bool> saveWeight(double kilograms, DateTime at) async => false;
  @override
  Future<bool> saveWater(double ml, DateTime at) async => false;
}
