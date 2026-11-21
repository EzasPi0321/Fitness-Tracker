import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/nutrients.dart';
import '../models/util.dart';
import 'open_food_facts.dart' show lossyDouble;

enum VisionProvider {
  claude('Claude', 'Anthropic Claude', AiModel.smartId),
  gemini('Gemini', 'Google Gemini', 'gemini-2.5-flash'),
  openAI('OpenAI', 'OpenAI', 'gpt-4o-mini');

  const VisionProvider(this.shortName, this.displayName, this.defaultModel);
  final String shortName;
  final String displayName;
  final String defaultModel;

  String get keyName => 'apiKey.$name';

  /// What the key field is called, so it's clear which company's key goes there.
  String get keyLabel => switch (this) {
    VisionProvider.claude => 'Anthropic API key',
    VisionProvider.gemini => 'Google AI Studio API key',
    VisionProvider.openAI => 'OpenAI API key',
  };
}

/// The models offered in Settings. Picking one also picks its provider.
class AiModel {
  const AiModel(this.id, this.label, this.provider);
  final String id;
  final String label;
  final VisionProvider provider;

  /// Not a real model: Haiku first, and Opus only when Haiku isn't sure. The default.
  static const smartId = 'claude-smart';
  static const quickModel = 'claude-haiku-5-5';
  static const carefulModel = 'claude-opus-5-5';

  bool get isSmart => id == smartId;

  static const all = [
    AiModel(smartId, 'Smart (Haiku, Opus when unsure)', VisionProvider.claude),
    AiModel('claude-opus-5-5', 'Claude Opus 5.5', VisionProvider.claude),
    AiModel('claude-sonnet-5-5', 'Claude Sonnet 5.5', VisionProvider.claude),
    AiModel('claude-haiku-5-5', 'Claude Haiku 5.5', VisionProvider.claude),
    AiModel('gemini-2.5-pro', 'Gemini 2.5 Pro', VisionProvider.gemini),
    AiModel('gemini-2.5-flash', 'Gemini 2.5 Flash', VisionProvider.gemini),
    AiModel('gpt-4o', 'GPT-4o', VisionProvider.openAI),
    AiModel('gpt-4o-mini', 'GPT-4o mini', VisionProvider.openAI),
  ];

  static AiModel byId(String id) => all.firstWhere((m) => m.id == id, orElse: () => all.first);

  /// Display name for a real model id (what actually answered).
  static String nameOf(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => AiModel(id, id, VisionProvider.claude)).label;
}

class DetectedFood {
  DetectedFood({
    required this.name,
    required this.grams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.confidence,
    this.fiber = 0,
    this.sugar = 0,
  });

  String name;
  double grams;
  double calories;
  double protein;
  double carbs;
  double fat;
  double fiber;
  double sugar;
  double confidence;

  Nutrients get nutrients =>
      Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar);
}

class MealAnalysis {
  MealAnalysis({required this.items, this.notes = '', this.answeredBy = '', this.escalated = false});
  final List<DetectedFood> items;
  final String notes;

  /// The model that produced these numbers.
  final String answeredBy;

  /// Smart mode: the quick model wasn't sure, so the careful model answered.
  final bool escalated;

  MealAnalysis copyWith({String? answeredBy, bool? escalated}) => MealAnalysis(
    items: items,
    notes: notes,
    answeredBy: answeredBy ?? this.answeredBy,
    escalated: escalated ?? this.escalated,
  );

  /// Smart mode hands a photo to the careful model when the quick one found nothing, or is
  /// unsure about any item, or about the meal as a whole (confidence weighted by calories).
  bool get needsCarefulLook {
    if (items.isEmpty) return true;
    if (items.any((i) => i.confidence < 0.6)) return true;
    final kcal = items.fold<double>(0, (a, i) => a + i.calories);
    final weighted = kcal <= 0
        ? items.fold<double>(0, (a, i) => a + i.confidence) / items.length
        : items.fold<double>(0, (a, i) => a + i.confidence * i.calories) / kcal;
    return weighted < 0.75;
  }
}

/// Values transcribed from a nutrition facts panel, always per serving.
class LabelReading {
  const LabelReading({
    required this.name,
    required this.brand,
    required this.servingDescription,
    required this.servingGrams,
    required this.perServing,
    required this.readable,
    this.printedUnit = EnergyUnit.kcal,
    this.answeredBy = '',
  });
  final String name;
  final String brand;
  final String servingDescription;
  final double? servingGrams;
  final Nutrients perServing;
  final bool readable;

  /// The energy unit printed on the package.
  final EnergyUnit printedUnit;

  /// The model that read the label.
  final String answeredBy;

  LabelReading withModel(String id) => LabelReading(
    name: name,
    brand: brand,
    servingDescription: servingDescription,
    servingGrams: servingGrams,
    perServing: perServing,
    readable: readable,
    printedUnit: printedUnit,
    answeredBy: id,
  );
}

class VisionException implements Exception {
  const VisionException(this.message);
  final String message;
  static const missingKey = VisionException('Add an API key in Settings › AI Photo Estimates.');
  static const empty = VisionException('The AI service returned no result. Please try again.');
  static const invalidJson = VisionException("The AI response wasn’t in the expected format. Please try again.");
  @override
  String toString() => message;
}

/// Sends a meal photo to a multimodal model and returns structured nutrition estimates.
class AIVisionService {
  AIVisionService({required this.provider, required this.apiKey, required this.model, http.Client? client})
    : _client = client ?? http.Client();

  final VisionProvider provider;
  final String apiKey;
  final String model;
  final http.Client _client;

  static const instructions = '''
You are a meticulous registered dietitian analysing a photo of a meal.
Identify every distinct food or drink item that is visible. For each item provide:
- name: a short, specific description (e.g. "grilled chicken breast", "steamed white rice").
- estimated_grams: the edible portion weight in grams. Use the plate, cutlery, hands and packaging as scale references.
- calories, protein_g, carbs_g, fat_g, fiber_g (dietary fibre), sugar_g (total sugars): values for that whole portion, based on standard food-composition data (e.g. USDA FoodData Central). Account for visible oils, sauces and dressings.
- confidence: 0.0–1.0 for how sure you are about the identification and portion size.
List the components of mixed dishes separately when they are visually distinguishable.
Ignore plates, cutlery and inedible packaging. If no food is visible, return an empty items array.
Put a single-sentence caveat in "notes" (e.g. likely hidden ingredients), or an empty string.
Respond with JSON only.''';

  /// Gemini uses an OpenAPI subset with upper-case type names; OpenAI strict mode requires
  /// `additionalProperties: false` and every key in `required`.
  static Map<String, dynamic> responseSchema(VisionProvider provider) {
    final gemini = provider == VisionProvider.gemini;
    String type(String n) => gemini ? n.toUpperCase() : n;
    Map<String, dynamic> object(Map<String, dynamic> props, List<String> keys) => {
      'type': type('object'),
      'properties': props,
      'required': keys,
      if (gemini) 'propertyOrdering': keys else 'additionalProperties': false,
    };
    final string = {'type': type('string')};
    final number = {'type': type('number')};
    const itemKeys = [
      'name',
      'estimated_grams',
      'calories',
      'protein_g',
      'carbs_g',
      'fat_g',
      'fiber_g',
      'sugar_g',
      'confidence',
    ];
    final item = object({
      'name': string,
      'estimated_grams': number,
      'calories': number,
      'protein_g': number,
      'carbs_g': number,
      'fat_g': number,
      'fiber_g': number,
      'sugar_g': number,
      'confidence': number,
    }, itemKeys);
    return object(
      {
        'items': {'type': type('array'), 'items': item},
        'notes': string,
      },
      ['items', 'notes'],
    );
  }

  AIVisionService _as(String id) => AIVisionService(provider: provider, apiKey: apiKey, model: id, client: _client);

  Future<MealAnalysis> analyzeMeal(Uint8List jpeg, {String? hint}) async {
    if (apiKey.trim().isEmpty) throw VisionException.missingKey;
    if (model == AiModel.smartId) {
      // Haiku first (about 1/35 of Opus's price); Opus only when Haiku isn't sure or fails.
      try {
        final quick = await _as(AiModel.quickModel).analyzeMeal(jpeg, hint: hint);
        if (!quick.needsCarefulLook) return quick;
      } on VisionException catch (e) {
        if (_isConnection(e)) rethrow;
      }
      final careful = await _as(AiModel.carefulModel).analyzeMeal(jpeg, hint: hint);
      return careful.copyWith(escalated: true);
    }
    final b64 = base64Encode(jpeg);
    var userText = 'Analyse this meal photo and return the nutrition estimate.';
    final h = hint?.trim();
    if (h != null && h.isNotEmpty) userText += ' Additional context from the user: $h';
    final raw = switch (provider) {
      VisionProvider.gemini => await _gemini(b64, userText, instructions, responseSchema(provider)),
      VisionProvider.openAI => await _openAI(b64, userText, instructions, responseSchema(provider), 'meal_analysis'),
      VisionProvider.claude => await _claude(b64, userText, instructions, responseSchema(provider)),
    };
    return decodeAnalysis(raw).copyWith(answeredBy: model);
  }

  /// Errors Opus would hit too (no connection, bad key, rate limit): don't pay for a second try.
  static bool _isConnection(VisionException e) =>
      e.message.startsWith("Couldn’t reach") || RegExp(r'failed \((401|403|429)\)').hasMatch(e.message);

  Future<String> _gemini(String b64, String userText, String system, Map<String, dynamic> schema) async {
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userText},
            {
              'inlineData': {'mimeType': 'image/jpeg', 'data': b64},
            },
          ],
        },
      ],
      'generationConfig': {'temperature': 0.2, 'responseMimeType': 'application/json', 'responseSchema': schema},
    };
    final json = await _post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/${Uri.encodeComponent(model)}:generateContent',
      ),
      {'x-goog-api-key': apiKey},
      body,
    );
    final reason = (json['promptFeedback'] as Map?)?['blockReason'];
    if (reason != null) throw VisionException('The AI service declined this image ($reason).');
    final candidates = json['candidates'] as List?;
    final parts = ((candidates?.firstOrNull as Map?)?['content'] as Map?)?['parts'] as List?;
    final text = (parts ?? const []).map((p) => (p as Map)['text'] as String? ?? '').join();
    if (text.isEmpty) throw VisionException.empty;
    return text;
  }

  Future<String> _openAI(String b64, String userText, String system, Map<String, dynamic> schema, String name) async {
    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': userText},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$b64', 'detail': 'high'},
            },
          ],
        },
      ],
      'response_format': {
        'type': 'json_schema',
        'json_schema': {'name': name, 'strict': true, 'schema': schema},
      },
    };
    final json = await _post(Uri.parse('https://api.openai.com/v1/chat/completions'), {
      'Authorization': 'Bearer $apiKey',
    }, body);
    final message = ((json['choices'] as List?)?.firstOrNull as Map?)?['message'] as Map?;
    if (message == null) throw VisionException.empty;
    final refusal = message['refusal'] as String?;
    if (refusal != null && refusal.isNotEmpty) throw VisionException('The AI service declined this image ($refusal).');
    final content = message['content'] as String?;
    if (content == null || content.isEmpty) throw VisionException.empty;
    return content;
  }

  // ---- Claude (Anthropic Messages API, raw HTTP: there is no official Dart SDK) ----

  /// Sends the photo as a base64 image block and constrains the reply to [schema] with
  /// structured outputs. Thinking is always on for Claude Opus 5.5; effort is set explicitly
  /// (its default is medium). `fallbacks: "default"` lets Anthropic re-run a declined request on
  /// its recommended fallback model instead of returning the refusal.
  Future<String> _claude(String b64, String userText, String system, Map<String, dynamic> schema) async {
    final body = {
      'model': model,
      'max_tokens': 16000,
      'system': system,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': b64},
            },
            {'type': 'text', 'text': userText},
          ],
        },
      ],
      'output_config': {
        'effort': 'medium',
        'format': {'type': 'json_schema', 'schema': schema},
      },
      // Server-side fallback exists for Opus and Sonnet; Haiku returns the refusal as-is.
      if (!model.startsWith('claude-haiku')) 'fallbacks': 'default',
    };
    final json = await _post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      {
        'x-api-key': apiKey,
        'anthropic-version': '2026-10-21',
        if (!model.startsWith('claude-haiku')) 'anthropic-beta': 'server-side-fallback-2026-07-01',
        // The web build calls the API straight from the browser with the user's own key.
        if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
      },
      body,
      timeout: const Duration(seconds: 120),
    );
    return claudeText(json);
  }

  /// Pulls the JSON text out of a Messages API response, checking the stop reason first.
  static String claudeText(Map<String, dynamic> json) {
    final stop = json['stop_reason'];
    if (stop == 'refusal') {
      final category = (json['stop_details'] as Map?)?['category'];
      throw VisionException('Claude declined this image${category == null ? '' : ' ($category)'}.');
    }
    if (stop == 'max_tokens') {
      throw const VisionException('The AI reply was cut off. Please try again.');
    }
    final content = json['content'] is List ? json['content'] as List : const [];
    final text = content
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join();
    if (text.trim().isEmpty) throw VisionException.empty;
    return text;
  }

  Future<Map<String, dynamic>> _post(
    Uri url,
    Map<String, String> headers,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final http.Response res;
    try {
      res = await _client
          .post(url, headers: {'Content-Type': 'application/json', ...headers}, body: jsonEncode(body))
          .timeout(timeout);
    } catch (_) {
      throw const VisionException("Couldn’t reach the AI service. Check your connection and try again.");
    }
    Map<String, dynamic>? json;
    try {
      json = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = ((json?['error'] as Map?)?['message'] as String?) ?? 'HTTP ${res.statusCode}';
      throw VisionException('AI request failed (${res.statusCode}): $msg');
    }
    if (json == null) throw VisionException.empty;
    return json;
  }

  // ---- Nutrition label ----

  static const labelInstructions = '''
You read a photo of a packaged food's nutrition facts panel and transcribe it exactly.
Return:
- product_name and brand if they are visible on the package, else empty strings.
- serving_size: the serving size text as printed (e.g. "2 tbsp (32 g)"), or "" if none.
- serving_grams: grams (or ml) in one serving, or 0 if not printed.
- basis: "serving" if the values you report are per serving, "100g" if per 100 g / 100 ml.
  Prefer per-serving values when the label shows both. Australian/NZ panels list "Avg. Quantity per Serving"
  then "per 100 g": use the per-serving column; their energy is usually in kJ, sometimes with Cal in brackets,
  and fat is written "Fat, total".
- energy: the energy number exactly as printed, and energy_unit: "kcal" or "kJ". If both are printed, give the kcal figure.
- protein_g, carbs_g (total carbohydrate), fat_g (total fat), fiber_g (dietary fibre), sugar_g (total sugars; "sugars" on Australian panels). Use 0 for fibre or sugars only when the panel doesn't list them.
- readable: true if the panel was legible, false if you had to guess.
Never estimate from the look of the food. Use only the printed numbers. Respond with JSON only.''';

  static Map<String, dynamic> labelSchema(VisionProvider provider) {
    final gemini = provider == VisionProvider.gemini;
    String type(String n) => gemini ? n.toUpperCase() : n;
    const keys = [
      'product_name',
      'brand',
      'serving_size',
      'serving_grams',
      'basis',
      'energy',
      'energy_unit',
      'protein_g',
      'carbs_g',
      'fat_g',
      'fiber_g',
      'sugar_g',
      'readable',
    ];
    final string = {'type': type('string')};
    final number = {'type': type('number')};
    return {
      'type': type('object'),
      'properties': {
        'product_name': string,
        'brand': string,
        'serving_size': string,
        'serving_grams': number,
        'basis': {
          'type': type('string'),
          'enum': ['serving', '100g'],
        },
        'energy': number,
        'energy_unit': {
          'type': type('string'),
          'enum': ['kcal', 'kJ'],
        },
        'protein_g': number,
        'carbs_g': number,
        'fat_g': number,
        'fiber_g': number,
        'sugar_g': number,
        'readable': {'type': type('boolean')},
      },
      'required': keys,
      if (gemini) 'propertyOrdering': keys else 'additionalProperties': false,
    };
  }

  Future<LabelReading> readNutritionLabel(Uint8List jpeg) async {
    if (apiKey.trim().isEmpty) throw VisionException.missingKey;
    if (model == AiModel.smartId) {
      // Reading printed numbers is easy work: Opus only if Haiku couldn't read the panel.
      try {
        final quick = await _as(AiModel.quickModel).readNutritionLabel(jpeg);
        if (quick.readable) return quick;
      } on VisionException catch (e) {
        if (_isConnection(e)) rethrow;
      }
      return _as(AiModel.carefulModel).readNutritionLabel(jpeg);
    }
    final b64 = base64Encode(jpeg);
    const text = 'Transcribe this nutrition facts label.';
    final raw = switch (provider) {
      VisionProvider.gemini => await _gemini(b64, text, labelInstructions, labelSchema(provider)),
      VisionProvider.openAI => await _openAI(b64, text, labelInstructions, labelSchema(provider), 'nutrition_label'),
      VisionProvider.claude => await _claude(b64, text, labelInstructions, labelSchema(provider)),
    };
    return decodeLabel(raw).withModel(model);
  }

  static LabelReading decodeLabel(String raw) {
    var text = raw.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);
    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw VisionException.invalidJson;
    }
    if (json is! Map) throw VisionException.invalidJson;
    final Map map = json;
    String str(String k) => (map[k] is String ? map[k] as String : '').trim();
    // Stored as kcal; a kJ-only label is converted here and shown in the user's unit later.
    final energy = lossyDouble(json['energy']) ?? lossyDouble(json['calories']) ?? 0;
    final printedKJ = str('energy_unit').toLowerCase() == 'kj';
    final n = Nutrients(
      calories: printedKJ ? energy / kilojoulesPerKcal : energy,
      protein: lossyDouble(json['protein_g']) ?? 0,
      carbs: lossyDouble(json['carbs_g']) ?? 0,
      fat: lossyDouble(json['fat_g']) ?? 0,
      fiber: lossyDouble(json['fiber_g']) ?? 0,
      sugar: lossyDouble(json['sugar_g']) ?? 0,
    ).sanitized;
    final grams = lossyDouble(json['serving_grams']) ?? 0;
    final per100 = str('basis') == '100g';
    if (n.calories <= 0 && n.protein <= 0 && n.carbs <= 0 && n.fat <= 0) {
      throw const VisionException("Couldn’t read any numbers from that label. Try a sharper, closer photo.");
    }
    // Hand back per-serving values; convert from per-100 g when the serving weight is known.
    final perServing = per100 && grams > 0 ? n * (grams / 100) : n;
    return LabelReading(
      name: str('product_name'),
      brand: str('brand'),
      servingDescription: per100 && grams <= 0
          ? '100 g'
          : (str('serving_size').isEmpty ? 'serving' : str('serving_size')),
      servingGrams: grams > 0 ? grams : (per100 ? 100 : null),
      perServing: perServing,
      readable: json['readable'] != false,
      printedUnit: printedKJ ? EnergyUnit.kJ : EnergyUnit.kcal,
    );
  }

  /// Parses the model's JSON text, tolerating stray code fences, and drops unusable items.
  static MealAnalysis decodeAnalysis(String raw) {
    var text = raw.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);
    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw VisionException.invalidJson;
    }
    if (json is! Map) throw VisionException.invalidJson;
    final items = <DetectedFood>[];
    for (final it in (json['items'] is List ? json['items'] as List : const [])) {
      if (it is! Map) continue;
      final name = (it['name'] is String ? it['name'] as String : '').trim();
      final grams = lossyDouble(it['estimated_grams']) ?? 0;
      if (name.isEmpty || !grams.isFinite || grams <= 0) continue;
      final n = Nutrients(
        calories: lossyDouble(it['calories']) ?? 0,
        protein: lossyDouble(it['protein_g']) ?? 0,
        carbs: lossyDouble(it['carbs_g']) ?? 0,
        fat: lossyDouble(it['fat_g']) ?? 0,
        fiber: lossyDouble(it['fiber_g']) ?? 0,
        sugar: lossyDouble(it['sugar_g']) ?? 0,
      ).sanitized;
      items.add(
        DetectedFood(
          name: name,
          grams: grams,
          calories: n.calories,
          protein: n.protein,
          carbs: n.carbs,
          fat: n.fat,
          fiber: n.fiber,
          sugar: n.sugar,
          confidence: (lossyDouble(it['confidence']) ?? 0.5).clamp(0.0, 1.0),
        ),
      );
    }
    return MealAnalysis(items: items, notes: json['notes'] is String ? json['notes'] as String : '');
  }
}
