/// HUX Indian Food Table (starter)
/// -------------------------------
/// Per-portion nutrients for common Indian dishes, in household units.
///
/// ⚠️ DATA STATUS: these are APPROXIMATE typical home-style values, for a
/// first working version. Every row is marked `verified: false` until a
/// qualified nutritionist checks it against an authoritative source
/// (e.g. ICMR-NIN's Indian Food Composition Tables, or a licensed Indian
/// recipe database). Home recipes vary a lot (oil, ghee, portion size),
/// so the UI always says "approx." — never presents these as exact.
///
/// To grow it: add rows here (or load a bigger licensed table later);
/// matching, text parsing and protein suggestions pick them up as-is.
library;

import 'nutrients.dart';

class FoodItem {
  final String id;
  final String name;

  /// Other names people type or the AI may return (Hindi, regional,
  /// spellings). Lower-case.
  final List<String> aliases;
  final FoodUnit unit;
  final Nutrients perUnit;

  /// Suitable for vegetarians / contains egg / contains meat-fish.
  final bool veg;
  final bool egg;

  /// Can be suggested to fill a protein gap.
  final bool proteinSource;
  final bool verified;

  const FoodItem({
    required this.id,
    required this.name,
    required this.aliases,
    required this.unit,
    required this.perUnit,
    this.veg = true,
    this.egg = false,
    this.proteinSource = false,
    this.verified = false,
  });
}


const indianFoods = <FoodItem>[
  // ---- breads & grains ----
  FoodItem(id: 'roti', name: 'Roti / chapati', aliases: ['roti', 'chapati', 'chapatti', 'phulka', 'fulka'],
      unit: FoodUnit.roti, perUnit: Nutrients(kcal: 100, proteinG: 3, carbsG: 18, fatG: 2, fiberG: 2.5)),
  FoodItem(id: 'paratha', name: 'Plain paratha', aliases: ['paratha', 'parantha', 'plain paratha'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 180, proteinG: 4, carbsG: 25, fatG: 7, fiberG: 2.5)),
  FoodItem(id: 'aloo_paratha', name: 'Aloo paratha', aliases: ['aloo paratha', 'alu paratha', 'potato paratha'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 250, proteinG: 5, carbsG: 35, fatG: 10, fiberG: 3)),
  FoodItem(id: 'rice', name: 'Plain rice', aliases: ['rice', 'chawal', 'annam', 'steamed rice', 'white rice'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 195, proteinG: 4, carbsG: 43, fatG: 0.4, fiberG: 0.6)),
  FoodItem(id: 'veg_pulao', name: 'Veg pulao', aliases: ['pulao', 'veg pulao', 'pulav'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 220, proteinG: 4.5, carbsG: 35, fatG: 7, fiberG: 2)),
  FoodItem(id: 'chicken_biryani', name: 'Chicken biryani', aliases: ['biryani', 'chicken biryani', 'biriyani'],
      unit: FoodUnit.plate, veg: false, proteinSource: true,
      perUnit: Nutrients(kcal: 500, proteinG: 22, carbsG: 60, fatG: 18, fiberG: 2)),
  FoodItem(id: 'veg_biryani', name: 'Veg biryani', aliases: ['veg biryani', 'vegetable biryani'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 420, proteinG: 9, carbsG: 65, fatG: 14, fiberG: 4)),

  // ---- South Indian ----
  FoodItem(id: 'idli', name: 'Idli', aliases: ['idli', 'idly'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 50, proteinG: 2, carbsG: 10, fatG: 0.3, fiberG: 0.5)),
  FoodItem(id: 'dosa', name: 'Plain dosa', aliases: ['dosa', 'plain dosa', 'dosai'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 150, proteinG: 3.5, carbsG: 25, fatG: 4, fiberG: 1)),
  FoodItem(id: 'masala_dosa', name: 'Masala dosa', aliases: ['masala dosa'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 300, proteinG: 6, carbsG: 45, fatG: 11, fiberG: 3)),
  FoodItem(id: 'sambar', name: 'Sambar', aliases: ['sambar', 'sambhar', 'saaru'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 110, proteinG: 5, carbsG: 15, fatG: 3, fiberG: 4)),
  FoodItem(id: 'upma', name: 'Upma', aliases: ['upma', 'uppittu', 'rava upma'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 200, proteinG: 5, carbsG: 30, fatG: 7, fiberG: 2)),
  FoodItem(id: 'poha', name: 'Poha', aliases: ['poha', 'avalakki', 'aval', 'chivda poha'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 180, proteinG: 3.5, carbsG: 32, fatG: 5, fiberG: 1.5)),

  // ---- dals & legumes ----
  FoodItem(id: 'dal', name: 'Dal (toor/moong)', aliases: ['dal', 'daal', 'toor dal', 'moong dal', 'pappu', 'arhar dal', 'dal tadka'],
      unit: FoodUnit.katori, proteinSource: true,
      perUnit: Nutrients(kcal: 150, proteinG: 7, carbsG: 20, fatG: 4, fiberG: 4)),
  FoodItem(id: 'rajma', name: 'Rajma curry', aliases: ['rajma', 'rajma masala', 'kidney beans'],
      unit: FoodUnit.katori, proteinSource: true,
      perUnit: Nutrients(kcal: 200, proteinG: 8, carbsG: 26, fatG: 7, fiberG: 7)),
  FoodItem(id: 'chole', name: 'Chole', aliases: ['chole', 'chana masala', 'chickpea curry', 'chana'],
      unit: FoodUnit.katori, proteinSource: true,
      perUnit: Nutrients(kcal: 210, proteinG: 8, carbsG: 28, fatG: 8, fiberG: 7)),
  FoodItem(id: 'sprouts', name: 'Sprouts salad', aliases: ['sprouts', 'moong sprouts', 'sprout salad'],
      unit: FoodUnit.katori, proteinSource: true,
      perUnit: Nutrients(kcal: 100, proteinG: 7, carbsG: 15, fatG: 1, fiberG: 4)),
  FoodItem(id: 'soya_chunks', name: 'Soya chunks (cooked)', aliases: ['soya chunks', 'soya', 'meal maker', 'nutrela'],
      unit: FoodUnit.katori, proteinSource: true,
      perUnit: Nutrients(kcal: 105, proteinG: 15.6, carbsG: 10, fatG: 0.2, fiberG: 4)),

  // ---- dairy & paneer ----
  FoodItem(id: 'paneer', name: 'Paneer (100 g)', aliases: ['paneer', 'cottage cheese'],
      unit: FoodUnit.piece, proteinSource: true,
      perUnit: Nutrients(kcal: 265, proteinG: 18, carbsG: 1.2, fatG: 20.8)),
  FoodItem(id: 'paneer_curry', name: 'Paneer curry', aliases: ['paneer curry', 'paneer butter masala', 'palak paneer', 'kadai paneer', 'matar paneer'],
      unit: FoodUnit.katori, proteinSource: true,
      perUnit: Nutrients(kcal: 280, proteinG: 12, carbsG: 10, fatG: 21, fiberG: 2)),
  FoodItem(id: 'curd', name: 'Curd / dahi', aliases: ['curd', 'dahi', 'yogurt', 'perugu', 'mosaru', 'thayir'],
      unit: FoodUnit.katori, proteinSource: true,
      perUnit: Nutrients(kcal: 90, proteinG: 5, carbsG: 7, fatG: 4.5)),
  FoodItem(id: 'milk', name: 'Milk (toned)', aliases: ['milk', 'doodh', 'paalu'],
      unit: FoodUnit.glass, proteinSource: true,
      perUnit: Nutrients(kcal: 120, proteinG: 6, carbsG: 9.5, fatG: 6)),
  FoodItem(id: 'chai', name: 'Chai (milk + sugar)', aliases: ['chai', 'tea', 'masala chai', 'cutting chai'],
      unit: FoodUnit.cup, perUnit: Nutrients(kcal: 90, proteinG: 2.5, carbsG: 13, fatG: 3)),

  // ---- eggs, meat, fish ----
  FoodItem(id: 'egg', name: 'Boiled egg', aliases: ['egg', 'boiled egg', 'anda', 'eggs'],
      unit: FoodUnit.piece, veg: false, egg: true, proteinSource: true,
      perUnit: Nutrients(kcal: 75, proteinG: 6.3, carbsG: 0.6, fatG: 5)),
  FoodItem(id: 'omelette', name: 'Omelette (2 eggs)', aliases: ['omelette', 'omelet', 'anda bhurji', 'egg bhurji'],
      unit: FoodUnit.plate, veg: false, egg: true, proteinSource: true,
      perUnit: Nutrients(kcal: 190, proteinG: 13, carbsG: 1, fatG: 15)),
  FoodItem(id: 'chicken_curry', name: 'Chicken curry', aliases: ['chicken curry', 'chicken', 'butter chicken', 'kozhi curry'],
      unit: FoodUnit.katori, veg: false, proteinSource: true,
      perUnit: Nutrients(kcal: 250, proteinG: 20, carbsG: 6, fatG: 16, fiberG: 1)),
  FoodItem(id: 'fish_curry', name: 'Fish curry', aliases: ['fish curry', 'fish', 'machli', 'meen curry'],
      unit: FoodUnit.katori, veg: false, proteinSource: true,
      perUnit: Nutrients(kcal: 200, proteinG: 18, carbsG: 5, fatG: 12, fiberG: 1)),

  // ---- vegetables ----
  FoodItem(id: 'mixed_sabzi', name: 'Mixed veg sabzi', aliases: ['sabzi', 'sabji', 'mixed veg', 'vegetable curry', 'poriyal', 'palya', 'thoran'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 120, proteinG: 3, carbsG: 12, fatG: 7, fiberG: 4)),
  FoodItem(id: 'aloo_sabzi', name: 'Aloo sabzi', aliases: ['aloo sabzi', 'aloo', 'potato curry', 'aloo gobi'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 160, proteinG: 2.5, carbsG: 22, fatG: 7, fiberG: 3)),

  // ---- snacks, fruit, sweets ----
  FoodItem(id: 'samosa', name: 'Samosa', aliases: ['samosa'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 260, proteinG: 4, carbsG: 30, fatG: 14, fiberG: 2)),
  FoodItem(id: 'peanuts', name: 'Peanuts', aliases: ['peanuts', 'moongphali', 'groundnuts', 'palli'],
      unit: FoodUnit.handful, proteinSource: true,
      perUnit: Nutrients(kcal: 170, proteinG: 7.5, carbsG: 5, fatG: 14, fiberG: 2.5)),
  FoodItem(id: 'banana', name: 'Banana', aliases: ['banana', 'kela', 'arati pandu'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 105, proteinG: 1.3, carbsG: 27, fatG: 0.4, fiberG: 3)),
  FoodItem(id: 'gulab_jamun', name: 'Gulab jamun', aliases: ['gulab jamun', 'jamun'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 150, proteinG: 2, carbsG: 25, fatG: 5)),
];

class IndianFoodDb {
  const IndianFoodDb._();

  static FoodItem? byId(String id) {
    for (final f in indianFoods) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Best match for a free-text dish name, or null. Exact alias first,
  /// then the longest alias contained in the text ("2 aloo paratha"
  /// matches "aloo paratha", not "paratha").
  static FoodItem? match(String text) {
    final q = _normalise(text);
    if (q.isEmpty) return null;
    // "2 rotis", "3 idlis", "eggs": try the singular when the plural
    // doesn't match (most aliases are singular).
    final direct = _match(q);
    if (direct != null) return direct;
    final singular = q.split(' ').map(_singular).join(' ');
    return singular == q ? null : _match(singular);
  }

  static String _singular(String w) {
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    return w;
  }

  static FoodItem? _match(String q) {
    for (final f in indianFoods) {
      if (f.aliases.contains(q) || _normalise(f.name) == q) return f;
    }
    FoodItem? best;
    var bestLen = 0;
    for (final f in indianFoods) {
      for (final a in f.aliases) {
        if (a.length > bestLen && _containsWord(q, a)) {
          best = f;
          bestLen = a.length;
        }
      }
    }
    return best;
  }

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _containsWord(String haystack, String needle) =>
      RegExp('(^| )${RegExp.escape(needle)}( |\$)').hasMatch(haystack);
}
