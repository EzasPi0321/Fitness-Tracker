import 'util.dart';

/// What a session trained. Push / Pull / Legs is the split; Cardio and Sport cover the rest.
enum TrainingType {
  push('Push', 'Chest, shoulders, triceps'),
  pull('Pull', 'Back, biceps'),
  legs('Legs', 'Quads, hamstrings, glutes'),
  cardio('Cardio', 'Run, bike, row, classes'),
  sport('Sport', 'Games and matches');

  const TrainingType(this.label, this.detail);
  final String label;
  final String detail;
}

/// One visit to the gym (or a run, or a game).
class GymSession {
  GymSession({required this.id, required this.at, required this.type, this.minutes, this.note = ''});
  final String id;
  final DateTime at;
  final TrainingType type;
  final int? minutes;

  /// Optional detail, e.g. "Basketball" or "5 km run".
  final String note;

  DateTime get day => startOfDay(at);

  /// "Push · 60 min · Bench day".
  String get summary => [
    type.label,
    if (minutes != null && minutes! > 0) '$minutes min',
    if (note.trim().isNotEmpty) note.trim(),
  ].join(' · ');

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'type': type.name,
    if (minutes != null) 'min': minutes,
    if (note.isNotEmpty) 'note': note,
  };

  factory GymSession.fromJson(Map<String, dynamic> j) => GymSession(
    id: j['id'] as String,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    type: TrainingType.values.firstWhere((t) => t.name == j['type'], orElse: () => TrainingType.push),
    minutes: (j['min'] as num?)?.toInt(),
    note: (j['note'] as String?) ?? '',
  );
}

/// The Monday that starts [d]'s week.
DateTime weekStart(DateTime d) => addDays(startOfDay(d), -(d.weekday - 1));

/// A year at a glance: totals, the split by type, and week streaks.
class GymYear {
  GymYear(this.year, Iterable<GymSession> all)
    : sessions = [
        for (final s in all)
          if (s.at.year == year) s,
      ] {
    for (final s in sessions) {
      byType[s.type] = (byType[s.type] ?? 0) + 1;
      byDay[s.day] = (byDay[s.day] ?? 0) + 1;
    }
  }

  final int year;
  final List<GymSession> sessions;
  final Map<TrainingType, int> byType = {};
  final Map<DateTime, int> byDay = {};

  int get total => sessions.length;
  int get daysTrained => byDay.length;
  Set<DateTime> get activeWeeks => {for (final d in byDay.keys) weekStart(d)};

  /// Most weeks in a row with at least one session.
  int get bestWeekStreak {
    final weeks = activeWeeks.toList()..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final w in weeks) {
      run = (prev != null && addDays(prev, 7) == w) ? run + 1 : 1;
      if (run > best) best = run;
      prev = w;
    }
    return best;
  }

  TrainingType? get mostTrained {
    TrainingType? top;
    for (final e in byType.entries) {
      if (top == null || e.value > byType[top]!) top = e.key;
    }
    return top;
  }
}
