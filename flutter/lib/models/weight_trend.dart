import 'dart:math' as math;

/// A smoothed weight line that ignores day-to-day water swings.
///
/// Each day the trend moves 10% of the way toward the latest weigh-in (an exponential moving
/// average, as in The Hacker's Diet). A gap of several days counts as several days of
/// movement, so a weigh-in after a week away pulls harder than one the next morning.
/// Points are (date, kg), oldest first; the result has one trend value per weigh-in.
List<(DateTime, double)> weightTrend(List<(DateTime, double)> points, {double perDay = 0.1}) {
  if (points.isEmpty) return const [];
  final sorted = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
  var trend = sorted.first.$2;
  final out = <(DateTime, double)>[(sorted.first.$1, trend)];
  for (var i = 1; i < sorted.length; i++) {
    final days = sorted[i].$1.difference(sorted[i - 1].$1).inMinutes / 1440;
    // Same-day weigh-ins still count a little; long gaps are capped at 30 days.
    final k = 1 - math.pow(1 - perDay, days.clamp(0.25, 30));
    trend += k * (sorted[i].$2 - trend);
    out.add((sorted[i].$1, trend));
  }
  return out;
}

/// How much the trend moved over the last week, in kg (negative is a loss). Null until the
/// trend covers at least a week.
double? weeklyTrendChange(List<(DateTime, double)> trend) {
  if (trend.length < 2) return null;
  final last = trend.last;
  final weekAgo = last.$1.subtract(const Duration(days: 7));
  if (trend.first.$1.isAfter(weekAgo)) return null;
  // The trend value as it stood a week ago: the last point on or before that day.
  final then = trend.lastWhere((p) => !p.$1.isAfter(weekAgo));
  return last.$2 - then.$2;
}
