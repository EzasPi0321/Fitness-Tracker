import '../models/food.dart';
import '../models/nutrients.dart';

/// Everyday whole and simple foods, built in so they're found instantly and offline. Open Food
/// Facts is a database of packaged, barcoded products, so a search for "banana" there mostly
/// finds banana chips and smoothies, when it answers at all.
///
/// Values are per 100 g (or 100 ml for drinks): typical figures from standard food-composition
/// data (USDA FoodData Central, cross-checked with AUSNUT), rounded. Each row is
/// name, other names it's searched by, a usual serving and its grams, then kcal, protein,
/// carbs, fat, fibre, sugars, saturated fat (g) and sodium (mg).
const _rows = <(String, String, String, double, List<double>)>[
  // Fruit
  ('Banana', '', 'medium (118 g)', 118, [89, 1.1, 22.8, 0.3, 2.6, 12.2, 0.1, 1]),
  ('Apple', '', 'medium (182 g)', 182, [52, 0.3, 13.8, 0.2, 2.4, 10.4, 0, 1]),
  ('Orange', '', 'medium (131 g)', 131, [47, 0.9, 11.8, 0.1, 2.4, 9.4, 0, 0]),
  ('Mandarin', 'tangerine', 'medium (88 g)', 88, [53, 0.8, 13.3, 0.3, 1.8, 10.6, 0, 2]),
  ('Pear', '', 'medium (178 g)', 178, [57, 0.4, 15.2, 0.1, 3.1, 9.8, 0, 1]),
  ('Grapes', 'grape', 'cup (151 g)', 151, [69, 0.7, 18.1, 0.2, 0.9, 15.5, 0.1, 2]),
  ('Strawberries', 'strawberry', 'cup (152 g)', 152, [32, 0.7, 7.7, 0.3, 2.0, 4.9, 0, 1]),
  ('Blueberries', 'blueberry', 'cup (148 g)', 148, [57, 0.7, 14.5, 0.3, 2.4, 10.0, 0, 1]),
  ('Raspberries', 'raspberry', 'cup (123 g)', 123, [52, 1.2, 11.9, 0.7, 6.5, 4.4, 0, 1]),
  ('Watermelon', '', 'cup diced (152 g)', 152, [30, 0.6, 7.6, 0.2, 0.4, 6.2, 0, 1]),
  ('Rockmelon', 'cantaloupe melon', 'cup diced (160 g)', 160, [34, 0.8, 8.2, 0.2, 0.9, 7.9, 0.1, 16]),
  ('Mango', '', 'cup sliced (165 g)', 165, [60, 0.8, 15.0, 0.4, 1.6, 13.7, 0.1, 1]),
  ('Pineapple', '', 'cup chunks (165 g)', 165, [50, 0.5, 13.1, 0.1, 1.4, 9.9, 0, 1]),
  ('Kiwifruit', 'kiwi', 'fruit (69 g)', 69, [61, 1.1, 14.7, 0.5, 3.0, 9.0, 0, 3]),
  ('Peach', 'nectarine', 'medium (150 g)', 150, [39, 0.9, 9.5, 0.3, 1.5, 8.4, 0, 0]),
  ('Plum', '', 'fruit (66 g)', 66, [46, 0.7, 11.4, 0.3, 1.4, 9.9, 0, 0]),
  ('Cherries', 'cherry', 'cup (138 g)', 138, [63, 1.1, 16.0, 0.2, 2.1, 12.8, 0, 0]),
  ('Grapefruit', '', 'half (123 g)', 123, [42, 0.8, 10.7, 0.1, 1.6, 6.9, 0, 0]),
  ('Avocado', 'avo', 'half (68 g)', 68, [160, 2.0, 8.5, 14.7, 6.7, 0.7, 2.1, 7]),
  ('Medjool dates', 'date dates', 'date (24 g)', 24, [277, 1.8, 75.0, 0.2, 6.7, 66.5, 0, 1]),
  ('Sultanas', 'raisins', 'small box (40 g)', 40, [299, 3.1, 79.2, 0.5, 3.7, 59.2, 0.1, 11]),
  // Vegetables
  ('Broccoli', '', 'cup chopped (91 g)', 91, [34, 2.8, 6.6, 0.4, 2.6, 1.7, 0.1, 33]),
  ('Carrot', 'carrots', 'medium (61 g)', 61, [41, 0.9, 9.6, 0.2, 2.8, 4.7, 0, 69]),
  ('Spinach', 'baby spinach', 'cup (30 g)', 30, [23, 2.9, 3.6, 0.4, 2.2, 0.4, 0.1, 79]),
  ('Lettuce', 'cos romaine salad leaves', 'cup shredded (47 g)', 47, [17, 1.2, 3.3, 0.3, 2.1, 1.2, 0, 8]),
  ('Tomato', 'tomatoes', 'medium (123 g)', 123, [18, 0.9, 3.9, 0.2, 1.2, 2.6, 0, 5]),
  ('Cucumber', 'cucumbers', 'cup sliced (104 g)', 104, [15, 0.7, 3.6, 0.1, 0.5, 1.7, 0, 2]),
  ('Capsicum', 'bell pepper red pepper', 'medium (119 g)', 119, [31, 1.0, 6.0, 0.3, 2.1, 4.2, 0, 4]),
  ('Onion', 'onions', 'medium (110 g)', 110, [40, 1.1, 9.3, 0.1, 1.7, 4.2, 0, 4]),
  ('Potato, baked', 'potato potatoes jacket', 'medium (173 g)', 173, [93, 2.5, 21.2, 0.1, 2.2, 1.2, 0, 10]),
  ('Sweet potato, baked', 'sweet potato kumara', 'medium (114 g)', 114, [90, 2.0, 20.7, 0.2, 3.3, 6.5, 0, 36]),
  ('Corn on the cob', 'sweet corn corn', 'cob (90 g)', 90, [96, 3.4, 21.0, 1.5, 2.4, 4.5, 0.2, 1]),
  ('Peas', 'green peas', 'cup (160 g)', 160, [84, 5.4, 15.6, 0.2, 5.5, 5.9, 0, 3]),
  ('Green beans', 'beans', 'cup (125 g)', 125, [35, 1.9, 7.9, 0.3, 3.2, 3.6, 0.1, 1]),
  ('Mushrooms', 'mushroom', 'cup sliced (70 g)', 70, [22, 3.1, 3.3, 0.3, 1.0, 2.0, 0, 5]),
  ('Zucchini', 'courgette', 'medium (196 g)', 196, [17, 1.2, 3.1, 0.3, 1.0, 2.5, 0.1, 8]),
  ('Cauliflower', '', 'cup (107 g)', 107, [25, 1.9, 5.0, 0.3, 2.0, 1.9, 0.1, 30]),
  ('Pumpkin, cooked', 'pumpkin butternut', 'cup (245 g)', 245, [20, 0.7, 4.9, 0.1, 1.1, 2.1, 0, 1]),
  ('Kale', '', 'cup chopped (21 g)', 21, [35, 2.9, 4.4, 1.5, 4.1, 1.0, 0.2, 53]),
  ('Edamame', 'soy beans soybeans', 'cup (155 g)', 155, [121, 11.9, 8.9, 5.2, 5.2, 2.2, 0.6, 6]),
  // Grains, bread and cereal
  ('White rice, cooked', 'rice white rice steamed rice', 'cup (158 g)', 158, [130, 2.7, 28.2, 0.3, 0.4, 0.1, 0.1, 1]),
  ('Brown rice, cooked', 'rice brown rice', 'cup (195 g)', 195, [112, 2.6, 23.0, 0.9, 1.8, 0.4, 0.2, 5]),
  ('Pasta, cooked', 'spaghetti penne noodles pasta', 'cup (140 g)', 140, [158, 5.8, 30.9, 0.9, 1.8, 0.6, 0.2, 1]),
  ('Rolled oats', 'oats oatmeal', 'half cup dry (40 g)', 40, [379, 13.2, 67.7, 6.5, 10.1, 1.0, 1.1, 6]),
  ('Porridge', 'oatmeal oats cooked', 'bowl (234 g)', 234, [71, 2.5, 12.0, 1.5, 1.7, 0.3, 0.3, 4]),
  ('White bread', 'bread toast', 'slice (30 g)', 30, [266, 7.6, 50.6, 3.3, 2.4, 5.7, 0.7, 490]),
  (
    'Wholemeal bread',
    'bread toast whole wheat wholegrain',
    'slice (32 g)',
    32,
    [252, 12.4, 42.7, 3.5, 6.0, 4.4, 0.7, 450],
  ),
  ('Bagel', '', 'bagel (105 g)', 105, [257, 10.0, 50.5, 1.6, 2.2, 5.1, 0.2, 450]),
  ('Tortilla wrap', 'wrap tortilla flour', 'wrap (45 g)', 45, [312, 8.3, 51.6, 8.0, 3.5, 3.2, 3.3, 600]),
  ('Croissant', '', 'croissant (57 g)', 57, [406, 8.2, 45.8, 21.0, 2.6, 11.3, 11.7, 384]),
  ('Quinoa, cooked', 'quinoa', 'cup (185 g)', 185, [120, 4.4, 21.3, 1.9, 2.8, 0.9, 0.2, 7]),
  ('Wheat biscuits', 'weet-bix weetbix', '2 biscuits (30 g)', 30, [358, 12.4, 67.0, 1.4, 11.0, 3.3, 0.3, 270]),
  ('Cornflakes', 'corn flakes cereal', 'bowl (30 g)', 30, [357, 7.5, 84.1, 0.4, 3.3, 8.0, 0.1, 729]),
  ('Muesli', 'granola cereal', 'serve (45 g)', 45, [360, 10.0, 66.0, 6.0, 8.0, 20.0, 1.0, 50]),
  ('Rice cakes', 'rice cake', 'cake (9 g)', 9, [387, 8.2, 81.5, 2.8, 4.2, 0.9, 0.6, 29]),
  // Meat, fish, eggs and plant protein
  ('Chicken breast, cooked', 'chicken grilled chicken', 'breast (150 g)', 150, [165, 31.0, 0, 3.6, 0, 0, 1.0, 74]),
  ('Chicken thigh, cooked', 'chicken thigh', 'thigh fillet (100 g)', 100, [209, 26.0, 0, 10.9, 0, 0, 3.0, 95]),
  ('Beef mince, cooked', 'mince ground beef', 'serve (100 g)', 100, [250, 25.9, 0, 15.4, 0, 0, 5.9, 72]),
  ('Steak, grilled', 'beef steak sirloin rump', 'steak (170 g)', 170, [200, 30.0, 0, 8.5, 0, 0, 3.3, 60]),
  ('Salmon, cooked', 'salmon fillet fish', 'fillet (150 g)', 150, [206, 22.1, 0, 12.4, 0, 0, 2.5, 61]),
  ('Tuna in water', 'tuna canned tuna tinned tuna', 'can drained (95 g)', 95, [116, 25.5, 0, 0.8, 0, 0, 0.2, 338]),
  ('Prawns, cooked', 'shrimp prawn', 'serve (100 g)', 100, [99, 24.0, 0.2, 0.3, 0, 0, 0.1, 111]),
  ('Egg', 'eggs boiled egg poached egg', 'large egg (50 g)', 50, [143, 12.6, 0.7, 9.5, 0, 0.4, 3.1, 142]),
  ('Ham', 'sliced ham deli ham', 'slice (28 g)', 28, [163, 16.6, 3.8, 8.6, 0, 0, 2.9, 1203]),
  ('Bacon, cooked', 'bacon', 'rasher (20 g)', 20, [541, 37.0, 1.4, 42.0, 0, 0, 13.7, 1717]),
  ('Tofu, firm', 'tofu bean curd', 'serve (100 g)', 100, [144, 17.3, 2.8, 8.7, 2.3, 0.6, 1.3, 14]),
  ('Lentils, cooked', 'lentil', 'cup (198 g)', 198, [116, 9.0, 20.1, 0.4, 7.9, 1.8, 0.1, 2]),
  ('Chickpeas, cooked', 'chickpea garbanzo', 'cup (164 g)', 164, [164, 8.9, 27.4, 2.6, 7.6, 4.8, 0.3, 7]),
  ('Black beans, cooked', 'beans', 'cup (172 g)', 172, [132, 8.9, 23.7, 0.5, 8.7, 0.3, 0.1, 1]),
  ('Baked beans', 'beans', 'half cup (130 g)', 130, [94, 4.8, 21.1, 0.4, 4.1, 7.8, 0.1, 343]),
  (
    'Whey protein powder',
    'protein shake protein powder whey',
    'scoop (30 g)',
    30,
    [380, 78.0, 8.0, 5.0, 0, 5.0, 3.0, 200],
  ),
  // Dairy
  ('Milk, full cream', 'milk whole milk', 'cup (250 ml)', 250, [61, 3.2, 4.8, 3.3, 0, 4.8, 1.9, 43]),
  ('Milk, skim', 'milk skim milk skinny', 'cup (250 ml)', 250, [34, 3.4, 5.0, 0.1, 0, 5.0, 0.1, 42]),
  ('Greek yoghurt, plain', 'yogurt yoghurt greek yogurt', 'tub (170 g)', 170, [97, 9.0, 4.0, 5.0, 0, 4.0, 2.4, 35]),
  (
    'Greek yoghurt, fat free',
    'yogurt yoghurt greek yogurt nonfat',
    'tub (170 g)',
    170,
    [59, 10.2, 3.6, 0.4, 0, 3.2, 0.1, 36],
  ),
  ('Cheddar cheese', 'cheese tasty cheese', 'slice (21 g)', 21, [403, 24.9, 1.3, 33.1, 0, 0.5, 21.1, 621]),
  ('Mozzarella', 'cheese', 'serve (28 g)', 28, [300, 22.2, 2.2, 22.4, 0, 1.0, 13.2, 627]),
  ('Cottage cheese', 'cheese', 'half cup (113 g)', 113, [98, 11.1, 3.4, 4.3, 0, 2.7, 1.7, 364]),
  ('Butter', '', 'tsp (5 g)', 5, [717, 0.9, 0.1, 81.1, 0, 0.1, 51.4, 643]),
  ('Ice cream, vanilla', 'ice cream gelato', 'scoop (66 g)', 66, [207, 3.5, 23.6, 11.0, 0.7, 21.2, 6.8, 80]),
  // Nuts, seeds, fats and spreads
  ('Olive oil', 'oil', 'tbsp (14 g)', 14, [884, 0, 0, 100, 0, 0, 13.8, 2]),
  ('Almonds', 'almond nuts', 'handful (28 g)', 28, [579, 21.2, 21.6, 49.9, 12.5, 4.4, 3.8, 1]),
  ('Peanuts', 'peanut nuts', 'handful (28 g)', 28, [567, 25.8, 16.1, 49.2, 8.5, 4.7, 6.3, 18]),
  ('Cashews', 'cashew nuts', 'handful (28 g)', 28, [553, 18.2, 30.2, 43.9, 3.3, 5.9, 7.8, 12]),
  ('Walnuts', 'walnut nuts', 'handful (28 g)', 28, [654, 15.2, 13.7, 65.2, 6.7, 2.6, 6.1, 2]),
  ('Peanut butter', 'pb', 'tbsp (16 g)', 16, [588, 25.1, 20.0, 50.4, 6.0, 9.2, 10.3, 459]),
  ('Chia seeds', 'chia', 'tbsp (12 g)', 12, [486, 16.5, 42.1, 30.7, 34.4, 0, 3.3, 16]),
  ('Hummus', 'houmous', '2 tbsp (30 g)', 30, [166, 7.9, 14.3, 9.6, 6.0, 0.3, 1.4, 379]),
  ('Honey', '', 'tbsp (21 g)', 21, [304, 0.3, 82.4, 0, 0.2, 82.1, 0, 4]),
  ('Sugar', 'white sugar', 'tsp (4 g)', 4, [387, 0, 100, 0, 0, 100, 0, 1]),
  // Snacks and treats
  (
    'Dark chocolate (70–85%)',
    'chocolate dark chocolate',
    '4 squares (25 g)',
    25,
    [598, 7.8, 45.9, 42.6, 10.9, 24.0, 24.5, 20],
  ),
  ('Milk chocolate', 'chocolate', '4 squares (25 g)', 25, [535, 7.6, 59.4, 29.7, 3.4, 51.5, 18.5, 79]),
  ('Potato chips', 'crisps chips', 'small packet (28 g)', 28, [536, 7.0, 53.0, 34.6, 4.4, 0.3, 3.6, 525]),
  ('Popcorn, air-popped', 'popcorn', '3 cups (24 g)', 24, [387, 12.9, 77.8, 4.5, 14.5, 0.9, 0.6, 8]),
  // Takeaway and common meals
  ('Cheese pizza', 'pizza margherita', 'slice (107 g)', 107, [266, 11.4, 33.3, 9.7, 2.3, 3.6, 4.5, 598]),
  ('Pepperoni pizza', 'pizza', 'slice (110 g)', 110, [287, 12.0, 32.0, 12.4, 2.2, 3.5, 5.2, 683]),
  ('Cheeseburger', 'burger hamburger', 'burger (113 g)', 113, [265, 13.3, 28.3, 11.5, 1.2, 6.2, 5.3, 650]),
  ('Hot chips', 'fries french fries chips', 'medium (117 g)', 117, [312, 3.4, 41.4, 14.7, 3.8, 0.3, 2.3, 210]),
  // Drinks (per 100 ml)
  ('Latte', 'flat white cappuccino coffee', 'regular (240 ml)', 240, [46, 2.5, 3.7, 2.4, 0, 3.7, 1.4, 36]),
  ('Black coffee', 'long black espresso americano coffee', 'cup (250 ml)', 250, [1, 0.1, 0, 0, 0, 0, 0, 2]),
  ('Orange juice', 'juice oj', 'glass (250 ml)', 250, [45, 0.7, 10.4, 0.2, 0.2, 8.4, 0, 1]),
  ('Cola', 'coke coca-cola soft drink soda', 'can (375 ml)', 375, [42, 0, 10.6, 0, 0, 10.6, 0, 4]),
  ('Beer', 'lager', 'can (375 ml)', 375, [43, 0.5, 3.6, 0, 0, 0, 0, 4]),
  ('Red wine', 'wine', 'glass (150 ml)', 150, [85, 0.1, 2.6, 0, 0, 0.6, 0, 4]),
];

/// Built-in foods matching [query], best first: whole-word matches on the name, then the
/// other names, then partial matches.
List<FoodProduct> searchCommonFoods(String query, {int limit = 8}) {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];
  final scored = <(int, int, FoodProduct)>[];
  for (final (i, row) in _rows.indexed) {
    final name = row.$1.toLowerCase();
    final alt = row.$2.toLowerCase();
    final words = RegExp(r'[a-z]+').allMatches('$name $alt').map((m) => m.group(0)!).toSet();
    final int score;
    if (name == q || name.startsWith('$q,')) {
      score = 0;
    } else if (words.any((w) => w == q || w == '${q}s' || '${w}s' == q)) {
      score = 1;
    } else if (name.contains(q) || alt.contains(q)) {
      score = 2;
    } else if (words.any((w) => w.startsWith(q))) {
      score = 3;
    } else {
      continue;
    }
    scored.add((score, i, _product(row)));
  }
  scored.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final s in scored.take(limit)) s.$3];
}

/// Every built-in food, for tests.
List<FoodProduct> get allCommonFoods => [for (final r in _rows) _product(r)];

const _trust = NutritionTrust.verified('Typical values for this food, from standard food-composition data (USDA)');

FoodProduct _product((String, String, String, double, List<double>) r) {
  final v = r.$5;
  return FoodProduct(
    barcode: 'common:${r.$1.toLowerCase()}',
    name: r.$1,
    servingDescription: r.$3,
    servingGrams: r.$4,
    per100g: Nutrients(
      calories: v[0],
      protein: v[1],
      carbs: v[2],
      fat: v[3],
      fiber: v[4],
      sugar: v[5],
      satFat: v[6],
      sodium: v[7],
    ),
    source: EntrySource.manual,
    trust: _trust,
  );
}
