import 'package:fittrack/data/app_state.dart';
import 'package:fittrack/models/body_fat.dart';
import 'package:fittrack/models/profile.dart';
import 'package:fittrack/screens/progress/body_fat.dart';
import 'package:fittrack/services/ai_vision.dart';
import 'package:fittrack/services/body_report_ocr.dart';
import 'package:fittrack/services/health_service.dart' show WeightSample;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('on-phone report reading', () {
    test('InBody: takes PBF, not body fat mass', () {
      const text = '''
InBody 570
Body Composition Analysis
Weight 72.4 kg
Body Fat Mass 18.5 kg
Skeletal Muscle Mass 30.1 kg
Obesity Analysis
PBF (Percent Body Fat) 25.6 %
''';
      final r = BodyReportOcr.parse(text)!;
      expect(r.percent, 25.6);
      expect(r.weightKg, 72.4);
      expect(r.device, 'InBody 570');
    });

    test('scale app screenshot with the value on the next line', () {
      const text = 'Withings\nBody fat\n21,3%\nWeight\n160.2 lb';
      final r = BodyReportOcr.parse(text)!;
      expect(r.percent, 21.3);
      expect(r.weightKg, closeTo(72.7, 0.1));
    });

    test('nothing usable', () {
      expect(BodyReportOcr.parse('Body fat mass 18 kg\nWeight 70 kg'), isNull);
      expect(BodyReportOcr.parse('Steps 9,000'), isNull);
    });
  });

  group('AI answers', () {
    test('report: date in the future is dropped, numbers kept', () {
      final r = AIVisionService.decodeReport(
        '{"body_fat_percent": 18.2, "weight_kg": 80, "lean_mass_kg": 65.4, "muscle_mass_kg": 0, '
        '"measured_on": "2099-01-01", "device": "DEXA", "readable": true}',
      );
      expect(r.percent, 18.2);
      expect(r.weightKg, 80);
      expect(r.muscleKg, isNull);
      expect(r.measuredOn, isNull);
      expect(r.device, 'DEXA');
    });

    test('report without a percentage is an error', () {
      expect(
        () => AIVisionService.decodeReport('{"body_fat_percent": 0, "readable": false}'),
        throwsA(isA<VisionException>()),
      );
    });

    test('photo: range widened to 4 points and kept around the guess', () {
      final e = AIVisionService.decodeEstimate(
        '{"usable": true, "estimate_percent": 20, "low_percent": 21, "high_percent": 22, "confidence": 0.8, "notes": ""}',
      );
      expect(e.low, lessThanOrEqualTo(20));
      expect(e.high, greaterThanOrEqualTo(20));
      expect(e.high - e.low, greaterThanOrEqualTo(4));
    });

    test('photo: unusable gives the model’s reason', () {
      expect(
        () => AIVisionService.decodeEstimate(
          '{"usable": false, "estimate_percent": 0, "low_percent": 0, "high_percent": 0, "confidence": 0, '
          '"notes": "The photo is too dark."}',
        ),
        throwsA(isA<VisionException>().having((e) => e.message, 'message', 'The photo is too dark.')),
      );
    });
  });

  test('bands differ by sex', () {
    expect(BodyFatBand.of(20, BiologicalSex.male), BodyFatBand.average);
    expect(BodyFatBand.of(20, BiologicalSex.female), BodyFatBand.athletic);
    expect(BodyFatBand.of(1, BiologicalSex.male), BodyFatBand.essential);
    expect(BodyFatBand.of(45, BiologicalSex.female), BodyFatBand.above);
  });

  test('entries round-trip, and Health fills only days without a reading', () {
    final e = BodyFatEntry(
      id: 'a',
      at: DateTime(2026, 11, 1, 9),
      percent: 24,
      source: BodyFatSource.photo,
      low: 22,
      high: 26,
    );
    final back = BodyFatEntry.fromJson(e.toJson());
    expect(back.source, BodyFatSource.photo);
    expect(back.low, 22);
    final merged = mergeBodyFat(
      [e],
      [WeightSample(DateTime(2026, 11, 1, 7), 23), WeightSample(DateTime(2026, 11, 5), 22)],
    );
    expect(merged.map((m) => m.percent), [24, 22]);
    expect(merged.last.source, BodyFatSource.health);
  });

  test('undo takes back the reading and the weigh-in its report added', () async {
    final s = AppState();
    final e = BodyFatEntry(id: 'x', at: DateTime(2026, 11, 2, 9), percent: 25, source: BodyFatSource.report);
    final before = s.weights.length;
    await s.logBodyFat(e, weightKg: 71.5);
    expect(s.bodyFat, hasLength(1));
    expect(s.weights.length, before + 1);
    s.undoBodyFat('x');
    expect(s.bodyFat, isEmpty);
    expect(s.weights.length, before);
  });
}
