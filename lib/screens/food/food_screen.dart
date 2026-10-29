/// Food: today's protein vs goal, what to add (in katoris), and three
/// ways to log — take a photo, pick a photo, or type it.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/food/food_log_service.dart';
import '../../core/food/meal_analyzer.dart';
import '../../core/food/meal_text_parser.dart';
import '../../core/food/nutrients.dart';
import '../../core/food/protein_gap.dart';
import '../../core/profile/user_profile.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import '../../core/food/photo_privacy.dart';
import 'meal_review_screen.dart';
import '../../widgets/text_prompt.dart';

class FoodScreen extends StatefulWidget {
  final FoodLogService foodLog;

  /// Null when photo analysis isn't available (no backend): photo
  /// buttons then explain that instead of failing.
  final MealAnalyzer? analyzer;

  /// From onboarding, to suggest veg / egg / non-veg protein foods.
  final Diet? diet;

  /// Called after a meal is saved (e.g. to schedule a walk nudge).
  /// Failures here never block saving.
  final Future<void> Function(Meal meal)? onMealLogged;

  const FoodScreen({super.key, required this.foodLog, this.analyzer, this.diet, this.onMealLogged});

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  List<Meal> _meals = const [];
  Nutrients _total = Nutrients.zero;
  double _goal = ProteinGap.defaultGoalG.toDouble();
  bool _loading = true;
  bool _analysing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _loadError;

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final meals = await widget.foodLog.mealsFor(now);
      final goal = await widget.foodLog.proteinGoal();
      if (!mounted) return;
      setState(() {
        _meals = meals;
        _total = meals.fold(Nutrients.zero, (s, m) => s + m.total);
        _goal = goal;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = "Couldn't load today's meals.";
      });
    }
  }

  Future<void> _review(MealAnalysis analysis, {List<String> unknown = const []}) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MealReviewScreen(
        analysis: analysis,
        unknown: unknown,
        onSave: (meal) async {
          await widget.foodLog.addMeal(meal);
          try {
            await widget.onMealLogged?.call(meal);
          } catch (_) {
            // A reminder failing must never lose the meal.
          }
        },
      ),
    ));
    await _load();
  }

  // ---- type it ----

  Future<void> _typeIt() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const TextPromptDialog(
        title: 'What did you eat?',
        hint: 'e.g. 2 roti, 1 katori dal, curd',
        confirmLabel: 'Next',
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final parsed = MealTextParser.parse(text);
    if (parsed.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Couldn't find “${text.trim()}”. Try a photo, or a simpler name like “dal”."),
      ));
      return;
    }
    await _review(
      MealAnalysis(items: parsed.entries, confidence: [for (final _ in parsed.entries) 1.0], questions: const []),
      unknown: parsed.unknown,
    );
  }

  // ---- photo ----

  Future<bool> _ensureConsent() async {
    if (await widget.foodLog.hasPhotoConsent()) return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Analyse meal photos?'),
        content: const Text(
          'To read your meal, the photo is sent securely to HUX\'s server and then to Groq Inc. '
          '(an AI provider in the USA), only to identify the food and portions. Location and other '
          'hidden photo details are removed first. Neither HUX nor Groq stores the photo (Groq\'s '
          'zero data retention is on). Your meal log stays on this phone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Allow')),
        ],
      ),
    );
    if (ok == true) await widget.foodLog.setPhotoConsent(true);
    return ok == true;
  }

  Future<void> _photo(ImageSource source) async {
    final analyzer = widget.analyzer;
    if (analyzer == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Photo logging is coming soon. You can type your meal for now.'),
      ));
      return;
    }
    if (!await _ensureConsent() || !mounted) return;

    final XFile? file;
    try {
      // Downsized on the phone: faster upload, enough detail for food.
      file = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 70);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Camera or photos not available. Check permissions in Settings.'),
      ));
      return;
    }
    if (file == null || !mounted) return;

    final description = await _askDescription();
    if (!mounted) return;

    setState(() => _analysing = true);
    try {
      // Re-encode before upload: drops EXIF (GPS location, device) —
      // HUX promises "no GPS location".
      final bytes = await stripPhotoMetadata(await file.readAsBytes());
      final analysis = await analyzer.analyze(imageJpeg: bytes, description: description);
      if (!mounted) return;
      setState(() => _analysing = false);
      await _review(analysis);
    } on MealAnalysisException catch (e) {
      if (!mounted) return;
      setState(() => _analysing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _analysing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong reading that photo. Please try again.')),
      );
    }
  }

  /// Optional: a dish name helps a lot ("rajma chawal", "Mom's sambar").
  Future<String?> _askDescription() => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const MealDescriptionSheet(),
      );

  Future<void> _editGoal() async {
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const HuxIconBadge(icon: Icons.monitor_weight_outlined, color: HuxColors.ringFood),
              title: const Text('Set from my weight'),
              subtitle: const Text('About 0.8 g protein per kg of body weight'),
              onTap: () => Navigator.pop(c, 'weight'),
            ),
            ListTile(
              leading: const HuxIconBadge(icon: Icons.edit_rounded, color: HuxColors.ringSteps),
              title: const Text('Enter grams myself'),
              onTap: () => Navigator.pop(c, 'grams'),
            ),
            const SizedBox(height: HuxSpacing.sm),
          ],
        ),
      ),
    );
    if (!mounted || how == null) return;
    if (how == 'weight') {
      final current = await widget.foodLog.bodyWeightKg();
      if (!mounted) return;
      final w = await showDialog<String>(
        context: context,
        builder: (_) => TextPromptDialog(
          title: 'Your weight (kg)',
          initialText: current == null ? '' : current.toStringAsFixed(0),
          keyboardType: TextInputType.number,
          confirmLabel: 'Set goal',
          helper: 'Used only to work out your protein goal; stays on this phone. '
              'Pregnant, an athlete, or managing a health condition? Ask your doctor or dietitian.',
        ),
      );
      final kg = double.tryParse(w ?? '');
      if (kg == null) return;
      final goal = await widget.foodLog.setGoalFromWeight(kg);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Protein goal set to ${goal.round()} g a day.')));
      return;
    }
    if (!mounted) return;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Daily protein goal (g)',
        initialText: _goal.round().toString(),
        keyboardType: TextInputType.number,
        confirmLabel: 'Save',
        helper: 'A common guide is about 0.8 g per kg of body weight. '
            'Ask your doctor or dietitian for your own target.',
      ),
    );
    final grams = double.tryParse(value ?? '');
    if (grams == null) return;
    await widget.foodLog.setProteinGoal(grams);
    await _load();
  }

  bool _deleting = false;

  /// Index-based delete: ignore taps until the list has reloaded (a
  /// quick second tap would otherwise delete whichever meal shifted
  /// into that slot), and offer Undo instead of a confirm dialog.
  Future<void> _deleteMeal(int index) async {
    if (_deleting || index >= _meals.length) return;
    _deleting = true;
    final removed = _meals[index];
    try {
      await widget.foodLog.deleteMeal(DateTime.now(), index);
      await _load();
    } finally {
      _deleting = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${removed.type.label} deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.foodLog.addMeal(removed);
            await _load();
          },
        ),
      ));
  }

  static IconData _mealIcon(MealType t) => switch (t) {
        MealType.breakfast => Icons.free_breakfast_outlined,
        MealType.lunch => Icons.lunch_dining_outlined,
        MealType.dinner => Icons.dinner_dining_outlined,
        MealType.snack => Icons.cookie_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final gap = ProteinGap.compute(eaten: _total, goalG: _goal, diet: widget.diet);
    final pct = _goal == 0 ? 0.0 : (_total.proteinG / _goal).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text('Food & protein')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
                  children: [
                    if (_loadError != null) ...[
                      HuxCard(
                        child: Row(
                          children: [
                            Expanded(child: Text(_loadError!, style: text.bodyMedium)),
                            TextButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      ),
                      const SizedBox(height: HuxSpacing.md),
                    ],
                    // ---- hero: protein ring + macros ----
                    HuxHeroCard(
                      icon: Icons.restaurant_rounded,
                      color: HuxColors.ringFood,
                      eyebrow: 'Today',
                      title: 'Protein ${_total.proteinG.round()} of ${_goal.round()} g',
                      subtitle: '${_total.kcal.round()} kcal so far (approx.)',
                      trailing: TextButton(onPressed: _editGoal, child: const Text('Goal')),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              HuxScoreRing(
                                progress: pct,
                                centerText: '${(pct * 100).round()}%',
                                color: HuxColors.ringFood,
                                size: 76,
                              ),
                              const SizedBox(width: HuxSpacing.lg),
                              Expanded(
                                child: Wrap(
                                  spacing: HuxSpacing.sm,
                                  runSpacing: HuxSpacing.sm,
                                  children: [
                                    HuxPill(label: 'Carbs ${_total.carbsG.round()} g', color: HuxColors.ringSteps),
                                    HuxPill(label: 'Fat ${_total.fatG.round()} g', color: HuxColors.ringCharge),
                                    HuxPill(label: 'Fibre ${_total.fiberG.round()} g', color: HuxColors.ringSleep),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: HuxSpacing.md),
                          HuxProgressBar(value: pct, color: HuxColors.ringFood),
                        ],
                      ),
                    ),
                    const SizedBox(height: HuxSpacing.md),

                    // ---- what to add ----
                    HuxCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HuxIconBadge(
                            icon: gap.done ? Icons.check_rounded : Icons.lightbulb_outline_rounded,
                            color: gap.done ? HuxColors.recharged : HuxColors.ringHabit,
                          ),
                          const SizedBox(width: HuxSpacing.md),
                          Expanded(
                            child: Text(
                              gap.done
                                  ? 'Protein goal reached today.'
                                  : 'To close the gap (${gap.remainingG.round()} g): '
                                      'add ${gap.suggestions.map((s) => s.text).join(' and ')}.',
                              style: text.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: HuxSpacing.xl),

                    // ---- log a meal ----
                    const HuxSectionTitle('Log a meal', icon: Icons.add_circle_outline_rounded),
                    Row(
                      children: [
                        Expanded(
                          child: HuxActionTile(
                            icon: Icons.photo_camera_rounded,
                            label: 'Photo',
                            color: HuxColors.ringCharge,
                            onTap: _analysing ? null : () => _photo(ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: HuxSpacing.sm),
                        Expanded(
                          child: HuxActionTile(
                            icon: Icons.photo_library_rounded,
                            label: 'Gallery',
                            color: HuxColors.ringSleep,
                            onTap: _analysing ? null : () => _photo(ImageSource.gallery),
                          ),
                        ),
                        const SizedBox(width: HuxSpacing.sm),
                        Expanded(
                          child: HuxActionTile(
                            icon: Icons.edit_rounded,
                            label: 'Type',
                            color: HuxColors.ringSteps,
                            onTap: _analysing ? null : _typeIt,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: HuxSpacing.xl),

                    // ---- today's meals ----
                    const HuxSectionTitle('Today', icon: Icons.schedule_rounded),
                    if (_meals.isEmpty)
                      const HuxEmptyState(
                        icon: Icons.ramen_dining_outlined,
                        color: HuxColors.ringFood,
                        title: 'Nothing logged yet.',
                        body: 'Snap your next meal — it takes 10 seconds.',
                      )
                    else
                      HuxCard(
                        padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
                        child: Column(
                          children: [
                            for (var i = 0; i < _meals.length; i++) ...[
                              if (i > 0) const Divider(height: 1, color: HuxColors.hairline),
                              HuxListRow(
                                icon: _mealIcon(_meals[i].type),
                                color: HuxColors.ringFood,
                                title: _meals[i].type.label,
                                subtitle: '${_meals[i].items.map((e) => '${e.portionText} ${e.name.toLowerCase()}').join(', ')}\n'
                                    '${_meals[i].total.proteinG.round()} g protein · ${_meals[i].total.kcal.round()} kcal',
                                trailing: IconButton(
                                  tooltip: 'Delete meal',
                                  icon: const Icon(Icons.delete_outline, color: HuxColors.mutedText),
                                  onPressed: () => _deleteMeal(i),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: HuxSpacing.lg),
                    Text(
                      'Values are approximate home-style estimates, not medical advice.',
                      style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                if (_analysing) const HuxBusyOverlay(message: 'Reading your meal…'),
              ],
            ),
    );
  }
}
