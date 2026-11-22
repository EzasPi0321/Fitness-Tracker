import 'util.dart';

/// A night logged by hand: when you went to sleep and when you woke.
class SleepEntry {
  SleepEntry({required this.id, required this.start, required this.end});
  final String id;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  /// A night belongs to the day you woke up, so "last night" shows on today.
  DateTime get day => startOfDay(end);

  Map<String, dynamic> toJson() => {'id': id, 'start': start.millisecondsSinceEpoch, 'end': end.millisecondsSinceEpoch};
  factory SleepEntry.fromJson(Map<String, dynamic> j) => SleepEntry(
    id: j['id'] as String,
    start: DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt()),
    end: DateTime.fromMillisecondsSinceEpoch((j['end'] as num).toInt()),
  );
}

/// One night of sleep from either source, as the screens show it.
class SleepNight {
  const SleepNight({required this.start, required this.end, required this.asleep, this.entryId});
  final DateTime start;
  final DateTime end;

  /// Time actually asleep. For a logged night it's the whole span; a health store may
  /// report less when it saw you awake in bed.
  final Duration asleep;

  /// Set when the night was logged by hand (so it can be edited or deleted).
  final String? entryId;

  bool get logged => entryId != null;
  DateTime get day => startOfDay(end);

  factory SleepNight.fromEntry(SleepEntry e) =>
      SleepNight(start: e.start, end: e.end, asleep: e.duration, entryId: e.id);
}

/// The longest night ending on each day: a nap shouldn't replace the night's sleep.
Map<DateTime, SleepNight> nightsByDay(Iterable<SleepNight> nights) {
  final out = <DateTime, SleepNight>{};
  for (final n in nights) {
    final cur = out[n.day];
    if (cur == null || n.asleep > cur.asleep) out[n.day] = n;
  }
  return out;
}

/// Joins sleep segments (Apple Health stores each stage separately) into nights: segments
/// less than 90 minutes apart belong to the same night.
List<SleepNight> mergeSegments(List<({DateTime start, DateTime end})> segments) {
  final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
  final nights = <SleepNight>[];
  DateTime? s, e;
  var asleep = Duration.zero;
  for (final seg in sorted) {
    if (!seg.end.isAfter(seg.start)) continue;
    if (e != null && seg.start.difference(e) <= const Duration(minutes: 90)) {
      final overlapStart = seg.start.isBefore(e) ? e : seg.start;
      if (seg.end.isAfter(overlapStart)) asleep += seg.end.difference(overlapStart);
      if (seg.end.isAfter(e)) e = seg.end;
    } else {
      if (s != null) nights.add(SleepNight(start: s, end: e!, asleep: asleep));
      s = seg.start;
      e = seg.end;
      asleep = seg.end.difference(seg.start);
    }
  }
  if (s != null) nights.add(SleepNight(start: s, end: e!, asleep: asleep));
  return nights;
}

/// "7 h 25 min", "8 h", "45 min".
String formatSleep(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}
