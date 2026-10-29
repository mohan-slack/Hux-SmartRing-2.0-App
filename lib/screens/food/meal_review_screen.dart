/// Review a meal before saving: answer up to 2 quick tap questions,
/// adjust portions with − / +, see totals, save.
library;

import 'package:flutter/material.dart';

import '../../core/food/meal_analyzer.dart';
import '../../core/food/nutrients.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';

class MealReviewScreen extends StatefulWidget {
  final MealAnalysis analysis;

  /// Text the user typed that matched no food (type-to-log only).
  final List<String> unknown;
  final Future<void> Function(Meal meal) onSave;

  const MealReviewScreen({
    super.key,
    required this.analysis,
    required this.onSave,
    this.unknown = const [],
  });

  @override
  State<MealReviewScreen> createState() => _MealReviewScreenState();
}

class _MealReviewScreenState extends State<MealReviewScreen> {
  late MealAnalysis _analysis = widget.analysis;
  late MealType _type = MealTypeLabel.forHour(DateTime.now().hour);
  bool _saving = false;

  void _setQty(int index, double qty) {
    if (qty <= 0) return;
    final items = [..._analysis.items];
    items[index] = items[index].withQuantity(qty);
    setState(() => _analysis = MealAnalysis(
          items: items,
          confidence: _analysis.confidence,
          questions: _analysis.questions,
          note: _analysis.note,
        ));
  }

  void _remove(int index) {
    final items = [..._analysis.items]..removeAt(index);
    final conf = [..._analysis.confidence];
    if (index < conf.length) conf.removeAt(index);
    // Questions point at item positions; drop any about removed/shifted items.
    final questions = [
      for (final q in _analysis.questions)
        if (q.itemIndex < index)
          q
        else if (q.itemIndex > index)
          MealQuestion(itemIndex: q.itemIndex - 1, kind: q.kind, text: q.text, options: q.options),
    ];
    setState(() => _analysis = MealAnalysis(items: items, confidence: conf, questions: questions, note: _analysis.note));
  }

  Future<void> _save() async {
    if (_analysis.items.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(Meal(type: _type, loggedAt: DateTime.now(), items: _analysis.items));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save — try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = _analysis.total;
    return Scaffold(
      appBar: AppBar(title: const Text('Check your meal')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.lg),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _analysis.items.isEmpty || _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Saving…' : 'Save meal'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xl),
        children: [
          // ---- totals hero ----
          HuxHeroCard(
            icon: Icons.restaurant_rounded,
            color: HuxColors.ringFood,
            eyebrow: 'This meal (approx.)',
            title: 'Protein ${total.proteinG.round()} g · ${total.kcal.round()} kcal',
            child: Wrap(
              spacing: HuxSpacing.sm,
              runSpacing: HuxSpacing.sm,
              children: [
                HuxPill(label: 'Carbs ${total.carbsG.round()} g', color: HuxColors.ringSteps),
                HuxPill(label: 'Fat ${total.fatG.round()} g', color: HuxColors.ringCharge),
                HuxPill(label: 'Fibre ${total.fiberG.round()} g', color: HuxColors.ringSleep),
              ],
            ),
          ),
          const SizedBox(height: HuxSpacing.md),

          // ---- quick questions ----
          for (final q in _analysis.questions) ...[
            HuxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const HuxIconBadge(icon: Icons.help_outline_rounded, color: HuxColors.ringSleep, size: 32),
                      const SizedBox(width: HuxSpacing.sm),
                      Text('Quick question', style: text.labelMedium?.copyWith(color: HuxColors.mutedText)),
                    ],
                  ),
                  const SizedBox(height: HuxSpacing.sm),
                  Text(q.text, style: text.titleSmall),
                  const SizedBox(height: HuxSpacing.sm),
                  Wrap(
                    spacing: HuxSpacing.sm,
                    runSpacing: HuxSpacing.sm,
                    children: [
                      for (final o in q.options)
                        ActionChip(
                          label: Text(o),
                          onPressed: () => setState(() => _analysis = _analysis.answer(q, o)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: HuxSpacing.md),
          ],
          if (widget.unknown.isNotEmpty) ...[
            HuxCard(
              child: Row(
                children: [
                  const HuxIconBadge(icon: Icons.search_off_rounded, color: HuxColors.stretched, size: 32),
                  const SizedBox(width: HuxSpacing.sm),
                  Expanded(
                    child: Text(
                      "Couldn't find: ${widget.unknown.join(', ')}. Try a photo, or a simpler name.",
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HuxSpacing.md),
          ],

          // ---- items ----
          const HuxSectionTitle('Items', icon: Icons.ramen_dining_outlined, iconColor: HuxColors.ringFood),
          HuxCard(
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < _analysis.items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: HuxColors.hairline),
                  _ItemRow(
                    entry: _analysis.items[i],
                    onMinus: () => _setQty(i, _analysis.items[i].quantity - 0.5),
                    onPlus: () => _setQty(i, _analysis.items[i].quantity + 0.5),
                    onRemove: () => _remove(i),
                  ),
                ],
                if (_analysis.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(HuxSpacing.md),
                    child: Text('No items left.', style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                  ),
              ],
            ),
          ),
          if (_analysis.note != null) ...[
            const SizedBox(height: HuxSpacing.sm),
            Text(_analysis.note!, style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
          ],
          const SizedBox(height: HuxSpacing.xl),

          // ---- which meal ----
          const HuxSectionTitle('Which meal?', icon: Icons.schedule_rounded),
          Wrap(
            spacing: HuxSpacing.sm,
            runSpacing: HuxSpacing.sm,
            children: [
              for (final t in MealType.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final FoodEntry entry;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onRemove;

  const _ItemRow({required this.entry, required this.onMinus, required this.onPlus, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ai = entry.source == NutrientSource.aiEstimate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(entry.name, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
              if (ai) const HuxPill(label: 'AI estimate', color: HuxColors.ringSleep, icon: Icons.auto_awesome),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 20, color: HuxColors.mutedText),
                onPressed: onRemove,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${entry.nutrients.proteinG.round()} g protein · ${entry.nutrients.kcal.round()} kcal'
                  '${ai ? '' : ' · approx.'}',
                  style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                ),
              ),
              // − portion +
              Container(
                decoration: BoxDecoration(
                  color: HuxColors.bg,
                  borderRadius: BorderRadius.circular(HuxRadii.chip),
                  border: Border.all(color: HuxColors.glassStroke),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Less',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      onPressed: entry.quantity > 0.5 ? onMinus : null,
                    ),
                    Text(entry.portionText, style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                    IconButton(
                      tooltip: 'More',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: onPlus,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
