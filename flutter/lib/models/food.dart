import 'nutrients.dart';

enum MealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snacks');

  const MealType(this.title);
  final String title;

  /// A sensible default meal for the given time of day.
  static MealType suggested(DateTime t) {
    final h = t.hour;
    if (h >= 4 && h < 11) return breakfast;
    if (h >= 11 && h < 15) return lunch;
    if (h >= 17 && h < 22) return dinner;
    return snack;
  }

  static MealType parse(String? s) => values.firstWhere((m) => m.name == s, orElse: () => snack);
}

enum EntrySource {
  barcode,
  photoAI,
  manual,
  customFood,
  voice;

  static EntrySource parse(String? s) => values.firstWhere((m) => m.name == s, orElse: () => manual);
}

/// How far the nutrition numbers can be trusted, with the reason in plain words.
class NutritionTrust {
  const NutritionTrust.verified(this.note) : verified = true;
  const NutritionTrust.unverified(this.note) : verified = false;

  final bool verified;
  final String note;

  String get label => verified ? 'Verified' : 'Unverified';

  Map<String, dynamic> toJson() => {'v': verified, 'note': note};

  static NutritionTrust? fromJson(Object? j) {
    if (j is! Map) return null;
    final note = (j['note'] as String?) ?? '';
    return j['v'] == true ? NutritionTrust.verified(note) : NutritionTrust.unverified(note);
  }

  /// A rough sanity check: label calories should be close to 4·protein + 4·carbs + 9·fat.
  /// Fibre, alcohol and rounding explain small gaps, so allow 20 % or 15 kcal.
  static bool caloriesMatchMacros(Nutrients n) {
    final fromMacros = n.protein * 4 + n.carbs * 4 + n.fat * 9;
    if (n.calories <= 0 && fromMacros <= 0) return false;
    final diff = (n.calories - fromMacros).abs();
    return diff <= 15 || diff <= n.calories * 0.2;
  }
}

/// A single logged food. Nutrition values are totals for the logged portion, so daily sums are a
/// simple reduction. `quantity` + `unit` describe the portion and allow linear rescaling.
class FoodEntry {
  FoodEntry({
    required this.id,
    required this.name,
    this.brand,
    this.barcode,
    required this.meal,
    required this.source,
    required this.consumedAt,
    required this.quantity,
    required this.unit,
    this.grams,
    required Nutrients nutrients,
    this.healthSynced = false,
    this.trust,
  }) : nutrients = nutrients.sanitized;

  final String id;
  String name;
  String? brand;
  String? barcode;
  MealType meal;
  EntrySource source;
  DateTime consumedAt;
  double quantity;
  String unit;
  double? grams;
  Nutrients nutrients;
  bool healthSynced;
  NutritionTrust? trust;

  String get portionDescription {
    final amount = formatAmount(quantity);
    if (unit == 'g') return '$amount g';
    if (unit == 'serving') return '$amount ${quantity == 1 ? 'serving' : 'servings'}';
    return '$amount × $unit'; // e.g. "2 × 1 cup (240 ml)"
  }

  /// Linearly rescales nutrition (and grams) to a new portion quantity.
  void rescale(double newQuantity) {
    if (quantity <= 0 || newQuantity <= 0 || newQuantity == quantity) return;
    final factor = newQuantity / quantity;
    nutrients = (nutrients * factor).sanitized;
    grams = grams == null ? null : grams! * factor;
    quantity = newQuantity;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'barcode': barcode,
    'meal': meal.name,
    'source': source.name,
    'at': consumedAt.millisecondsSinceEpoch,
    'qty': quantity,
    'unit': unit,
    'grams': grams,
    'n': nutrients.toJson(),
    'hs': healthSynced,
    if (trust != null) 'trust': trust!.toJson(),
  };

  factory FoodEntry.fromJson(Map<String, dynamic> j) => FoodEntry(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    brand: j['brand'] as String?,
    barcode: j['barcode'] as String?,
    meal: MealType.parse(j['meal'] as String?),
    source: EntrySource.parse(j['source'] as String?),
    consumedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    quantity: (j['qty'] as num?)?.toDouble() ?? 1,
    unit: (j['unit'] as String?) ?? 'serving',
    grams: (j['grams'] as num?)?.toDouble(),
    nutrients: Nutrients.fromJson((j['n'] as Map).cast<String, dynamic>()),
    healthSynced: (j['hs'] as bool?) ?? false,
    trust: NutritionTrust.fromJson(j['trust']),
  );
}

/// A user-defined food ("My Foods"). Also caches barcodes Open Food Facts doesn't know.
class CustomFood {
  CustomFood({
    required this.id,
    required this.name,
    this.brand,
    this.barcode,
    this.servingDescription = 'serving',
    this.servingGrams,
    required Nutrients perServing,
    DateTime? lastUsedAt,
    this.useCount = 0,
    this.trust,
  }) : perServing = perServing.sanitized,
       lastUsedAt = lastUsedAt ?? DateTime.now();

  final String id;
  String name;
  String? brand;
  String? barcode;
  String servingDescription;
  double? servingGrams;
  Nutrients perServing;
  DateTime lastUsedAt;
  int useCount;
  NutritionTrust? trust;

  void markUsed() {
    lastUsedAt = DateTime.now();
    useCount += 1;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'barcode': barcode,
    'serving': servingDescription,
    'servingGrams': servingGrams,
    'n': perServing.toJson(),
    'used': lastUsedAt.millisecondsSinceEpoch,
    'count': useCount,
    if (trust != null) 'trust': trust!.toJson(),
  };

  factory CustomFood.fromJson(Map<String, dynamic> j) => CustomFood(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    brand: j['brand'] as String?,
    barcode: j['barcode'] as String?,
    servingDescription: (j['serving'] as String?) ?? 'serving',
    servingGrams: (j['servingGrams'] as num?)?.toDouble(),
    perServing: Nutrients.fromJson((j['n'] as Map).cast<String, dynamic>()),
    lastUsedAt: DateTime.fromMillisecondsSinceEpoch(((j['used'] as num?) ?? 0).toInt()),
    useCount: ((j['count'] as num?) ?? 0).toInt(),
    trust: NutritionTrust.fromJson(j['trust']),
  );
}

/// One drink of water, in millilitres.
class WaterEntry {
  WaterEntry({required this.id, required this.at, required this.ml});
  final String id;
  final DateTime at;
  final double ml;

  Map<String, dynamic> toJson() => {'id': id, 'at': at.millisecondsSinceEpoch, 'ml': ml};
  factory WaterEntry.fromJson(Map<String, dynamic> j) => WaterEntry(
    id: j['id'] as String,
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    ml: (j['ml'] as num).toDouble(),
  );
}

class WeightEntry {
  WeightEntry({required this.id, required this.date, required this.kilograms});
  final String id;
  final DateTime date;
  final double kilograms;

  Map<String, dynamic> toJson() => {'id': id, 'at': date.millisecondsSinceEpoch, 'kg': kilograms};
  factory WeightEntry.fromJson(Map<String, dynamic> j) => WeightEntry(
    id: j['id'] as String,
    date: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    kilograms: (j['kg'] as num).toDouble(),
  );
}

/// A food resolved from a barcode, either from Open Food Facts or the user's own "My Foods".
class FoodProduct {
  const FoodProduct({
    required this.barcode,
    required this.name,
    this.brand,
    this.imageUrl,
    this.servingDescription,
    this.servingGrams,
    this.per100g,
    this.perServingReported,
    this.source = EntrySource.barcode,
    this.customFoodId,
    this.trust,
  });

  final String barcode;
  final String name;
  final String? brand;
  final String? imageUrl;
  final String? servingDescription;
  final double? servingGrams;
  final Nutrients? per100g;
  final Nutrients? perServingReported;
  final EntrySource source;
  final String? customFoodId;
  final NutritionTrust? trust;

  factory FoodProduct.fromCustomFood(CustomFood food) {
    final g = food.servingGrams;
    return FoodProduct(
      barcode: food.barcode ?? food.id,
      name: food.name,
      brand: food.brand,
      servingDescription: food.servingDescription,
      servingGrams: g,
      per100g: g != null && g > 0 ? food.perServing * (100 / g) : null,
      perServingReported: food.perServing,
      source: EntrySource.customFood,
      customFoodId: food.id,
      trust: food.trust,
    );
  }

  /// Per-serving nutrition, derived from per-100 g values when not reported directly.
  Nutrients? get perServing {
    if (perServingReported != null) return perServingReported;
    final g = servingGrams;
    if (per100g != null && g != null && g > 0) return per100g! * (g / 100);
    return null;
  }

  bool get hasNutrition => per100g != null || perServing != null;
  bool get supportsGrams => nutrientsForGrams(100) != null;

  Nutrients? nutrientsForGrams(double grams) {
    if (per100g != null) return per100g! * (grams / 100);
    final g = servingGrams;
    if (perServingReported != null && g != null && g > 0) return perServingReported! * (grams / g);
    return null;
  }

  Nutrients? nutrientsForServings(double servings) => perServing == null ? null : perServing! * servings;

  String get servingLabel {
    final d = servingDescription;
    if (d != null && d.isNotEmpty) return d;
    if (servingGrams != null) return 'serving (${formatAmount(servingGrams!, maxDigits: 1)} g)';
    return 'serving';
  }
}

/// "1.5", "2", "0.25" — trims trailing zeros.
String formatAmount(double v, {int maxDigits = 2}) {
  var s = v.toStringAsFixed(maxDigits);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}
