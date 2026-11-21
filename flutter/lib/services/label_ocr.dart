import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/nutrients.dart';
import '../models/util.dart';
import 'ai_vision.dart';
import 'platform_caps.dart';

/// Reads a nutrition facts panel on the phone itself (Google ML Kit), with no API key and no
/// network. Less forgiving than an AI model with blurry or curved labels, so the result always
/// goes to the review form.
class LabelOcr {
  static bool get isAvailable => PlatformCaps.isPhone;

  static Future<LabelReading> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final reading = parse(result.text);
      if (reading == null) {
        throw const VisionException(
          "Couldn’t find the nutrition numbers. Photograph just the nutrition panel, flat and in good light.",
        );
      }
      return reading;
    } finally {
      await recognizer.close();
    }
  }

  // ---- Parsing (pure, tested) ----

  /// A number, optionally with a decimal comma or point.
  static final _num = RegExp(r'(\d+(?:[.,]\d+)?)');

  /// Turns the recognised text of a nutrition panel into per-serving values. Handles US panels
  /// ("Calories 190", "Total Fat 16g") and EU panels ("Energy 2252 kJ / 539 kcal", per 100 g).
  /// Returns null when fewer than two of energy, protein, carbs and fat can be found.
  static LabelReading? parse(String text) {
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim().toLowerCase()).where((l) => l.isNotEmpty).toList();
    final all = lines.join('\n');

    // Energy: prefer a kcal figure, then "Calories N", then kJ converted.
    double? kcal;
    var printedKJ = false;
    // "kcal", or Australian "Cal" as in "540 kJ (129 Cal)".
    final kcalMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:kcal|cal)\b').firstMatch(all);
    if (kcalMatch != null) kcal = parseLenientNumber(kcalMatch.group(1));
    kcal ??= _valueAfter(lines, RegExp(r'^calories\b'), unit: '');
    if (kcal == null) {
      final kj = RegExp(r'(\d+(?:[.,]\d+)?)\s*kj').firstMatch(all);
      final v = kj == null ? null : parseLenientNumber(kj.group(1));
      if (v != null) {
        kcal = v / kilojoulesPerKcal;
        printedKJ = true;
      }
    }

    var fat = _valueAfter(lines, RegExp(r'^(total\s+)?fat\b'));
    var carbs = _valueAfter(lines, RegExp(r'^(total\s+)?carbohydrates?\b|^carbs\b'));
    var protein = _valueAfter(lines, RegExp(r'^proteins?\b'));

    // Table read column by column (common on Australian/NZ panels): names first, then
    // each column of values. Fill only what the line-by-line pass missed.
    if (kcal == null || fat == null || carbs == null || protein == null) {
      final cols = _columns(lines);
      if (kcal == null && cols.energyKcal != null) {
        kcal = cols.energyKcal;
        printedKJ = cols.energyWasKJ;
      }
      fat ??= cols.fat;
      carbs ??= cols.carbs;
      protein ??= cols.protein;
    }

    final found = [kcal, fat, carbs, protein].where((v) => v != null).length;
    if (found < 2) return null;

    // Serving size: "Serving size 2 tbsp (32g)" or "per serving (30 g)".
    String? servingText;
    double? servingGrams;
    for (final l in lines) {
      final m = RegExp(r'serving\s*size[:\s]*(.+)$').firstMatch(l);
      if (m != null) {
        servingText = m.group(1)!.trim();
        final g = RegExp(r'(\d+(?:[.,]\d+)?)\s*(g|ml)\b').firstMatch(servingText);
        if (g != null) servingGrams = parseLenientNumber(g.group(1));
        break;
      }
    }

    // A panel with a serving size is read per serving; otherwise values are per 100 g.
    final per100 = servingText == null && RegExp(r'(per|/)\s*100\s*(g|ml)').hasMatch(all);
    final n = Nutrients(calories: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0).sanitized;

    return LabelReading(
      name: '',
      brand: '',
      servingDescription: per100 ? '100 g' : (servingText ?? 'serving'),
      servingGrams: per100 ? 100 : servingGrams,
      perServing: n,
      // Read on-device: call it readable only when all four numbers were found.
      readable: found == 4,
      printedUnit: printedKJ ? EnergyUnit.kJ : EnergyUnit.kcal,
    );
  }

  static final _valueOnly = RegExp(r'^[<~]?\s*(\d+(?:[.,]\d+)?)\s*(g|mg|mcg|µg|kj|kcal|cal)?\b\s*(\([^)]*\))?\s*%?$');

  /// Pairs nutrient names with values when OCR returned them as separate runs of lines.
  /// The first value after the names belongs to the first name, and so on: that is the
  /// first column, which is per serving on Australian panels.
  static _Columns _columns(List<String> lines) {
    final names = <String>[];
    final values = <String>[];
    for (final raw in lines) {
      final l = raw.replaceFirst(RegExp(r'^[-–•*\s]+'), '');
      if (_valueOnly.hasMatch(l)) {
        if (names.isNotEmpty) values.add(l);
      } else if (!RegExp(r'\d').hasMatch(l) &&
          RegExp(
            r'^(energy|protein|fat|saturated|trans|carbohydrate|sugars?|dietary|fibre|fiber|sodium|salt|calories|cholesterol|potassium|calcium|polyunsaturated|monounsaturated)',
          ).hasMatch(l)) {
        names.add(l);
      }
    }
    final c = _Columns();
    for (var i = 0; i < names.length && i < values.length; i++) {
      final name = names[i];
      final m = _valueOnly.firstMatch(values[i])!;
      final v = parseLenientNumber(m.group(1));
      if (v == null) continue;
      if (name.startsWith('energy') || name.startsWith('calories')) {
        final cal = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:kcal|cal)\b').firstMatch(values[i]);
        if (cal != null) {
          c.energyKcal = parseLenientNumber(cal.group(1));
        } else if (m.group(2) == 'kj') {
          c.energyKcal = v / kilojoulesPerKcal;
          c.energyWasKJ = true;
        } else {
          c.energyKcal = v;
        }
      } else if (RegExp(r'^fat\b').hasMatch(name)) {
        c.fat ??= v;
      } else if (name.startsWith('carbohydrate')) {
        c.carbs ??= v;
      } else if (name.startsWith('protein')) {
        c.protein ??= v;
      }
    }
    return c;
  }

  /// The first gram value on the line that starts with [label], or on one of the next two
  /// lines (OCR often splits a table's label and value columns). Skips sub-rows such as
  /// "Saturated Fat" or "of which sugars" because they don't start with the label.
  static double? _valueAfter(List<String> lines, RegExp label, {String unit = 'g'}) {
    final withUnit = RegExp(r'(\d+(?:[.,]\d+)?)\s*' + unit + r'\b');
    for (var i = 0; i < lines.length; i++) {
      if (!label.hasMatch(lines[i])) continue;
      for (var j = i; j < lines.length && j <= i + 2; j++) {
        final line = j == i ? lines[j].replaceFirst(label, '') : lines[j];
        // A following line that starts with a word is the next nutrient, not this value.
        if (j > i && RegExp(r'^[a-z]').hasMatch(line)) break;
        final m = unit.isEmpty || j > i ? _num.firstMatch(line) : withUnit.firstMatch(line);
        if (m != null) return parseLenientNumber(m.group(1));
      }
    }
    return null;
  }
}

class _Columns {
  double? energyKcal;
  bool energyWasKJ = false;
  double? fat;
  double? carbs;
  double? protein;
}
