/// Food (UI 2.0): protein ring + macro bars, the gap as one number with
/// two foods, meals as compact rows, and a log bar: snap, gallery, type.
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
import '../../widgets/hux/hux_kit.dart';
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
    await _logText(text);
  }

  /// One tap from the quick-add row: straight to the review screen.
  Future<void> _logText(String text) async {
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

  List<(String, String)> get _quickAdds {
    final protein = switch (widget.diet) {
      Diet.veg || Diet.jain => ('Curd', '1 katori curd'),
      _ => ('Egg', '1 egg'),
    };
    return [('Chai', '1 chai'), ('2 roti', '2 roti'), ('Dal', '1 katori dal'), protein];
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
    final gap = ProteinGap.compute(eaten: _total, goalG: _goal, diet: widget.diet);
    final pct = _goal == 0 ? 0.0 : (_total.proteinG / _goal).clamp(0.0, 1.0);

    Widget macro(String label, double grams, double of, Color color) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: huxInk))),
                  Text('${grams.round()} g', style: const TextStyle(fontSize: 14, color: huxMuted)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: of <= 0 ? 0 : (grams / of).clamp(0.0, 1.0),
                  minHeight: 7,
                  color: color,
                  backgroundColor: huxTrack,
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food'),
        actions: [
          TextButton.icon(
            onPressed: _editGoal,
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: Text('${_goal.round()} g goal'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, 120),
                  children: [
                    if (_loadError != null) ...[
                      HuxTile(
                        child: Row(
                          children: [
                            Expanded(child: Text(_loadError!, style: const TextStyle(fontSize: 15, color: huxInk))),
                            TextButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ---- hero: protein ring + macro bars ----
                    HuxTile(
                      semanticLabel: 'Protein ${_total.proteinG.round()} of ${_goal.round()} grams, '
                          '${_total.kcal.round()} kilocalories today',
                      padding: const EdgeInsets.all(18),
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 124,
                              height: 124,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 124,
                                    height: 124,
                                    child: CircularProgressIndicator(
                                      value: pct,
                                      strokeWidth: 12,
                                      strokeCap: StrokeCap.round,
                                      color: HuxColors.ringFood,
                                      backgroundColor: huxTrack,
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      HuxTileValue('${_total.proteinG.round()}', unit: 'g', size: 30),
                                      Text('protein of ${_goal.round()}',
                                          style: const TextStyle(fontSize: 13, color: huxMuted)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  HuxTileValue('${_total.kcal.round()}', unit: 'kcal', size: 24),
                                  const SizedBox(height: 12),
                                  macro('Carbs', _total.carbsG, 250, HuxColors.ringSteps),
                                  macro('Fat', _total.fatG, 70, HuxColors.ringHabit),
                                  macro('Fibre', _total.fiberG, 30, HuxColors.ringSleep),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ---- the gap, as a number + two foods ----
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: gap.done ? const Color(0xFFE3F5EA) : const Color(0xFFFCE8F3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(gap.done ? 'Done' : '+${gap.remainingG.round()} g',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: gap.done ? const Color(0xFF17804B) : const Color(0xFFA1306B),
                              )),
                          const SizedBox(width: 12),
                          Expanded(
                            child: gap.done
                                ? const Text('Protein goal reached',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxInk))
                                : Semantics(
                                    label: 'Add: ${gap.suggestions.map((s) => s.text).join(', ')}',
                                    excludeSemantics: true,
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final s in gap.suggestions)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text.rich(TextSpan(children: [
                                              TextSpan(
                                                  text: s.food.name,
                                                  style: const TextStyle(
                                                      fontSize: 14, fontWeight: FontWeight.w700, color: huxInk)),
                                              TextSpan(
                                                  text: '  +${s.proteinG.round()}',
                                                  style: const TextStyle(fontSize: 13, color: huxMuted)),
                                            ])),
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ---- meals ----
                    HuxTileLabel('Meals today', trailing: Text('${_meals.length}', style: const TextStyle(fontSize: 15, color: huxMuted))),
                    const SizedBox(height: 10),
                    if (_meals.isEmpty)
                      const HuxTile(
                        child: Row(
                          children: [
                            Icon(Icons.ramen_dining_outlined, color: HuxColors.ringFood, size: 28),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text('Nothing logged yet',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
                            ),
                          ],
                        ),
                      )
                    else
                      for (var i = 0; i < _meals.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        HuxTile(
                          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                          child: Row(
                            children: [
                              Icon(_mealIcon(_meals[i].type), color: HuxColors.ringFood, size: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_meals[i].type.label,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
                                    Text(
                                      _meals[i].items.map((e) => e.name).join(', '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14, color: huxMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${_meals[i].total.proteinG.round()} g',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
                                  Text('${_meals[i].total.kcal.round()} kcal',
                                      style: const TextStyle(fontSize: 13, color: huxMuted)),
                                ],
                              ),
                              IconButton(
                                tooltip: 'Delete meal',
                                icon: const Icon(Icons.close_rounded, color: huxMuted, size: 20),
                                onPressed: () => _deleteMeal(i),
                              ),
                            ],
                          ),
                        ),
                      ],
                    const SizedBox(height: 20),
                    const HuxTileLabel('Quick add'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (label, text) in _quickAdds)
                          ActionChip(
                            label: Text('+ $label'),
                            onPressed: _analysing ? null : () => _logText(text),
                            backgroundColor: Colors.white,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxInk),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Approximate home-style values.',
                      style: TextStyle(fontSize: 13, color: huxMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),

                // ---- log bar: photo first, then gallery and type ----
                Positioned(
                  left: HuxSpacing.lg,
                  right: HuxSpacing.lg,
                  bottom: 16,
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _analysing ? null : () => _photo(ImageSource.camera),
                            style: FilledButton.styleFrom(
                              backgroundColor: HuxColors.accentPink,
                              minimumSize: const Size(0, 56),
                              shape: const StadiumBorder(),
                            ),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Snap meal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Pick from gallery',
                          onPressed: _analysing ? null : () => _photo(ImageSource.gallery),
                          style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: Colors.white),
                          icon: const Icon(Icons.photo_library_outlined, color: huxInk),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Type what you ate',
                          onPressed: _analysing ? null : _typeIt,
                          style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: Colors.white),
                          icon: const Icon(Icons.edit_outlined, color: huxInk),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_analysing) const HuxBusyOverlay(message: 'Reading your meal…'),
              ],
            ),
    );
  }
}
