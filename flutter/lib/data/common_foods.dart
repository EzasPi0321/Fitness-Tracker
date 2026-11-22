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
  // More fruit
  ('Papaya', 'pawpaw', 'cup (145 g)', 145, [43, 0.5, 10.8, 0.3, 1.7, 7.8, 0.1, 8]),
  ('Pomegranate seeds', 'pomegranate', 'half cup (87 g)', 87, [83, 1.7, 18.7, 1.2, 4.0, 13.7, 0.1, 3]),
  ('Apricot', 'apricots', 'fruit (35 g)', 35, [48, 1.4, 11.1, 0.4, 2.0, 9.2, 0, 1]),
  ('Lychees', 'lychee', 'cup (190 g)', 190, [66, 0.8, 16.5, 0.4, 1.3, 15.2, 0.1, 1]),
  ('Passionfruit', 'passion fruit', 'fruit (18 g)', 18, [97, 2.2, 23.4, 0.7, 10.4, 11.2, 0.1, 28]),
  ('Fruit salad', 'mixed fruit', 'cup (180 g)', 180, [50, 0.6, 12.7, 0.2, 1.6, 10.5, 0, 2]),
  ('Dried apricots', 'apricots dried fruit', '5 pieces (35 g)', 35, [241, 3.4, 62.6, 0.5, 7.3, 53.4, 0, 10]),
  ('Desiccated coconut', 'coconut', 'tbsp (5 g)', 5, [660, 6.9, 23.7, 64.5, 16.3, 7.4, 57.2, 37]),
  // More vegetables
  ('Asparagus', '', 'serve (90 g)', 90, [20, 2.2, 3.9, 0.1, 2.1, 1.9, 0, 2]),
  ('Brussels sprouts, cooked', 'brussels sprouts sprouts', 'cup (156 g)', 156, [36, 2.6, 7.1, 0.5, 2.6, 1.7, 0.1, 21]),
  ('Cabbage', '', 'cup shredded (89 g)', 89, [25, 1.3, 5.8, 0.1, 2.5, 3.2, 0, 18]),
  ('Celery', '', 'stalk (40 g)', 40, [14, 0.7, 3.0, 0.2, 1.6, 1.3, 0, 80]),
  ('Beetroot, cooked', 'beets beetroot', 'half cup (85 g)', 85, [44, 1.7, 10.0, 0.2, 2.0, 8.0, 0, 77]),
  ('Eggplant, cooked', 'aubergine eggplant', 'cup (99 g)', 99, [35, 0.8, 8.7, 0.2, 2.5, 3.2, 0, 1]),
  ('Bok choy, cooked', 'pak choy bok choy', 'cup (170 g)', 170, [12, 1.6, 1.8, 0.2, 1.0, 0.8, 0, 34]),
  ('Snow peas', 'mangetout sugar snap peas', 'cup (63 g)', 63, [42, 2.8, 7.6, 0.2, 2.6, 4.0, 0, 4]),
  ('Garden salad', 'salad side salad', 'bowl (150 g)', 150, [17, 1.1, 3.4, 0.2, 1.6, 1.8, 0, 15]),
  ('Coleslaw', 'slaw', 'cup (120 g)', 120, [152, 1.1, 13.0, 10.9, 1.5, 11.0, 1.6, 230]),
  ('Mashed potato', 'mash potatoes', 'cup (210 g)', 210, [113, 1.9, 16.9, 4.2, 1.5, 1.4, 2.3, 300]),
  ('Hash brown', 'hashbrown', 'piece (55 g)', 55, [270, 2.5, 28.0, 16.6, 2.5, 0.3, 2.5, 450]),
  ('Olives', 'olive', '10 olives (30 g)', 30, [115, 0.8, 6.3, 10.7, 3.2, 0, 1.4, 735]),
  (
    'Mixed vegetables, cooked',
    'frozen vegetables veggies vegetables',
    'cup (182 g)',
    182,
    [65, 2.9, 13.1, 0.2, 4.4, 3.1, 0, 35],
  ),
  // More bread, grains and cereal
  ('Sourdough bread', 'bread toast sourdough', 'slice (45 g)', 45, [272, 10.8, 51.9, 2.4, 2.2, 2.3, 0.5, 602]),
  ('Bread roll', 'roll bun', 'roll (60 g)', 60, [279, 9.5, 50.0, 4.3, 2.3, 4.6, 0.9, 480]),
  ('English muffin', 'muffin', 'muffin (57 g)', 57, [227, 8.9, 44.2, 1.7, 3.5, 3.6, 0.3, 425]),
  ('Pita bread', 'pita pitta flatbread lebanese bread', 'pita (60 g)', 60, [275, 9.1, 55.7, 1.2, 2.2, 1.3, 0.2, 536]),
  ('Crumpet', 'crumpets', 'crumpet (50 g)', 50, [180, 6.0, 37.0, 0.8, 2.0, 2.0, 0.1, 600]),
  ('Pancake', 'pancakes hotcakes', 'pancake (40 g)', 40, [227, 6.4, 28.3, 9.7, 0.9, 5.6, 2.1, 439]),
  ('Egg noodles, cooked', 'noodles hokkien', 'cup (160 g)', 160, [138, 4.5, 25.2, 2.1, 1.2, 0.4, 0.4, 5]),
  ('Rice noodles, cooked', 'noodles vermicelli', 'cup (176 g)', 176, [108, 1.8, 24.0, 0.2, 1.0, 0, 0, 19]),
  (
    'Instant noodles',
    'maggi 2 minute noodles ramen noodles',
    'packet (72 g)',
    72,
    [440, 9.5, 60.0, 18.0, 2.5, 2.0, 8.5, 1500],
  ),
  ('Couscous, cooked', 'couscous', 'cup (157 g)', 157, [112, 3.8, 23.2, 0.2, 1.4, 0.1, 0, 5]),
  ('Muesli bar', 'granola bar cereal bar', 'bar (31 g)', 31, [450, 7.0, 64.0, 18.0, 4.0, 28.0, 5.0, 200]),
  ('Crackers', 'cracker savoury biscuits', '5 crackers (16 g)', 16, [484, 7.3, 61.3, 23.2, 2.2, 7.6, 4.5, 800]),
  ('Corn chips', 'tortilla chips', 'handful (28 g)', 28, [489, 7.0, 64.0, 23.0, 5.3, 1.0, 3.0, 420]),
  ('Pretzels', 'pretzel', 'handful (28 g)', 28, [380, 10.3, 79.8, 2.9, 2.8, 2.8, 0.6, 1260]),
  ('Rice crackers', 'rice cracker', 'serve (25 g)', 25, [400, 7.0, 85.0, 3.0, 1.0, 3.0, 1.2, 600]),
  // Sweets and spreads
  ('Blueberry muffin', 'muffin cake', 'muffin (113 g)', 113, [377, 5.0, 54.0, 16.0, 1.5, 28.0, 3.0, 300]),
  ('Banana bread', 'banana cake', 'slice (60 g)', 60, [326, 4.3, 54.6, 10.5, 1.1, 32.0, 2.3, 302]),
  ('Doughnut', 'donut', 'doughnut (60 g)', 60, [421, 5.0, 49.0, 22.9, 1.5, 25.0, 10.8, 340]),
  ('Chocolate chip cookie', 'cookie biscuit', 'biscuit (15 g)', 15, [488, 5.4, 64.0, 24.0, 2.4, 34.0, 8.0, 330]),
  ('Brownie', 'chocolate brownie', 'piece (56 g)', 56, [466, 5.0, 60.0, 23.0, 2.0, 40.0, 7.0, 300]),
  ('Cheesecake', 'cheese cake', 'slice (80 g)', 80, [321, 5.5, 25.5, 22.5, 0.4, 21.8, 9.9, 300]),
  ('Frozen yoghurt', 'froyo frozen yogurt', 'scoop (100 g)', 100, [160, 4.0, 24.0, 5.6, 0, 22.0, 3.5, 70]),
  ('Jelly lollies', 'lollies gummies gummy candy sweets', 'handful (30 g)', 30, [340, 4.0, 80.0, 0, 0, 55.0, 0, 40]),
  ('Jam', 'jelly preserve', 'tbsp (20 g)', 20, [278, 0.4, 68.9, 0.1, 1.1, 48.5, 0, 32]),
  ('Vegemite', 'yeast extract marmite', 'thin spread (5 g)', 5, [185, 25.4, 20.0, 0.5, 0, 2.2, 0.1, 3300]),
  ('Chocolate hazelnut spread', 'nutella', 'tbsp (19 g)', 19, [539, 6.3, 57.5, 30.9, 3.4, 56.3, 10.6, 41]),
  ('Maple syrup', 'syrup', 'tbsp (20 g)', 20, [260, 0, 67.0, 0.1, 0, 60.5, 0, 12]),
  // More meat, fish, eggs and plant protein
  ('Turkey breast, roast', 'turkey', 'serve (100 g)', 100, [147, 30.1, 0, 2.1, 0, 0, 0.6, 99]),
  ('Lamb, roast', 'lamb leg roast lamb', 'serve (100 g)', 100, [191, 28.3, 0, 7.7, 0, 0, 2.8, 68]),
  ('Lamb chop', 'lamb cutlet lamb chops', 'chop (64 g)', 64, [282, 25.5, 0, 19.9, 0, 0, 8.5, 75]),
  ('Pork chop, cooked', 'pork', 'chop (150 g)', 150, [231, 28.9, 0, 12.8, 0, 0, 4.5, 57]),
  ('Sausage, cooked', 'sausages snag bbq sausage', 'sausage (65 g)', 65, [270, 13.0, 6.0, 21.5, 0.5, 1.0, 8.5, 750]),
  ('Chicken drumstick', 'drumstick chicken leg', 'drumstick (72 g)', 72, [212, 26.9, 0, 11.2, 0, 0, 3.1, 90]),
  ('Roast chicken', 'chicken rotisserie chicken', 'serve (150 g)', 150, [239, 27.3, 0, 13.6, 0, 0, 3.8, 82]),
  ('Chicken nuggets', 'nuggets', '6 nuggets (96 g)', 96, [296, 15.3, 16.4, 18.8, 1.0, 0.2, 3.3, 550]),
  (
    'White fish, cooked',
    'fish barramundi basa cod snapper flathead',
    'fillet (150 g)',
    150,
    [105, 22.8, 0, 0.9, 0, 0, 0.2, 78],
  ),
  ('Battered fish', 'fish and chips fried fish', 'piece (120 g)', 120, [232, 14.6, 17.0, 12.2, 0.5, 0.5, 2.0, 530]),
  ('Smoked salmon', 'salmon lox', 'serve (50 g)', 50, [117, 18.3, 0, 4.3, 0, 0, 0.9, 784]),
  ('Sardines', 'sardine canned fish', 'can drained (92 g)', 92, [208, 24.6, 0, 11.5, 0, 0, 1.5, 307]),
  ('Egg whites', 'egg white', '2 whites (66 g)', 66, [52, 10.9, 0.7, 0.2, 0, 0.7, 0, 166]),
  ('Scrambled eggs', 'eggs scrambled egg', '2 eggs (120 g)', 120, [149, 10.0, 1.6, 11.0, 0, 1.4, 3.3, 145]),
  ('Omelette', 'omelet eggs', '2-egg (120 g)', 120, [154, 10.6, 0.6, 11.7, 0, 0.4, 3.2, 155]),
  ('Beef jerky', 'jerky', 'serve (25 g)', 25, [410, 33.2, 11.0, 25.6, 1.8, 9.0, 10.9, 2081]),
  ('Kangaroo, cooked', 'roo kangaroo', 'serve (150 g)', 150, [134, 28.0, 0, 2.5, 0, 0, 0.6, 60]),
  ('Tempeh', '', 'serve (100 g)', 100, [192, 20.3, 7.6, 10.8, 0, 0, 2.2, 9]),
  ('Kidney beans, cooked', 'beans red kidney', 'cup (177 g)', 177, [127, 8.7, 22.8, 0.5, 6.4, 0.3, 0.1, 2]),
  ('Falafel', 'falafels', '3 pieces (51 g)', 51, [333, 13.3, 31.8, 17.8, 4.9, 2.0, 2.4, 294]),
  ('Protein bar', 'protein bar', 'bar (60 g)', 60, [360, 30.0, 33.0, 12.0, 8.0, 5.0, 5.0, 250]),
  // More dairy and plant milks
  ('Almond milk, unsweetened', 'almond milk', 'cup (250 ml)', 250, [15, 0.6, 0.3, 1.2, 0.2, 0, 0.1, 72]),
  ('Oat milk', 'oat milk', 'cup (250 ml)', 250, [46, 1.0, 6.7, 1.5, 0.8, 4.0, 0.2, 40]),
  ('Soy milk', 'soy milk soymilk', 'cup (250 ml)', 250, [54, 3.3, 6.3, 1.8, 0.6, 4.0, 0.2, 51]),
  ('Fruit yoghurt', 'yogurt yoghurt flavoured', 'tub (170 g)', 170, [95, 4.4, 15.9, 1.4, 0, 15.0, 0.9, 55]),
  ('Chocolate milk', 'flavoured milk choc milk', 'cup (250 ml)', 250, [83, 3.2, 10.3, 3.4, 0.8, 9.5, 2.1, 60]),
  ('Feta', 'cheese feta cheese', 'serve (30 g)', 30, [264, 14.2, 4.1, 21.3, 0, 4.1, 14.9, 1116]),
  ('Parmesan', 'cheese parmigiano', 'tbsp grated (5 g)', 5, [431, 38.5, 4.1, 28.6, 0, 0.9, 17.3, 1602]),
  ('Halloumi', 'cheese', 'serve (50 g)', 50, [321, 21.0, 2.2, 25.0, 0, 1.5, 17.0, 1100]),
  ('Cream cheese', 'philadelphia', 'tbsp (15 g)', 15, [342, 5.9, 4.1, 34.2, 0, 3.2, 19.3, 321]),
  ('Cream', 'thickened cream heavy cream', 'tbsp (15 g)', 15, [340, 2.8, 2.7, 36.1, 0, 2.7, 23.0, 27]),
  ('Sour cream', '', '2 tbsp (30 g)', 30, [198, 2.4, 4.6, 19.4, 0, 3.4, 10.1, 31]),
  // Oils, nuts, seeds and sauces
  ('Coconut oil', 'oil', 'tbsp (14 g)', 14, [892, 0, 0, 99.1, 0, 0, 82.5, 0]),
  ('Margarine', 'spread butter spread', 'tsp (5 g)', 5, [535, 0.2, 0.7, 59.0, 0, 0, 13.0, 600]),
  ('Mayonnaise', 'mayo aioli', 'tbsp (14 g)', 14, [680, 1.0, 0.6, 74.9, 0, 0.6, 11.7, 635]),
  ('Tomato sauce', 'ketchup', 'tbsp (17 g)', 17, [101, 1.0, 27.4, 0.1, 0.3, 21.3, 0, 907]),
  ('BBQ sauce', 'barbecue sauce', 'tbsp (17 g)', 17, [172, 0.8, 40.8, 0.6, 0.9, 33.2, 0.1, 1027]),
  ('Soy sauce', 'soya sauce', 'tbsp (16 g)', 16, [53, 8.1, 4.9, 0.6, 0.8, 0.4, 0.1, 5493]),
  ('Sweet chilli sauce', 'chili sauce', 'tbsp (20 g)', 20, [221, 0.4, 54.0, 0.4, 0.5, 50.0, 0, 900]),
  ('Salad dressing', 'italian dressing vinaigrette', 'tbsp (15 g)', 15, [240, 0.4, 12.2, 21.1, 0, 10.8, 3.2, 993]),
  ('Pesto', 'basil pesto', 'tbsp (16 g)', 16, [420, 5.0, 6.0, 41.0, 1.5, 2.0, 6.5, 900]),
  ('Guacamole', 'avocado dip', '2 tbsp (30 g)', 30, [150, 2.0, 8.6, 13.0, 6.0, 0.9, 1.9, 240]),
  ('Almond butter', 'nut butter', 'tbsp (16 g)', 16, [614, 21.0, 18.8, 55.5, 10.3, 4.4, 4.2, 7]),
  ('Pumpkin seeds', 'pepitas', 'handful (28 g)', 28, [559, 30.2, 10.7, 49.1, 6.0, 1.4, 8.7, 7]),
  ('Sunflower seeds', 'seeds', 'handful (28 g)', 28, [584, 20.8, 20.0, 51.5, 8.6, 2.6, 4.5, 9]),
  ('Macadamias', 'macadamia nuts', 'handful (28 g)', 28, [718, 7.9, 13.8, 75.8, 8.6, 4.6, 12.1, 5]),
  ('Pistachios', 'pistachio nuts', 'handful (28 g)', 28, [560, 20.2, 27.2, 45.3, 10.6, 7.7, 5.9, 1]),
  ('Mixed nuts', 'nuts', 'handful (28 g)', 28, [607, 20.0, 21.0, 54.0, 7.0, 4.5, 7.5, 10]),
  ('Trail mix', 'scroggin', 'serve (40 g)', 40, [462, 13.8, 44.9, 29.4, 4.0, 30.0, 5.6, 229]),
  // More takeaway and meals
  ('Meat pie', 'pie', 'pie (175 g)', 175, [250, 8.5, 22.0, 14.5, 1.3, 1.5, 7.0, 450]),
  ('Sausage roll', '', 'roll (100 g)', 100, [301, 8.6, 23.6, 19.3, 1.3, 1.5, 8.5, 600]),
  ('Fried rice', 'chicken fried rice', 'serve (300 g)', 300, [168, 6.3, 21.0, 6.2, 1.0, 1.0, 1.2, 400]),
  ('Pad thai', 'noodles', 'serve (400 g)', 400, [170, 7.0, 23.0, 5.5, 1.2, 6.0, 1.0, 500]),
  ('Butter chicken', 'curry chicken curry', 'serve (300 g)', 300, [150, 11.0, 6.0, 9.0, 1.0, 3.5, 4.5, 450]),
  ('Sushi roll', 'sushi', '6 pieces (180 g)', 180, [145, 5.0, 24.0, 3.3, 1.2, 4.5, 0.6, 380]),
  ('Chicken burrito', 'burrito', 'burrito (300 g)', 300, [185, 9.5, 21.0, 7.0, 3.0, 1.5, 2.8, 450]),
  ('Kebab', 'doner kebab souvlaki gyros yiros', 'kebab (400 g)', 400, [215, 12.0, 18.0, 10.5, 1.5, 2.5, 4.0, 550]),
  ('Chicken Caesar salad', 'caesar salad', 'bowl (300 g)', 300, [135, 9.0, 5.5, 8.7, 1.5, 1.5, 2.5, 400]),
  ('Spaghetti bolognese', 'bolognese spag bol', 'bowl (400 g)', 400, [130, 7.0, 15.5, 4.5, 1.8, 3.0, 1.7, 300]),
  ('Lasagne', 'lasagna', 'serve (300 g)', 300, [150, 8.5, 13.5, 7.0, 1.2, 3.0, 3.5, 380]),
  (
    'Chicken schnitzel',
    'schnitzel parma parmigiana',
    'schnitzel (200 g)',
    200,
    [255, 20.0, 15.0, 13.0, 0.8, 0.8, 2.5, 420],
  ),
  ('Hot dog', 'hotdog', 'hot dog (100 g)', 100, [240, 10.0, 24.0, 11.5, 1.0, 4.0, 4.2, 680]),
  (
    'Ham and cheese toastie',
    'toasted sandwich toastie sandwich',
    'sandwich (150 g)',
    150,
    [265, 14.0, 25.0, 12.0, 1.5, 3.0, 6.0, 900],
  ),
  ('Bacon and egg roll', 'bacon egg roll', 'roll (200 g)', 200, [245, 12.5, 22.0, 12.0, 1.2, 3.0, 4.2, 650]),
  ('Ramen', 'ramen tonkotsu noodle soup', 'bowl (600 g)', 600, [95, 4.5, 11.0, 3.5, 0.6, 0.5, 1.2, 500]),
  ('Dumplings', 'gyoza dim sum dumpling', '6 dumplings (150 g)', 150, [200, 9.0, 24.0, 7.5, 1.5, 1.5, 2.5, 450]),
  ('Spring roll', 'spring rolls', 'roll (64 g)', 64, [248, 5.0, 26.0, 13.8, 1.8, 2.5, 2.2, 400]),
  ('Nachos', 'nachos with cheese', 'serve (200 g)', 200, [300, 8.0, 32.0, 16.0, 3.0, 1.5, 6.0, 480]),
  ('Mac and cheese', 'macaroni cheese', 'cup (200 g)', 200, [164, 6.6, 20.0, 6.5, 1.0, 2.5, 3.0, 400]),
  ('Pumpkin soup', 'soup', 'bowl (300 g)', 300, [50, 1.2, 7.0, 2.0, 1.0, 3.0, 1.0, 300]),
  // More drinks (per 100 ml)
  ('Apple juice', 'juice', 'glass (250 ml)', 250, [46, 0.1, 11.3, 0.1, 0.2, 9.6, 0, 4]),
  ('Lemonade', 'sprite soft drink soda', 'can (375 ml)', 375, [41, 0, 10.4, 0, 0, 10.0, 0, 10]),
  ('Diet cola', 'coke zero diet coke pepsi max', 'can (375 ml)', 375, [1, 0.1, 0, 0, 0, 0, 0, 10]),
  ('Sports drink', 'gatorade powerade', 'bottle (600 ml)', 600, [26, 0, 6.4, 0, 0, 5.6, 0, 41]),
  ('Energy drink', 'red bull monster v', 'can (250 ml)', 250, [45, 0, 11.0, 0, 0, 11.0, 0, 80]),
  ('Iced coffee', 'flavoured milk coffee', 'bottle (500 ml)', 500, [70, 3.4, 9.0, 2.2, 0, 9.0, 1.4, 50]),
  ('Hot chocolate', 'cocoa drinking chocolate', 'mug (250 ml)', 250, [77, 3.5, 10.5, 2.3, 1.0, 9.5, 1.4, 45]),
  ('Fruit smoothie', 'smoothie', 'glass (400 ml)', 400, [68, 2.0, 13.5, 0.8, 1.0, 11.0, 0.4, 25]),
  ('Protein shake', 'ready to drink protein', 'bottle (330 ml)', 330, [60, 7.0, 4.0, 1.5, 0, 3.0, 0.8, 60]),
  ('Kombucha', '', 'bottle (330 ml)', 330, [13, 0, 3.0, 0, 0, 2.5, 0, 5]),
  ('Coconut water', '', 'carton (330 ml)', 330, [19, 0.7, 3.7, 0.2, 1.1, 2.6, 0.2, 105]),
  ('White wine', 'wine sauvignon chardonnay', 'glass (150 ml)', 150, [82, 0.1, 2.6, 0, 0, 1.0, 0, 5]),
  ('Cider', '', 'can (375 ml)', 375, [50, 0, 5.9, 0, 0, 5.0, 0, 4]),
  ('Spirits', 'vodka gin rum whisky whiskey', 'shot (30 ml)', 30, [231, 0, 0, 0, 0, 0, 0, 1]),
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
    liquid: r.$3.contains(' ml)'),
  );
}
