import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/body_fat.dart';
import '../models/util.dart';
import 'ai_vision.dart' show VisionException;
import 'platform_caps.dart';

/// Reads a body composition report or app screenshot on the phone itself (Google ML Kit):
/// no API key, no network. Finds the body fat percentage and, when printed, the weight.
class BodyReportOcr {
  static bool get isAvailable => PlatformCaps.isPhone;

  static Future<BodyReportReading> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final reading = parse(result.text);
      if (reading == null) {
        throw const VisionException(
          "Couldn’t find a body fat percentage. Crop the screenshot to the part that shows body fat %.",
        );
      }
      return reading;
    } finally {
      await recognizer.close();
    }
  }

  // ---- Parsing (pure, tested) ----

  static final _num = RegExp(r'(\d{1,3}(?:[.,]\d+)?)');

  /// Labels that name the percentage, most specific first. "Body fat mass" (kg) is not one.
  static final _percentLabels = [
    RegExp(r'\bpbf\b'),
    RegExp(r'percent(age)?\s+(of\s+)?body\s+fat'),
    RegExp(r'body\s*fat\s*(%|percent(age)?|pct)'),
    RegExp(r'\bbody\s*fat\b(?!\s*mass)'),
    RegExp(r'^fat\s*(%|percent)'),
  ];

  /// Returns null when no plausible body fat percentage (2–70%) is found.
  static BodyReportReading? parse(String text) {
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim().toLowerCase()).where((l) => l.isNotEmpty).toList();

    double? pct;
    for (final label in _percentLabels) {
      for (var i = 0; i < lines.length && pct == null; i++) {
        final m = label.firstMatch(lines[i]);
        if (m == null) continue;
        if (lines[i].contains('mass') && !lines[i].contains('%')) continue;
        // The value is on the same line after the label, or on one of the next two lines.
        final candidates = [
          lines[i].substring(m.end),
          if (i + 1 < lines.length) lines[i + 1],
          if (i + 2 < lines.length) lines[i + 2],
        ];
        for (final c in candidates) {
          final v = _percentIn(c);
          if (v != null) {
            pct = v;
            break;
          }
        }
      }
      if (pct != null) break;
    }
    if (pct == null) return null;

    return BodyReportReading(percent: pct, weightKg: _weight(lines), device: _device(lines));
  }

  /// A number in 2–70, preferring one written with a % sign; skips anything in kg or lb.
  static double? _percentIn(String s) {
    final withSign = RegExp(r'(\d{1,2}(?:[.,]\d+)?)\s*%').firstMatch(s);
    if (withSign != null) {
      final v = parseLenientNumber(withSign.group(1));
      if (v != null && v >= 2 && v <= 70) return v;
    }
    for (final m in _num.allMatches(s)) {
      final after = s.substring(m.end).trimLeft();
      if (after.startsWith('kg') || after.startsWith('lb')) continue;
      final v = parseLenientNumber(m.group(1));
      if (v != null && v >= 2 && v <= 70) return v;
    }
    return null;
  }

  static double? _weight(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!RegExp(r'^(body\s+)?weight\b').hasMatch(l)) continue;
      for (final c in [l, if (i + 1 < lines.length) lines[i + 1]]) {
        final m = RegExp(r'(\d{2,3}(?:[.,]\d+)?)\s*(kg|lbs?)\b').firstMatch(c);
        if (m == null) continue;
        final v = parseLenientNumber(m.group(1));
        if (v == null) continue;
        final kg = m.group(2)!.startsWith('lb') ? v / 2.20462 : v;
        if (kg >= 25 && kg <= 300) return (kg * 10).round() / 10;
      }
    }
    return null;
  }

  static String _device(List<String> lines) {
    for (final l in lines.take(8)) {
      for (final name in const ['inbody', 'tanita', 'withings', 'bodpod', 'dexa', 'dxa', 'garmin', 'renpho', 'eufy']) {
        if (l.contains(name)) {
          final m = RegExp('$name\\s*\\w*').firstMatch(l)!;
          final raw = m.group(0)!.trim();
          return raw
              .split(' ')
              .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
              .join(' ')
              .replaceFirst('Inbody', 'InBody')
              .replaceFirst('Dexa', 'DEXA')
              .replaceFirst('Dxa', 'DXA')
              .replaceFirst('Bodpod', 'BodPod');
        }
      }
    }
    return '';
  }
}
