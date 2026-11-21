/// Energy and macronutrients for an arbitrary amount of food.
class Nutrients {
  const Nutrients({this.calories = 0, this.protein = 0, this.carbs = 0, this.fat = 0});

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  static const zero = Nutrients();

  Nutrients operator +(Nutrients o) => Nutrients(
    calories: calories + o.calories,
    protein: protein + o.protein,
    carbs: carbs + o.carbs,
    fat: fat + o.fat,
  );

  Nutrients operator *(double factor) =>
      Nutrients(calories: calories * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor);

  /// Replaces negative or non-finite values (common in crowd-sourced / AI data) with zero.
  Nutrients get sanitized {
    double clean(double v) => v.isFinite ? (v < 0 ? 0 : v) : 0;
    return Nutrients(calories: clean(calories), protein: clean(protein), carbs: clean(carbs), fat: clean(fat));
  }

  double of(Macro macro) => switch (macro) {
    Macro.protein => protein,
    Macro.carbs => carbs,
    Macro.fat => fat,
  };

  static Nutrients sum(Iterable<Nutrients> values) => values.fold(zero, (a, b) => a + b);

  Map<String, dynamic> toJson() => {'cal': calories, 'p': protein, 'c': carbs, 'f': fat};

  factory Nutrients.fromJson(Map<String, dynamic> j) =>
      Nutrients(calories: _d(j['cal']), protein: _d(j['p']), carbs: _d(j['c']), fat: _d(j['f']));

  @override
  bool operator ==(Object other) =>
      other is Nutrients &&
      other.calories == calories &&
      other.protein == protein &&
      other.carbs == carbs &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(calories, protein, carbs, fat);

  @override
  String toString() => 'Nutrients($calories kcal, P$protein C$carbs F$fat)';
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
