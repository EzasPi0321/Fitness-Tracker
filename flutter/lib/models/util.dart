import 'package:intl/intl.dart';

/// Postel's law: accept messy number input, give back a clean value.
///
/// Understands "6,3", "1.5", " 150 kcal", "1 1/2", "1/2", "½", "1,234.5", "1.234,5" and "~200".
/// Returns null when there is no number at all.
double? parseLenientNumber(String? raw) {
  if (raw == null) return null;
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;

  const vulgar = {'¼': 0.25, '½': 0.5, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125};
  double extra = 0;
  for (final e in vulgar.entries) {
    if (s.contains(e.key)) {
      extra += e.value;
      s = s.replaceAll(e.key, ' ');
    }
  }

  // Mixed or plain fraction: "1 1/2", "3/4".
  final frac = RegExp(r'(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)').firstMatch(s);
  if (frac != null) {
    final whole = double.tryParse(frac.group(1) ?? '0') ?? 0;
    final num = double.parse(frac.group(2)!);
    final den = double.parse(frac.group(3)!);
    if (den == 0) return null;
    return whole + num / den + extra;
  }

  final match = RegExp(r'-?\d[\d.,\s]*').firstMatch(s);
  if (match == null) return extra > 0 ? extra : null;
  var n = match.group(0)!.replaceAll(RegExp(r'\s'), '');
  n = n.replaceFirst(RegExp(r'[.,]+$'), '');

  final lastDot = n.lastIndexOf('.');
  final lastComma = n.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    // Whichever separator comes last is the decimal point.
    if (lastComma > lastDot) {
      n = n.replaceAll('.', '').replaceAll(',', '.');
    } else {
      n = n.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    // "1,234" (thousands) vs "6,3" (decimal comma).
    final parts = n.split(',');
    final thousands = parts.length > 1 && parts.skip(1).every((p) => p.length == 3) && parts.first.length <= 3;
    n = thousands ? n.replaceAll(',', '') : n.replaceAll(',', '.');
    if ('.'.allMatches(n).length > 1) return null;
  } else if ('.'.allMatches(n).length > 1) {
    n = n.replaceAll('.', ''); // "1.234.567"
  }
  final v = double.tryParse(n);
  if (v == null || !v.isFinite) return null;
  return v + extra;
}

final _whole = NumberFormat.decimalPattern('en_US')..maximumFractionDigits = 0;
final _one = NumberFormat('#,##0.0', 'en_US');

/// "1,234" — rounded.
String whole(double v) => _whole.format(v.isFinite ? v.round() : 0);

/// "12.3"
String oneDecimal(double v) => _one.format(v.isFinite ? v : 0);

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second);
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Timestamp to use when logging food for `day`: "now" for today, midday for other days.
DateTime logTimestamp(DateTime day) {
  final now = DateTime.now();
  if (sameDay(day, now)) return now;
  return DateTime(day.year, day.month, day.day, 12);
}

String dayTitle(DateTime day) {
  final today = startOfDay(DateTime.now());
  if (sameDay(day, today)) return 'Today';
  if (sameDay(day, addDays(today, -1))) return 'Yesterday';
  return DateFormat('EEE, MMM d').format(day);
}

enum EnergyUnit { kcal, kJ }

const kilojoulesPerKcal = 4.184;

/// Energy is stored in kcal everywhere; this converts for display and input in the unit the
/// user picked in Settings.
abstract final class Energy {
  static EnergyUnit unit = EnergyUnit.kcal;

  static bool get isKJ => unit == EnergyUnit.kJ;
  static String get label => isKJ ? 'kJ' : 'kcal';

  /// Field name: "Calories" reads oddly next to kJ.
  static String get fieldName => isKJ ? 'Energy' : 'Calories';

  static double toDisplay(double kcal) => isKJ ? kcal * kilojoulesPerKcal : kcal;
  static double fromDisplay(double value) => isKJ ? value / kilojoulesPerKcal : value;

  /// "1,234 kcal" or "5,163 kJ".
  static String format(double kcal) => '${whole(toDisplay(kcal))} $label';
}
