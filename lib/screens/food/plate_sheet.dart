/// "Plate view": the petal chart for one meal (or the whole day), then
/// each food with its protein, carbs and fat.
library;

import 'package:flutter/material.dart';
import '../../theme/hux_fonts.dart';

import '../../core/food/nutrients.dart';
import '../../core/food/plate_shares.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_kit.dart';
import '../../widgets/petal_chart.dart';

Future<void> showPlateSheet(BuildContext context, {required String title, required List<FoodEntry> entries}) {
  final shares = PlateShares.of(entries);
  final total = entries.fold<Nutrients>(Nutrients.zero, (s, e) => s + e.nutrients);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: HuxColors.bg,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.9),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            if (shares.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text('Nothing logged here yet.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: huxMuted)),
              )
            else ...[
              Center(child: PetalChart(shares: shares, size: 300)),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: huxSora(textStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15, color: huxInk))),
              Text('${total.kcal.round()} kcal · ${total.proteinG.round()} g protein · share of calories',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: huxMuted)),
              const SizedBox(height: 16),
              HuxTile(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (var i = 0; i < shares.length; i++) ...[
                      if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: HuxColors.hairline),
                      _ShareRow(share: shares[i], color: petalColors[i % petalColors.length]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('Approximate values from HUX\'s food table.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: huxMuted)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ShareRow extends StatelessWidget {
  final PlateShare share;
  final Color color;

  const _ShareRow({required this.share, required this.color});

  @override
  Widget build(BuildContext context) {
    final n = share.nutrients;
    Widget chip(String label, double grams, Color dot) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: HuxColors.cardElevated, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('$label ${grams < 10 ? grams.toStringAsFixed(1) : grams.round()} g',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: huxInk)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
            child: Text('${share.percent}%',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: huxInk)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(share.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
                    ),
                    Text(
                        '${share.portion.isEmpty ? '' : '${share.portion} · '}${n.kcal.round()} kcal',
                        style: TextStyle(fontSize: 13, color: huxMuted)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    chip('Protein', n.proteinG, HuxColors.ringFood),
                    chip('Carbs', n.carbsG, HuxColors.ringSteps),
                    chip('Fat', n.fatG, HuxColors.ringHeart),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
