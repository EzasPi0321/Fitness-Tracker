import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/food.dart';
import '../models/nutrients.dart';

class FoodLookupException implements Exception {
  const FoodLookupException(this.message);
  final String message;

  static const invalidBarcode = FoodLookupException("That doesn’t look like a valid product barcode.");
  static const notFound = FoodLookupException("This product isn’t in the Open Food Facts database yet.");
  static const decoding = FoodLookupException("The product data couldn’t be read.");
  static const offline = FoodLookupException("Couldn’t reach Open Food Facts. Check your connection and try again.");

  @override
  String toString() => message;
}

/// Client for the public Open Food Facts product API.
class OpenFoodFactsService {
  OpenFoodFactsService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static String normalizeBarcode(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  Future<FoodProduct> product(String rawBarcode) async {
    final barcode = normalizeBarcode(rawBarcode);
    if (barcode.length < 6 || barcode.length > 14) throw FoodLookupException.invalidBarcode;

    final http.Response res;
    try {
      res = await _client
          .get(
            Uri.parse('https://world.openfoodfacts.org/api/v0/product/$barcode.json'),
            headers: const {'Accept': 'application/json', 'User-Agent': 'FitTrack/2.0'},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw FoodLookupException.offline;
    }
    if (res.statusCode == 404) throw FoodLookupException.notFound;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FoodLookupException('Open Food Facts returned an error (${res.statusCode}). Please try again.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw FoodLookupException.decoding;
    }
    final product = parseProduct(barcode, decoded);
    if (product == null) throw FoodLookupException.notFound;
    return product;
  }

  /// Open Food Facts is crowd-sourced: numbers arrive as strings ("12,5"), fields go missing.
  /// Each field is read on its own so one bad value doesn't fail the whole product.
  static FoodProduct? parseProduct(String barcode, Object? json) {
    if (json is! Map) return null;
    if (lossyDouble(json['status']) != 1) return null;
    final p = json['product'];
    if (p is! Map) return null;

    final name = lossyString(p['product_name']) ?? lossyString(p['product_name_en']) ?? lossyString(p['generic_name']);
    final n = p['nutriments'] is Map ? p['nutriments'] as Map : const {};

    Nutrients? read(String suffix) {
      final kcal = lossyDouble(n['energy-kcal_$suffix']) ?? _kjToKcal(lossyDouble(n['energy_$suffix']));
      if (kcal == null) return null;
      return Nutrients(
        calories: kcal,
        protein: lossyDouble(n['proteins_$suffix']) ?? 0,
        carbs: lossyDouble(n['carbohydrates_$suffix']) ?? 0,
        fat: lossyDouble(n['fat_$suffix']) ?? 0,
        fiber: lossyDouble(n['fiber_$suffix']) ?? 0,
        sugar: lossyDouble(n['sugars_$suffix']) ?? 0,
        satFat: lossyDouble(n['saturated-fat_$suffix']) ?? 0,
        // Open Food Facts gives sodium in grams; salt is 2.5x sodium when only salt is listed.
        sodium: ((lossyDouble(n['sodium_$suffix']) ?? ((lossyDouble(n['salt_$suffix']) ?? 0) / 2.5)) * 1000),
      ).sanitized;
    }

    final per100g = read('100g');
    final perServing = read('serving');
    if (name == null && per100g == null && perServing == null) return null;

    final servingQty = lossyDouble(p['serving_quantity']);
    final trust = rateTrust(p, per100g ?? perServing);
    final brand = lossyString(p['brands'])?.split(',').first.trim();
    return FoodProduct(
      barcode: barcode,
      name: name ?? 'Product $barcode',
      brand: (brand == null || brand.isEmpty) ? null : brand,
      imageUrl: lossyString(p['image_front_url']) ?? lossyString(p['image_front_small_url']),
      servingDescription: lossyString(p['serving_size']),
      servingGrams: servingQty != null && servingQty > 0 ? servingQty : null,
      per100g: per100g,
      perServingReported: perServing,
      trust: trust,
    );
  }

  /// Verified when Open Food Facts marks the nutrition facts complete, no nutrition data
  /// problems are flagged, and the calories agree with the macros. Otherwise unverified, with
  /// the first reason that applies.
  static NutritionTrust rateTrust(Map p, Nutrients? n) {
    List<String> tags(String k) => (p[k] is List ? p[k] as List : const []).whereType<String>().toList();
    final states = tags('states_tags');
    final problems = tags('data_quality_errors_tags')
        .where((t) => t.contains('nutrition') || t.contains('energy') || t.contains('nutriment'))
        .toList();
    final complete = states.contains('en:nutrition-facts-completed');
    final checked = states.contains('en:checked');
    if (n == null) return const NutritionTrust.unverified('No nutrition facts in Open Food Facts');
    if (!complete && !checked)
      return const NutritionTrust.unverified('Nutrition facts not marked complete in Open Food Facts');
    if (problems.isNotEmpty)
      return const NutritionTrust.unverified('Open Food Facts flagged a problem with these numbers');
    if (!NutritionTrust.caloriesMatchMacros(n))
      return const NutritionTrust.unverified("Calories don’t match the protein, carbs and fat");
    return NutritionTrust.verified(
      checked
          ? 'Checked by Open Food Facts editors; calories match the macros'
          : 'Complete in Open Food Facts; calories match the macros',
    );
  }

  static const _searchFields =
      'code,product_name,product_name_en,generic_name,brands,serving_size,serving_quantity,image_front_small_url,'
      'image_front_url,nutriments,states_tags,data_quality_errors_tags';

  /// Text search. Results without any nutrition are dropped.
  Future<List<FoodProduct>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
      'search_terms': q,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '20',
      'fields': _searchFields,
    });
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: const {'Accept': 'application/json', 'User-Agent': 'FitTrack/2.0'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw FoodLookupException.offline;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FoodLookupException('Search failed (${res.statusCode}). Please try again.');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw FoodLookupException.decoding;
    }
    return parseSearch(json);
  }

  static List<FoodProduct> parseSearch(Object? json) {
    if (json is! Map || json['products'] is! List) return const [];
    final out = <FoodProduct>[];
    for (final p in json['products'] as List) {
      if (p is! Map) continue;
      final code = lossyString(p['code']) ?? '';
      final product = parseProduct(code, {'status': 1, 'product': p});
      if (product != null && product.hasNutrition) out.add(product);
    }
    return out;
  }

  static double? _kjToKcal(double? kj) => kj == null ? null : kj / 4.184;
}

/// A number that may arrive as a JSON number or a numeric string like "6,3".
double? lossyDouble(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

String? lossyString(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
