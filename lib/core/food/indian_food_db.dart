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

  // ---- more dishes: regional, street food, global, fruit, drinks ----
  FoodItem(id: 'naan', name: 'Naan', aliases: ['naan', 'nan', 'plain naan', 'tandoori roti'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 260, proteinG: 8, carbsG: 45, fatG: 5, fiberG: 2)),
  FoodItem(id: 'butter_naan', name: 'Butter naan', aliases: ['butter naan', 'garlic naan'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 320, proteinG: 8, carbsG: 45, fatG: 12, fiberG: 2)),
  FoodItem(id: 'kulcha', name: 'Kulcha', aliases: ['kulcha', 'amritsari kulcha'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 280, proteinG: 7, carbsG: 48, fatG: 7, fiberG: 2)),
  FoodItem(id: 'puri', name: 'Puri', aliases: ['puri', 'poori', 'pooris'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 100, proteinG: 2, carbsG: 12, fatG: 5, fiberG: 0.5)),
  FoodItem(id: 'bhatura', name: 'Bhatura', aliases: ['bhatura', 'bhature', 'chole bhature'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 300, proteinG: 7, carbsG: 40, fatG: 13, fiberG: 2)),
  FoodItem(id: 'thepla', name: 'Thepla', aliases: ['thepla', 'methi thepla'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 120, proteinG: 3, carbsG: 16, fatG: 5, fiberG: 2)),
  FoodItem(id: 'millet_roti', name: 'Millet roti (bajra/jowar)', aliases: ['bajra roti', 'jowar roti', 'bhakri', 'jonna rotte', 'jolada rotti', 'millet roti', 'ragi roti'],
      unit: FoodUnit.roti, perUnit: Nutrients(kcal: 105, proteinG: 3, carbsG: 20, fatG: 1.5, fiberG: 3)),
  FoodItem(id: 'ragi_mudde', name: 'Ragi mudde', aliases: ['ragi mudde', 'ragi ball', 'ragi sangati', 'sangati'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 150, proteinG: 3, carbsG: 32, fatG: 0.8, fiberG: 4)),
  FoodItem(id: 'jeera_rice', name: 'Jeera rice', aliases: ['jeera rice', 'fried jeera rice'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 210, proteinG: 4, carbsG: 40, fatG: 4, fiberG: 1)),
  FoodItem(id: 'curd_rice', name: 'Curd rice', aliases: ['curd rice', 'perugu annam', 'thayir sadam', 'mosaru anna', 'dahi chawal'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 200, proteinG: 6, carbsG: 30, fatG: 6, fiberG: 1)),
  FoodItem(id: 'lemon_rice', name: 'Lemon rice', aliases: ['lemon rice', 'chitranna', 'nimmakaya pulihora'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 230, proteinG: 4, carbsG: 38, fatG: 7, fiberG: 2)),
  FoodItem(id: 'tamarind_rice', name: 'Tamarind rice', aliases: ['pulihora', 'puliyogare', 'puliyodarai', 'tamarind rice'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 250, proteinG: 4, carbsG: 40, fatG: 8, fiberG: 2)),
  FoodItem(id: 'khichdi', name: 'Khichdi', aliases: ['khichdi', 'khichri', 'moong dal khichdi', 'pongal rice'],
      unit: FoodUnit.katori, proteinSource: true, perUnit: Nutrients(kcal: 180, proteinG: 7, carbsG: 30, fatG: 4, fiberG: 3)),
  FoodItem(id: 'veg_fried_rice', name: 'Veg fried rice', aliases: ['fried rice', 'veg fried rice', 'schezwan fried rice'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 400, proteinG: 8, carbsG: 62, fatG: 13, fiberG: 3)),
  FoodItem(id: 'chicken_fried_rice', name: 'Chicken fried rice', aliases: ['chicken fried rice', 'chicken schezwan fried rice'],
      unit: FoodUnit.plate, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 480, proteinG: 20, carbsG: 60, fatG: 16, fiberG: 2)),
  FoodItem(id: 'egg_fried_rice', name: 'Egg fried rice', aliases: ['egg fried rice'],
      unit: FoodUnit.plate, veg: false, egg: true, proteinSource: true, perUnit: Nutrients(kcal: 450, proteinG: 15, carbsG: 60, fatG: 15, fiberG: 2)),
  FoodItem(id: 'mutton_biryani', name: 'Mutton biryani', aliases: ['mutton biryani', 'gosht biryani', 'goat biryani'],
      unit: FoodUnit.plate, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 580, proteinG: 26, carbsG: 60, fatG: 24, fiberG: 2)),
  FoodItem(id: 'egg_biryani', name: 'Egg biryani', aliases: ['egg biryani', 'anda biryani'],
      unit: FoodUnit.plate, veg: false, egg: true, proteinSource: true, perUnit: Nutrients(kcal: 480, proteinG: 17, carbsG: 62, fatG: 17, fiberG: 2)),
  FoodItem(id: 'bread', name: 'Bread slice', aliases: ['bread', 'white bread', 'toast', 'bread slice', 'pav', 'bun'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 75, proteinG: 2.5, carbsG: 14, fatG: 1, fiberG: 0.7)),
  FoodItem(id: 'brown_bread', name: 'Brown bread slice', aliases: ['brown bread', 'whole wheat bread', 'multigrain bread'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 70, proteinG: 3, carbsG: 12, fatG: 1, fiberG: 2)),
  FoodItem(id: 'bread_omelette', name: 'Bread omelette', aliases: ['bread omelette', 'bread omelet'],
      unit: FoodUnit.plate, veg: false, egg: true, proteinSource: true, perUnit: Nutrients(kcal: 330, proteinG: 15, carbsG: 30, fatG: 17, fiberG: 1)),
  FoodItem(id: 'oats', name: 'Oats porridge', aliases: ['oats', 'oatmeal', 'oats porridge', 'masala oats'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 150, proteinG: 5, carbsG: 27, fatG: 3, fiberG: 4)),
  FoodItem(id: 'cornflakes', name: 'Cornflakes with milk', aliases: ['cornflakes', 'corn flakes', 'muesli', 'cereal'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 200, proteinG: 6, carbsG: 35, fatG: 4, fiberG: 1)),
  FoodItem(id: 'pasta', name: 'Pasta', aliases: ['pasta', 'white sauce pasta', 'red sauce pasta', 'macaroni', 'spaghetti', 'penne'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 380, proteinG: 12, carbsG: 55, fatG: 12, fiberG: 3)),
  FoodItem(id: 'chicken_pasta', name: 'Chicken pasta', aliases: ['chicken pasta'],
      unit: FoodUnit.plate, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 480, proteinG: 25, carbsG: 55, fatG: 16, fiberG: 3)),
  FoodItem(id: 'veg_noodles', name: 'Veg noodles', aliases: ['noodles', 'noodle', 'veg noodles', 'hakka noodles', 'veg hakka noodles', 'chowmein', 'chow mein', 'schezwan noodles'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 380, proteinG: 8, carbsG: 55, fatG: 13, fiberG: 3)),
  FoodItem(id: 'chicken_noodles', name: 'Chicken noodles', aliases: ['chicken noodles', 'chicken noodle', 'chicken hakka noodles', 'chicken chowmein', 'chicken chow mein', 'chicken schezwan noodles'],
      unit: FoodUnit.plate, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 450, proteinG: 20, carbsG: 55, fatG: 15, fiberG: 2)),
  FoodItem(id: 'egg_noodles', name: 'Egg noodles', aliases: ['egg noodles', 'egg hakka noodles', 'egg chowmein'],
      unit: FoodUnit.plate, veg: false, egg: true, proteinSource: true, perUnit: Nutrients(kcal: 420, proteinG: 15, carbsG: 55, fatG: 14, fiberG: 2)),
  FoodItem(id: 'instant_noodles', name: 'Instant noodles (1 pack)', aliases: ['maggi', 'maggie', 'instant noodles', 'top ramen', 'yippee', 'ramen', 'cup noodles'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 350, proteinG: 8, carbsG: 48, fatG: 14, fiberG: 2)),
  FoodItem(id: 'thukpa_soup', name: 'Thukpa / noodle soup', aliases: ['noodle soup', 'chicken noodle soup'],
      unit: FoodUnit.katori, veg: false, perUnit: Nutrients(kcal: 220, proteinG: 12, carbsG: 28, fatG: 6, fiberG: 2)),
  FoodItem(id: 'vada', name: 'Medu vada', aliases: ['vada', 'medu vada', 'vadai', 'garelu', 'uddina vade', 'wada'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 140, proteinG: 4, carbsG: 14, fatG: 8, fiberG: 2)),
  FoodItem(id: 'pongal', name: 'Ven pongal', aliases: ['pongal', 'ven pongal', 'khara pongal'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 220, proteinG: 6, carbsG: 30, fatG: 8, fiberG: 2)),
  FoodItem(id: 'pesarattu', name: 'Pesarattu', aliases: ['pesarattu', 'moong dosa', 'green gram dosa'],
      unit: FoodUnit.piece, proteinSource: true, perUnit: Nutrients(kcal: 180, proteinG: 9, carbsG: 26, fatG: 4, fiberG: 4)),
  FoodItem(id: 'uttapam', name: 'Uttapam', aliases: ['uttapam', 'uthappam', 'onion uttapam'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 220, proteinG: 6, carbsG: 35, fatG: 6, fiberG: 3)),
  FoodItem(id: 'rava_dosa', name: 'Rava dosa', aliases: ['rava dosa', 'onion rava dosa'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 180, proteinG: 3, carbsG: 25, fatG: 7, fiberG: 1)),
  FoodItem(id: 'appam', name: 'Appam', aliases: ['appam', 'palappam'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 120, proteinG: 2, carbsG: 24, fatG: 2, fiberG: 1)),
  FoodItem(id: 'puttu', name: 'Puttu', aliases: ['puttu', 'puttu kadala'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 220, proteinG: 4, carbsG: 45, fatG: 2, fiberG: 2)),
  FoodItem(id: 'idiyappam', name: 'Idiyappam', aliases: ['idiyappam', 'string hoppers', 'nool puttu', 'sevai'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 60, proteinG: 1, carbsG: 13, fatG: 0.2, fiberG: 0.4)),
  FoodItem(id: 'rasam', name: 'Rasam', aliases: ['rasam', 'chaaru', 'saaru rasam'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 60, proteinG: 2, carbsG: 8, fatG: 2, fiberG: 1)),
  FoodItem(id: 'chutney', name: 'Coconut chutney', aliases: ['chutney', 'coconut chutney', 'pachadi', 'groundnut chutney'],
      unit: FoodUnit.spoon, perUnit: Nutrients(kcal: 35, proteinG: 0.6, carbsG: 1.5, fatG: 3, fiberG: 1)),
  FoodItem(id: 'ragi_java', name: 'Ragi malt', aliases: ['ragi java', 'ragi malt', 'ragi ambali', 'ambali', 'ragi porridge'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 100, proteinG: 2, carbsG: 20, fatG: 1, fiberG: 2)),
  FoodItem(id: 'bisi_bele_bath', name: 'Bisi bele bath', aliases: ['bisi bele bath', 'bisibelebath', 'sambar rice', 'sambar sadam'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 250, proteinG: 7, carbsG: 38, fatG: 8, fiberG: 4)),
  FoodItem(id: 'akki_roti', name: 'Akki roti', aliases: ['akki roti', 'rice roti', 'pathiri'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 180, proteinG: 3, carbsG: 32, fatG: 4, fiberG: 2)),
  FoodItem(id: 'papad', name: 'Papad', aliases: ['papad', 'appalam', 'papadum', 'appadam'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 40, proteinG: 2, carbsG: 6, fatG: 1, fiberG: 1)),
  FoodItem(id: 'kozhukatta', name: 'Kozhukattai / modak', aliases: ['kozhukattai', 'kozhukatta', 'modak', 'kudumulu'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 90, proteinG: 1.5, carbsG: 16, fatG: 2.5, fiberG: 1)),
  FoodItem(id: 'dal_makhani', name: 'Dal makhani', aliases: ['dal makhani', 'maa ki dal', 'kali dal'],
      unit: FoodUnit.katori, proteinSource: true, perUnit: Nutrients(kcal: 250, proteinG: 9, carbsG: 24, fatG: 13, fiberG: 6)),
  FoodItem(id: 'kadhi', name: 'Kadhi', aliases: ['kadhi', 'kadhi pakora', 'majjiga pulusu', 'mor kuzhambu'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 150, proteinG: 5, carbsG: 12, fatG: 9, fiberG: 1)),
  FoodItem(id: 'kala_chana', name: 'Black chana', aliases: ['kala chana', 'black chana', 'sundal', 'chana sundal', 'boiled chana', 'chana chaat'],
      unit: FoodUnit.katori, proteinSource: true, perUnit: Nutrients(kcal: 180, proteinG: 9, carbsG: 27, fatG: 3, fiberG: 7)),
  FoodItem(id: 'lobia', name: 'Lobia / beans curry', aliases: ['lobia', 'rajma beans', 'black eyed beans', 'alasandalu', 'bobbarlu'],
      unit: FoodUnit.katori, proteinSource: true, perUnit: Nutrients(kcal: 180, proteinG: 9, carbsG: 27, fatG: 3, fiberG: 6)),
  FoodItem(id: 'besan_chilla', name: 'Besan chilla', aliases: ['besan chilla', 'chilla', 'cheela', 'besan cheela'],
      unit: FoodUnit.piece, proteinSource: true, perUnit: Nutrients(kcal: 120, proteinG: 6, carbsG: 14, fatG: 4, fiberG: 3)),
  FoodItem(id: 'moong_chilla', name: 'Moong dal chilla', aliases: ['moong chilla', 'moong dal chilla'],
      unit: FoodUnit.piece, proteinSource: true, perUnit: Nutrients(kcal: 110, proteinG: 7, carbsG: 14, fatG: 3, fiberG: 3)),
  FoodItem(id: 'dhokla', name: 'Dhokla', aliases: ['dhokla', 'khaman'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 40, proteinG: 2, carbsG: 6, fatG: 1, fiberG: 0.5)),
  FoodItem(id: 'tofu', name: 'Tofu (100 g)', aliases: ['tofu', 'bean curd'],
      unit: FoodUnit.piece, proteinSource: true, perUnit: Nutrients(kcal: 145, proteinG: 15, carbsG: 3, fatG: 8, fiberG: 2)),
  FoodItem(id: 'tofu_curry', name: 'Tofu curry', aliases: ['tofu curry', 'tofu stir fry', 'tofu bhurji'],
      unit: FoodUnit.katori, proteinSource: true, perUnit: Nutrients(kcal: 200, proteinG: 14, carbsG: 8, fatG: 13, fiberG: 2)),
  FoodItem(id: 'buttermilk', name: 'Buttermilk', aliases: ['buttermilk', 'chaas', 'majjiga', 'moru', 'majjige', 'mattha'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 40, proteinG: 2, carbsG: 4, fatG: 1.5, fiberG: 0)),
  FoodItem(id: 'lassi', name: 'Sweet lassi', aliases: ['lassi', 'sweet lassi', 'mango lassi'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 180, proteinG: 6, carbsG: 26, fatG: 5, fiberG: 0)),
  FoodItem(id: 'paneer_bhurji', name: 'Paneer bhurji', aliases: ['paneer bhurji'],
      unit: FoodUnit.katori, proteinSource: true, perUnit: Nutrients(kcal: 260, proteinG: 14, carbsG: 6, fatG: 20, fiberG: 1)),
  FoodItem(id: 'paneer_tikka', name: 'Paneer tikka', aliases: ['paneer tikka', 'tandoori paneer'],
      unit: FoodUnit.plate, proteinSource: true, perUnit: Nutrients(kcal: 300, proteinG: 20, carbsG: 8, fatG: 21, fiberG: 2)),
  FoodItem(id: 'ghee', name: 'Ghee', aliases: ['ghee', 'neyyi', 'tuppa'],
      unit: FoodUnit.spoon, perUnit: Nutrients(kcal: 45, proteinG: 0, carbsG: 0, fatG: 5, fiberG: 0)),
  FoodItem(id: 'butter', name: 'Butter', aliases: ['butter', 'makhan', 'venna'],
      unit: FoodUnit.spoon, perUnit: Nutrients(kcal: 36, proteinG: 0, carbsG: 0, fatG: 4, fiberG: 0)),
  FoodItem(id: 'cheese', name: 'Cheese slice', aliases: ['cheese', 'cheese slice'],
      unit: FoodUnit.piece, proteinSource: true, perUnit: Nutrients(kcal: 60, proteinG: 4, carbsG: 1, fatG: 5, fiberG: 0)),
  FoodItem(id: 'coffee', name: 'Coffee (milk + sugar)', aliases: ['coffee', 'filter coffee', 'kaapi', 'cold coffee', 'cappuccino', 'latte'],
      unit: FoodUnit.cup, perUnit: Nutrients(kcal: 80, proteinG: 2, carbsG: 10, fatG: 3, fiberG: 0)),
  FoodItem(id: 'black_coffee', name: 'Black coffee', aliases: ['black coffee', 'americano', 'espresso'],
      unit: FoodUnit.cup, perUnit: Nutrients(kcal: 5, proteinG: 0.3, carbsG: 0, fatG: 0, fiberG: 0)),
  FoodItem(id: 'green_tea', name: 'Green tea', aliases: ['green tea', 'black tea', 'lemon tea', 'herbal tea'],
      unit: FoodUnit.cup, perUnit: Nutrients(kcal: 2, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0)),
  FoodItem(id: 'protein_shake', name: 'Protein shake (1 scoop)', aliases: ['protein shake', 'whey', 'whey protein', 'protein powder'],
      unit: FoodUnit.glass, proteinSource: true, perUnit: Nutrients(kcal: 120, proteinG: 24, carbsG: 3, fatG: 1.5, fiberG: 0)),
  FoodItem(id: 'milkshake', name: 'Milkshake', aliases: ['milkshake', 'milk shake', 'banana shake', 'mango shake', 'badam milk'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 250, proteinG: 8, carbsG: 35, fatG: 8, fiberG: 1)),
  FoodItem(id: 'egg_curry', name: 'Egg curry (2 eggs)', aliases: ['egg curry', 'anda curry', 'egg masala', 'guddu koora', 'mutta curry', 'motte saaru'],
      unit: FoodUnit.katori, veg: false, egg: true, proteinSource: true, perUnit: Nutrients(kcal: 220, proteinG: 13, carbsG: 6, fatG: 16, fiberG: 1)),
  FoodItem(id: 'fried_egg', name: 'Fried egg', aliases: ['fried egg', 'egg fry', 'half fry', 'bulls eye', 'sunny side up'],
      unit: FoodUnit.piece, veg: false, egg: true, proteinSource: true, perUnit: Nutrients(kcal: 90, proteinG: 6, carbsG: 0.5, fatG: 7, fiberG: 0)),
  FoodItem(id: 'chicken_tikka', name: 'Chicken tikka / tandoori', aliases: ['chicken tikka', 'tandoori chicken', 'grilled chicken', 'chicken kebab', 'chicken kabab', 'chicken seekh kebab'],
      unit: FoodUnit.plate, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 280, proteinG: 36, carbsG: 4, fatG: 13, fiberG: 0)),
  FoodItem(id: 'chicken_fry', name: 'Chicken fry', aliases: ['chicken fry', 'chicken 65', 'chilli chicken', 'chicken pakoda', 'fried chicken', 'kfc'],
      unit: FoodUnit.katori, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 320, proteinG: 24, carbsG: 10, fatG: 20, fiberG: 1)),
  FoodItem(id: 'mutton_curry', name: 'Mutton curry', aliases: ['mutton', 'mutton curry', 'goat curry', 'gosht', 'rogan josh', 'keema', 'mutton keema'],
      unit: FoodUnit.katori, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 300, proteinG: 22, carbsG: 5, fatG: 21, fiberG: 1)),
  FoodItem(id: 'fish_fry', name: 'Fish fry', aliases: ['fish fry', 'fried fish', 'fish tawa fry'],
      unit: FoodUnit.piece, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 200, proteinG: 18, carbsG: 6, fatG: 11, fiberG: 0)),
  FoodItem(id: 'prawn_curry', name: 'Prawn curry', aliases: ['prawns', 'prawn curry', 'shrimp', 'jhinga', 'royyala koora', 'prawn fry'],
      unit: FoodUnit.katori, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 200, proteinG: 20, carbsG: 6, fatG: 10, fiberG: 1)),
  FoodItem(id: 'chicken_breast', name: 'Chicken breast (100 g)', aliases: ['chicken breast', 'boiled chicken', 'chicken boiled'],
      unit: FoodUnit.piece, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6, fiberG: 0)),
  FoodItem(id: 'chicken_soup', name: 'Chicken soup', aliases: ['chicken soup', 'chicken clear soup', 'chicken sweet corn soup'],
      unit: FoodUnit.katori, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 100, proteinG: 10, carbsG: 6, fatG: 4, fiberG: 0)),
  FoodItem(id: 'shawarma', name: 'Shawarma / roll', aliases: ['shawarma', 'chicken shawarma', 'chicken roll', 'kathi roll', 'frankie', 'wrap'],
      unit: FoodUnit.piece, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 450, proteinG: 25, carbsG: 40, fatG: 20, fiberG: 3)),
  FoodItem(id: 'palak', name: 'Palak / saag', aliases: ['palak', 'saag', 'sarson ka saag', 'spinach', 'palakura', 'keerai'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 120, proteinG: 4, carbsG: 8, fatG: 8, fiberG: 4)),
  FoodItem(id: 'bhindi', name: 'Bhindi', aliases: ['bhindi', 'okra', 'bendakaya', 'vendakkai', 'bhindi fry'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 130, proteinG: 3, carbsG: 10, fatG: 9, fiberG: 4)),
  FoodItem(id: 'baingan', name: 'Baingan', aliases: ['baingan', 'baingan bharta', 'brinjal', 'brinjal curry', 'vankaya', 'kathirikai', 'eggplant'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 140, proteinG: 3, carbsG: 12, fatG: 9, fiberG: 5)),
  FoodItem(id: 'salad', name: 'Salad', aliases: ['salad', 'green salad', 'cucumber', 'kachumber', 'raita'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 40, proteinG: 2, carbsG: 8, fatG: 0.3, fiberG: 2)),
  FoodItem(id: 'veg_soup', name: 'Veg soup', aliases: ['soup', 'veg soup', 'tomato soup', 'sweet corn soup', 'manchow soup', 'hot and sour soup'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 80, proteinG: 3, carbsG: 10, fatG: 3, fiberG: 2)),
  FoodItem(id: 'dal_vada', name: 'Masala vada', aliases: ['masala vada', 'dal vada', 'paruppu vadai'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 120, proteinG: 4, carbsG: 12, fatG: 6, fiberG: 2)),
  FoodItem(id: 'pav_bhaji', name: 'Pav bhaji', aliases: ['pav bhaji', 'pao bhaji'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 450, proteinG: 10, carbsG: 60, fatG: 18, fiberG: 6)),
  FoodItem(id: 'vada_pav', name: 'Vada pav', aliases: ['vada pav', 'vada pao', 'wada pav'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 290, proteinG: 6, carbsG: 40, fatG: 12, fiberG: 3)),
  FoodItem(id: 'pani_puri', name: 'Pani puri (6)', aliases: ['pani puri', 'golgappa', 'gol gappe', 'puchka', 'pani poori'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 200, proteinG: 4, carbsG: 32, fatG: 6, fiberG: 3)),
  FoodItem(id: 'bhel_puri', name: 'Bhel / chaat', aliases: ['bhel', 'bhel puri', 'chaat', 'sev puri', 'papdi chaat', 'dahi puri', 'masala puri'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 250, proteinG: 6, carbsG: 40, fatG: 8, fiberG: 4)),
  FoodItem(id: 'pakora', name: 'Pakora / bajji', aliases: ['pakora', 'pakoda', 'pakodi', 'bajji', 'bhaji', 'onion pakoda', 'mirchi bajji'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 250, proteinG: 6, carbsG: 25, fatG: 15, fiberG: 3)),
  FoodItem(id: 'kachori', name: 'Kachori', aliases: ['kachori', 'pyaaz kachori'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 190, proteinG: 4, carbsG: 22, fatG: 10, fiberG: 2)),
  FoodItem(id: 'veg_momos', name: 'Veg momos (6)', aliases: ['momos', 'momo', 'veg momos', 'dumplings', 'steamed momos'],
      unit: FoodUnit.plate, perUnit: Nutrients(kcal: 250, proteinG: 7, carbsG: 40, fatG: 6, fiberG: 2)),
  FoodItem(id: 'chicken_momos', name: 'Chicken momos (6)', aliases: ['chicken momos', 'chicken momo', 'chicken dumplings'],
      unit: FoodUnit.plate, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 300, proteinG: 15, carbsG: 35, fatG: 10, fiberG: 2)),
  FoodItem(id: 'spring_roll', name: 'Spring roll', aliases: ['spring roll', 'spring rolls', 'veg roll'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 150, proteinG: 3, carbsG: 18, fatG: 7, fiberG: 1)),
  FoodItem(id: 'sandwich', name: 'Sandwich', aliases: ['sandwich', 'veg sandwich', 'grilled sandwich', 'club sandwich', 'toast sandwich'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 250, proteinG: 8, carbsG: 32, fatG: 10, fiberG: 3)),
  FoodItem(id: 'chicken_sandwich', name: 'Chicken sandwich', aliases: ['chicken sandwich', 'egg sandwich'],
      unit: FoodUnit.piece, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 320, proteinG: 20, carbsG: 32, fatG: 12, fiberG: 3)),
  FoodItem(id: 'burger', name: 'Burger', aliases: ['burger', 'veg burger', 'aloo tikki burger'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 400, proteinG: 15, carbsG: 45, fatG: 17, fiberG: 3)),
  FoodItem(id: 'chicken_burger', name: 'Chicken burger', aliases: ['chicken burger', 'zinger', 'chicken zinger'],
      unit: FoodUnit.piece, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 480, proteinG: 25, carbsG: 45, fatG: 22, fiberG: 3)),
  FoodItem(id: 'pizza', name: 'Pizza slice', aliases: ['pizza', 'pizza slice', 'margherita', 'veg pizza', 'cheese pizza'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 280, proteinG: 11, carbsG: 33, fatG: 11, fiberG: 2)),
  FoodItem(id: 'chicken_pizza', name: 'Chicken pizza slice', aliases: ['chicken pizza', 'pepperoni pizza'],
      unit: FoodUnit.piece, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 310, proteinG: 14, carbsG: 33, fatG: 13, fiberG: 2)),
  FoodItem(id: 'fries', name: 'French fries', aliases: ['fries', 'french fries', 'finger chips'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 300, proteinG: 4, carbsG: 38, fatG: 15, fiberG: 3)),
  FoodItem(id: 'chips', name: 'Chips (small pack)', aliases: ['chips', 'lays', 'potato chips', 'banana chips', 'kurkure'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 160, proteinG: 2, carbsG: 15, fatG: 10, fiberG: 1)),
  FoodItem(id: 'biscuit', name: 'Biscuit', aliases: ['biscuit', 'biscuits', 'cookie', 'cookies', 'marie', 'rusk', 'parle g'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 45, proteinG: 0.6, carbsG: 7, fatG: 2, fiberG: 0.2)),
  FoodItem(id: 'namkeen', name: 'Namkeen / mixture', aliases: ['namkeen', 'mixture', 'bhujia', 'chivda', 'murukku', 'chakli'],
      unit: FoodUnit.handful, perUnit: Nutrients(kcal: 150, proteinG: 4, carbsG: 14, fatG: 9, fiberG: 2)),
  FoodItem(id: 'makhana', name: 'Roasted makhana', aliases: ['makhana', 'fox nuts', 'phool makhana'],
      unit: FoodUnit.handful, perUnit: Nutrients(kcal: 100, proteinG: 3, carbsG: 20, fatG: 0.5, fiberG: 2)),
  FoodItem(id: 'roasted_chana', name: 'Roasted chana', aliases: ['roasted chana', 'bhuna chana', 'putnalu', 'pottukadalai'],
      unit: FoodUnit.handful, proteinSource: true, perUnit: Nutrients(kcal: 120, proteinG: 7, carbsG: 20, fatG: 2, fiberG: 5)),
  FoodItem(id: 'almonds', name: 'Almonds (10)', aliases: ['almonds', 'badam', 'almond'],
      unit: FoodUnit.handful, perUnit: Nutrients(kcal: 70, proteinG: 2.5, carbsG: 2.5, fatG: 6, fiberG: 1.5)),
  FoodItem(id: 'cashews', name: 'Cashews (10)', aliases: ['cashews', 'kaju', 'cashew'],
      unit: FoodUnit.handful, perUnit: Nutrients(kcal: 90, proteinG: 3, carbsG: 5, fatG: 7, fiberG: 0.5)),
  FoodItem(id: 'walnuts', name: 'Walnuts', aliases: ['walnuts', 'akhrot', 'walnut'],
      unit: FoodUnit.handful, perUnit: Nutrients(kcal: 130, proteinG: 3, carbsG: 3, fatG: 13, fiberG: 1.3)),
  FoodItem(id: 'dates', name: 'Dates', aliases: ['dates', 'khajur', 'date'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 20, proteinG: 0.2, carbsG: 5, fatG: 0, fiberG: 0.6)),
  FoodItem(id: 'corn', name: 'Boiled corn', aliases: ['corn', 'sweet corn', 'bhutta', 'boiled corn', 'corn chaat', 'mokka jonna'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 130, proteinG: 4, carbsG: 28, fatG: 1.5, fiberG: 3)),
  FoodItem(id: 'apple', name: 'Apple', aliases: ['apple', 'seb', 'apples'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 95, proteinG: 0.5, carbsG: 25, fatG: 0.3, fiberG: 4.4)),
  FoodItem(id: 'orange', name: 'Orange / mosambi', aliases: ['orange', 'santra', 'mosambi', 'sweet lime', 'kamala'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 60, proteinG: 1.2, carbsG: 15, fatG: 0.2, fiberG: 3)),
  FoodItem(id: 'papaya', name: 'Papaya', aliases: ['papaya', 'papita', 'boppayi'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 60, proteinG: 0.7, carbsG: 15, fatG: 0.2, fiberG: 2.5)),
  FoodItem(id: 'mango', name: 'Mango', aliases: ['mango', 'aam', 'mamidi', 'maambazham'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 200, proteinG: 2.8, carbsG: 50, fatG: 1.3, fiberG: 5)),
  FoodItem(id: 'guava', name: 'Guava', aliases: ['guava', 'amrood', 'jama', 'koyya', 'perakka'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 70, proteinG: 2.6, carbsG: 14, fatG: 1, fiberG: 5)),
  FoodItem(id: 'watermelon', name: 'Watermelon', aliases: ['watermelon', 'tarbooz', 'puchakaya'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 45, proteinG: 1, carbsG: 11, fatG: 0.2, fiberG: 0.6)),
  FoodItem(id: 'grapes', name: 'Grapes', aliases: ['grapes', 'angoor', 'draksha'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 100, proteinG: 1, carbsG: 27, fatG: 0.2, fiberG: 1.4)),
  FoodItem(id: 'pomegranate', name: 'Pomegranate', aliases: ['pomegranate', 'anar', 'danimma'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 80, proteinG: 1.7, carbsG: 19, fatG: 1, fiberG: 4)),
  FoodItem(id: 'chikoo', name: 'Chikoo', aliases: ['chikoo', 'sapota', 'chiku'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 70, proteinG: 0.4, carbsG: 17, fatG: 0.9, fiberG: 4)),
  FoodItem(id: 'pineapple', name: 'Pineapple', aliases: ['pineapple', 'ananas'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 80, proteinG: 0.9, carbsG: 21, fatG: 0.2, fiberG: 2.3)),
  FoodItem(id: 'fruit_bowl', name: 'Fruit bowl', aliases: ['fruit', 'fruits', 'fruit bowl', 'fruit salad', 'mixed fruit'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 90, proteinG: 1, carbsG: 22, fatG: 0.4, fiberG: 3)),
  FoodItem(id: 'jalebi', name: 'Jalebi', aliases: ['jalebi', 'jilebi', 'imarti'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 150, proteinG: 1, carbsG: 25, fatG: 5, fiberG: 0)),
  FoodItem(id: 'laddoo', name: 'Laddoo', aliases: ['laddoo', 'laddu', 'ladoo', 'besan laddoo', 'motichoor', 'boondi laddu', 'rava laddu'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 180, proteinG: 3, carbsG: 24, fatG: 8, fiberG: 1)),
  FoodItem(id: 'kheer', name: 'Kheer / payasam', aliases: ['kheer', 'payasam', 'payesh', 'semiya payasam', 'rice kheer', 'phirni'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 220, proteinG: 6, carbsG: 32, fatG: 7, fiberG: 0.5)),
  FoodItem(id: 'halwa', name: 'Halwa', aliases: ['halwa', 'sooji halwa', 'gajar halwa', 'kesari', 'sheera', 'rava kesari'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 300, proteinG: 4, carbsG: 40, fatG: 14, fiberG: 1)),
  FoodItem(id: 'rasgulla', name: 'Rasgulla', aliases: ['rasgulla', 'rosogolla', 'rasmalai', 'ras malai'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 120, proteinG: 3, carbsG: 25, fatG: 1, fiberG: 0)),
  FoodItem(id: 'barfi', name: 'Barfi', aliases: ['barfi', 'burfi', 'kaju katli', 'kalakand', 'peda', 'mysore pak'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 150, proteinG: 3, carbsG: 20, fatG: 7, fiberG: 0.5)),
  FoodItem(id: 'ice_cream', name: 'Ice cream', aliases: ['ice cream', 'icecream', 'kulfi', 'sundae'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 200, proteinG: 3.5, carbsG: 24, fatG: 11, fiberG: 0.5)),
  FoodItem(id: 'chocolate', name: 'Chocolate bar', aliases: ['chocolate', 'dairy milk', 'kitkat', 'chocolate bar'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 230, proteinG: 3, carbsG: 25, fatG: 13, fiberG: 1)),
  FoodItem(id: 'cake', name: 'Cake slice', aliases: ['cake', 'pastry', 'brownie', 'muffin', 'cupcake'],
      unit: FoodUnit.piece, perUnit: Nutrients(kcal: 350, proteinG: 5, carbsG: 50, fatG: 15, fiberG: 1)),
  FoodItem(id: 'sugar', name: 'Sugar', aliases: ['sugar', 'jaggery', 'gur', 'bellam', 'honey'],
      unit: FoodUnit.spoon, perUnit: Nutrients(kcal: 20, proteinG: 0, carbsG: 5, fatG: 0, fiberG: 0)),
  FoodItem(id: 'fruit_juice', name: 'Fruit juice', aliases: ['juice', 'fruit juice', 'orange juice', 'mosambi juice', 'apple juice', 'pineapple juice'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 110, proteinG: 1, carbsG: 26, fatG: 0.3, fiberG: 0.5)),
  FoodItem(id: 'coconut_water', name: 'Coconut water', aliases: ['coconut water', 'nariyal pani', 'elaneer', 'kobbari neellu', 'tender coconut'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 45, proteinG: 1.7, carbsG: 9, fatG: 0.5, fiberG: 2.6)),
  FoodItem(id: 'soft_drink', name: 'Soft drink', aliases: ['coke', 'pepsi', 'cola', 'sprite', 'thums up', 'soft drink', 'cold drink', 'fanta', 'limca', 'mazaa', 'maaza', 'frooti'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 140, proteinG: 0, carbsG: 38, fatG: 0, fiberG: 0)),
  FoodItem(id: 'sugarcane_juice', name: 'Sugarcane juice', aliases: ['sugarcane juice', 'ganne ka ras', 'cheruku rasam'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 180, proteinG: 0, carbsG: 45, fatG: 0, fiberG: 0)),
  FoodItem(id: 'nimbu_pani', name: 'Nimbu pani', aliases: ['nimbu pani', 'lemonade', 'shikanji', 'lemon juice', 'lemon water'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 60, proteinG: 0, carbsG: 15, fatG: 0, fiberG: 0)),
  FoodItem(id: 'beer', name: 'Beer', aliases: ['beer', 'pint'],
      unit: FoodUnit.glass, perUnit: Nutrients(kcal: 150, proteinG: 1.6, carbsG: 13, fatG: 0, fiberG: 0)),
  FoodItem(id: 'veg_manchurian', name: 'Veg / gobi manchurian', aliases: ['manchurian', 'gobi manchurian', 'veg manchurian', 'gobi 65', 'chilli paneer', 'paneer manchurian'],
      unit: FoodUnit.katori, perUnit: Nutrients(kcal: 280, proteinG: 6, carbsG: 28, fatG: 16, fiberG: 3)),
  FoodItem(id: 'chicken_manchurian', name: 'Chicken manchurian', aliases: ['chicken manchurian', 'dragon chicken', 'chicken lollipop'],
      unit: FoodUnit.katori, veg: false, proteinSource: true, perUnit: Nutrients(kcal: 330, proteinG: 22, carbsG: 15, fatG: 20, fiberG: 1)),
  FoodItem(id: 'egg_rice', name: 'Egg rice', aliases: ['egg rice', 'egg pulao', 'muttai sadam'],
      unit: FoodUnit.katori, veg: false, egg: true, proteinSource: true, perUnit: Nutrients(kcal: 280, proteinG: 10, carbsG: 38, fatG: 9, fiberG: 1)),
];

/// A table match for typed or AI-returned text.
class FoodMatch {
  final FoodItem food;

  /// False when spelling was corrected ("chcken" → chicken) or only part
  /// of the text matched; the review screen shows the dish name either way.
  final bool exact;

  /// Share of the typed dish words the match explains (0–1). "chicken
  /// manchurian" → "chicken" covers about half: too little to trust.
  final double coverage;

  const FoodMatch(this.food, {required this.exact, this.coverage = 1});

  /// Good enough to log without asking: whole-name, or most of the words.
  bool get confident => exact || coverage >= 0.6;
}

class IndianFoodDb {
  const IndianFoodDb._();

  static FoodItem? byId(String id) {
    for (final f in indianFoods) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Best match for a free-text dish name, or null.
  static FoodItem? match(String text) => bestMatch(text)?.food;

  /// Words that describe the meal, not the dish ("had some homemade dal
  /// for lunch" → "dal").
  static const _filler = {
    'i', 'had', 'have', 'ate', 'eaten', 'eat', 'some', 'little', 'bit', 'of', 'the', 'my', 'for', 'at',
    'breakfast', 'lunch', 'dinner', 'snack', 'snacks', 'today', 'tonight', 'morning', 'evening', 'night',
    'homemade', 'home', 'made', 'fresh', 'hot', 'cold', 'just', 'only', 'also', 'plus', 'approx', 'about',
    'small', 'big', 'large', 'medium', 'full', 'extra', 'chota', 'bada', 'thoda', 'konchem', 'konjam',
  };

  /// Exact alias first; then the best alias found inside the text, with
  /// small spelling mistakes forgiven ("chcken noodles", "biryni"). When
  /// two dishes appear, the longer one wins, and the last word breaks
  /// close calls ("paneer pasta" is pasta; "aloo paratha" stays one dish).
  static FoodMatch? bestMatch(String text) {
    final q = _normalise(text);
    if (q.isEmpty) return null;
    final tokens = q.split(' ').where((w) => w.isNotEmpty && !_filler.contains(w) && double.tryParse(w) == null).toList();
    if (tokens.isEmpty) return null;
    final joined = tokens.join(' ');
    final singular = tokens.map(_singular).join(' ');
    for (final f in indianFoods) {
      if (f.aliases.contains(joined) || f.aliases.contains(singular) || _normalise(f.name) == joined) {
        return FoodMatch(f, exact: true);
      }
    }

    FoodItem? best;
    var bestScore = 0;
    var bestEdits = 0;
    var bestCovered = 0;
    for (final f in indianFoods) {
      for (final alias in f.aliases) {
        final a = alias.split(' ');
        if (a.length > tokens.length) continue;
        for (var start = 0; start + a.length <= tokens.length; start++) {
          var edits = 0;
          var ok = true;
          for (var k = 0; k < a.length && ok; k++) {
            final d = _tokenDistance(tokens[start + k], a[k]);
            if (d < 0) {
              ok = false;
            } else {
              edits += d;
            }
          }
          if (!ok) continue;
          final endsLast = start + a.length == tokens.length;
          final score = alias.length * 10 - edits * 8 + (endsLast ? 15 : 0);
          if (score > bestScore) {
            best = f;
            bestScore = score;
            bestEdits = edits;
            bestCovered = [for (var k = 0; k < a.length; k++) tokens[start + k].length].fold(0, (x, y) => x + y);
          }
        }
      }
    }
    if (best == null) return null;
    final total = tokens.fold<int>(0, (x, t) => x + t.length);
    final coverage = total == 0 ? 0.0 : bestCovered / total;
    return FoodMatch(best, exact: bestEdits == 0 && coverage >= 0.999, coverage: coverage);
  }

  /// Edits between a typed word and an alias word, or -1 if too far.
  /// Short words must match exactly; longer ones forgive 1–2 slips.
  static int _tokenDistance(String typed, String word) {
    if (typed == word || _singular(typed) == word) return 0;
    final allowed = word.length <= 3 ? 0 : (word.length <= 6 ? 1 : 2);
    if (allowed == 0 || (typed.length - word.length).abs() > allowed) return -1;
    final d = _osa(typed, word);
    return d <= allowed ? d : -1;
  }

  /// Optimal string alignment distance (Levenshtein + swapped letters).
  static int _osa(String a, String b) {
    final m = a.length, n = b.length;
    final d = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var v = d[i - 1][j] + 1;
        if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
        if (d[i - 1][j - 1] + cost < v) v = d[i - 1][j - 1] + cost;
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] && d[i - 2][j - 2] + 1 < v) {
          v = d[i - 2][j - 2] + 1;
        }
        d[i][j] = v;
      }
    }
    return d[m][n];
  }

  static String _singular(String w) {
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && w.endsWith('es') && (w.endsWith('oes') || w.endsWith('ches'))) {
      return w.substring(0, w.length - 2);
    }
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    return w;
  }

  /// How many grams one portion is, when it can be said ("100 g rice"
  /// is 2/3 of a katori). Null for things counted in pieces.
  static double? gramsPerUnit(FoodItem f) {
    final m = RegExp(r'\((\d+) g\)').firstMatch(f.name);
    if (m != null) return double.parse(m.group(1)!);
    return switch (f.unit) {
      FoodUnit.katori => 150,
      FoodUnit.plate => 300,
      FoodUnit.glass => 250,
      FoodUnit.cup => 150,
      FoodUnit.spoon => 10,
      FoodUnit.handful => 30,
      _ => null,
    };
  }

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
