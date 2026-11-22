/// Energy and macronutrients for an arbitrary amount of food.
class Nutrients {
  const Nutrients({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.sugar = 0,
    this.satFat = 0,
    this.sodium = 0,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  /// Dietary fibre and sugars in grams. Not every source reports them, so 0 can mean "not
  /// known": the health score only ever adds credit for fibre and takes it away for sugar,
  /// so a missing value never counts against a food.
  final double fiber;
  final double sugar;

  /// Saturated fat in grams and sodium in milligrams, for the health score (FSANZ nutrient
  /// profiling). 0 can mean "not known" too; the AI fill-in supplies them when missing.
  final double satFat;
  final double sodium;

  static const zero = Nutrients();

  Nutrients operator +(Nutrients o) => Nutrients(
    calories: calories + o.calories,
    protein: protein + o.protein,
    carbs: carbs + o.carbs,
    fat: fat + o.fat,
    fiber: fiber + o.fiber,
    sugar: sugar + o.sugar,
    satFat: satFat + o.satFat,
    sodium: sodium + o.sodium,
  );

  Nutrients operator *(double factor) => Nutrients(
    calories: calories * factor,
    protein: protein * factor,
    carbs: carbs * factor,
    fat: fat * factor,
    fiber: fiber * factor,
    sugar: sugar * factor,
    satFat: satFat * factor,
    sodium: sodium * factor,
  );

  /// Replaces negative or non-finite values (common in crowd-sourced / AI data) with zero.
  Nutrients get sanitized {
    double clean(double v) => v.isFinite ? (v < 0 ? 0 : v) : 0;
    return Nutrients(
      calories: clean(calories),
      protein: clean(protein),
      carbs: clean(carbs),
      fat: clean(fat),
      fiber: clean(fiber),
      sugar: clean(sugar),
      satFat: clean(satFat),
      sodium: clean(sodium),
    );
  }

  /// The same food with fibre and sugar filled in (from a source that knows them).
  Nutrients withExtras({double? fiber, double? sugar, double? satFat, double? sodium}) => Nutrients(
    calories: calories,
    protein: protein,
    carbs: carbs,
    fat: fat,
    fiber: fiber ?? this.fiber,
    sugar: sugar ?? this.sugar,
    satFat: satFat ?? this.satFat,
    sodium: sodium ?? this.sodium,
  );

  double of(Macro macro) => switch (macro) {
    Macro.protein => protein,
    Macro.carbs => carbs,
    Macro.fat => fat,
  };

  static Nutrients sum(Iterable<Nutrients> values) => values.fold(zero, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'cal': calories,
    'p': protein,
    'c': carbs,
    'f': fat,
    if (fiber > 0) 'fi': fiber,
    if (sugar > 0) 'su': sugar,
    if (satFat > 0) 'sf': satFat,
    if (sodium > 0) 'na': sodium,
  };

  factory Nutrients.fromJson(Map<String, dynamic> j) => Nutrients(
    calories: _d(j['cal']),
    protein: _d(j['p']),
    carbs: _d(j['c']),
    fat: _d(j['f']),
    fiber: _d(j['fi']),
    sugar: _d(j['su']),
    satFat: _d(j['sf']),
    sodium: _d(j['na']),
  );

  @override
  bool operator ==(Object other) =>
      other is Nutrients &&
      other.calories == calories &&
      other.protein == protein &&
      other.carbs == carbs &&
      other.fat == fat &&
      other.fiber == fiber &&
      other.sugar == sugar &&
      other.satFat == satFat &&
      other.sodium == sodium;

  @override
  int get hashCode => Object.hash(calories, protein, carbs, fat, fiber, sugar, satFat, sodium);

  @override
  String toString() => 'Nutrients($calories kcal, P$protein C$carbs F$fat fibre$fiber sugar$sugar)';
}

enum Macro {
  protein('Protein', 'P'),
  carbs('Carbs', 'C'),
  fat('Fat', 'F');

  const Macro(this.title, this.short);
  final String title;
  final String short;

  double get kcalPerGram => this == Macro.fat ? 9 : 4;
}

double _d(Object? v) => v is num ? v.toDouble() : 0;
