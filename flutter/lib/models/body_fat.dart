import 'profile.dart';

/// Where a body fat number came from. Measured values (a report, a scale, a typed reading)
/// are drawn solid; a photo estimate is drawn hollow, with its range, because it's a guess.
enum BodyFatSource {
  typed('Typed in'),
  report('Read from a report'),
  photo('Estimated from a photo'),
  health('From Health');

  const BodyFatSource(this.label);
  final String label;

  bool get isEstimate => this == BodyFatSource.photo;
}

class BodyFatEntry {
  BodyFatEntry({
    required this.id,
    required this.at,
    required this.percent,
    required this.source,
    this.low,
    this.high,
    this.device,
  });

  final String id;
  final DateTime at;
  final double percent;
  final BodyFatSource source;

  /// The likely range, for photo estimates.
  final double? low;
  final double? high;

  /// "InBody 570", "Withings Body+"… when a report said.
  final String? device;

  /// Fat-free mass for a body weight.
  double leanKg(double weightKg) => weightKg * (1 - percent / 100);

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'pct': percent,
    'src': source.name,
    if (low != null) 'lo': low,
    if (high != null) 'hi': high,
    if (device != null && device!.isNotEmpty) 'dev': device,
  };

  factory BodyFatEntry.fromJson(Map<String, dynamic> j) => BodyFatEntry(
    id: j['id'] as String,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    percent: (j['pct'] as num).toDouble(),
    source: BodyFatSource.values.firstWhere((s) => s.name == j['src'], orElse: () => BodyFatSource.typed),
    low: (j['lo'] as num?)?.toDouble(),
    high: (j['hi'] as num?)?.toDouble(),
    device: j['dev'] as String?,
  );
}

/// The American Council on Exercise's body fat categories. Shown as a guide on a scale, not
/// as a verdict: the same number means different things for different bodies.
enum BodyFatBand {
  essential('Essential'),
  athletic('Athletic'),
  fitness('Fitness'),
  average('Average'),
  above('Above average');

  const BodyFatBand(this.label);
  final String label;

  /// Lower edge of each band, then the scale's top. Women carry more essential fat.
  static List<double> edges(BiologicalSex sex) =>
      sex == BiologicalSex.male ? const [2, 6, 14, 18, 25, 40] : const [10, 14, 21, 25, 32, 47];

  static BodyFatBand of(double percent, BiologicalSex sex) {
    final e = edges(sex);
    for (var i = BodyFatBand.values.length - 1; i > 0; i--) {
      if (percent >= e[i]) return BodyFatBand.values[i];
    }
    return BodyFatBand.essential;
  }
}

/// What a report or a body-composition app screenshot said.
class BodyReportReading {
  const BodyReportReading({
    required this.percent,
    this.weightKg,
    this.leanKg,
    this.muscleKg,
    this.measuredOn,
    this.device = '',
    this.readable = true,
    this.answeredBy = '',
  });

  final double percent;
  final double? weightKg;
  final double? leanKg;
  final double? muscleKg;
  final DateTime? measuredOn;
  final String device;
  final bool readable;

  /// Model id, or '' when read on the phone.
  final String answeredBy;

  BodyReportReading withModel(String id) => BodyReportReading(
    percent: percent,
    weightKg: weightKg,
    leanKg: leanKg,
    muscleKg: muscleKg,
    measuredOn: measuredOn,
    device: device,
    readable: readable,
    answeredBy: id,
  );
}

/// A visual estimate from a photo: a best guess inside a range.
class BodyFatEstimate {
  const BodyFatEstimate({
    required this.percent,
    required this.low,
    required this.high,
    required this.confidence,
    this.notes = '',
    this.answeredBy = '',
  });

  final double percent;
  final double low;
  final double high;
  final double confidence;
  final String notes;
  final String answeredBy;

  /// Wide ranges and low confidence are worth a second, more careful look.
  bool get needsCarefulLook => confidence < 0.6 || high - low > 8;

  BodyFatEstimate withModel(String id) =>
      BodyFatEstimate(percent: percent, low: low, high: high, confidence: confidence, notes: notes, answeredBy: id);
}
