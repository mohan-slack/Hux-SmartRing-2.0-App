/// A meal (or a whole day) split by food: each food's share of the
/// calories, for the petal chart. Same foods are merged, the biggest
/// come first, and anything past [maxPetals] is grouped as "Other".
/// Percentages always add up to 100. Pure.
library;

import 'nutrients.dart';

class PlateShare {
  final String name;

  /// "2 rotis", "1 katori" — empty for merged or "Other" rows.
  final String portion;
  final Nutrients nutrients;

  /// Whole-number share of the plate's calories.
  final int percent;

  const PlateShare({required this.name, required this.portion, required this.nutrients, required this.percent});
}

class PlateShares {
  PlateShares._();

  static const maxPetals = 8;

  static List<PlateShare> of(List<FoodEntry> entries, {int max = maxPetals}) {
    // Merge the same food logged twice (2 rotis at lunch + 2 at dinner).
    final byName = <String, ({String name, Nutrients n, int count, String portion})>{};
    for (final e in entries) {
      final key = e.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      final old = byName[key];
      byName[key] = old == null
          ? (name: e.name.trim(), n: e.nutrients, count: 1, portion: e.portionText)
          : (name: old.name, n: old.n + e.nutrients, count: old.count + 1, portion: '');
    }
    var rows = byName.values.toList()..sort((a, b) => b.n.kcal.compareTo(a.n.kcal));
    if (rows.isEmpty) return const [];
    if (rows.length > max) {
      final rest = rows.sublist(max - 1);
      rows = [
        ...rows.sublist(0, max - 1),
        (
          name: 'Other',
          n: rest.fold<Nutrients>(Nutrients.zero, (s, r) => s + r.n),
          count: rest.length,
          portion: '${rest.length} more',
        ),
      ];
    }
    final total = rows.fold<double>(0, (s, r) => s + r.n.kcal);
    // No calories known: share the plate equally rather than show 0%.
    final raw = [for (final r in rows) total <= 0 ? 100 / rows.length : r.n.kcal / total * 100];
    final pct = [for (final v in raw) v.floor()];
    // Hand the leftover points to the largest remainders, so it sums to 100.
    final order = List.generate(rows.length, (i) => i)
      ..sort((a, b) => (raw[b] - pct[b]).compareTo(raw[a] - pct[a]));
    for (var i = 0, left = 100 - pct.fold<int>(0, (s, v) => s + v); left > 0; i++, left--) {
      pct[order[i % order.length]]++;
    }
    return [
      for (var i = 0; i < rows.length; i++)
        PlateShare(name: rows[i].name, portion: rows[i].portion, nutrients: rows[i].n, percent: pct[i]),
    ];
  }
}
