/// Food (UI 2.0): protein ring + macro bars, the gap as one number with
/// two foods, meals as compact rows, and a log bar: snap, gallery, type.
library;

import 'package:flutter/material.dart';
import '../../theme/hux_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/food/calorie_budget.dart';
import '../../core/food/calorie_budget_service.dart';
import '../../core/food/food_log_service.dart';
import '../../core/food/indian_food_db.dart';
import '../../core/food/meal_analyzer.dart';
import '../../core/food/meal_text_parser.dart';
import '../../core/food/nutrients.dart';
import '../../core/food/protein_gap.dart';
import '../../core/profile/user_profile.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';
import '../../core/food/photo_privacy.dart';
import 'meal_review_screen.dart';
import 'plate_sheet.dart';
import 'voice_log_sheet.dart';
import '../../widgets/text_prompt.dart';

class FoodScreen extends StatefulWidget {
  final FoodLogService foodLog;

  /// Null when photo analysis isn't available (no backend): photo
  /// buttons then explain that instead of failing.
  final MealAnalyzer? analyzer;

  /// From onboarding, to suggest veg / egg / non-veg protein foods.
  final Diet? diet;

  /// The user's app language: picks the voice-logging language.
  final AppLanguage? language;

  /// Called after a meal is saved (e.g. to schedule a walk nudge).
  /// Failures here never block saving.
  final Future<void> Function(Meal meal)? onMealLogged;

  const FoodScreen({super.key, required this.foodLog, this.analyzer, this.diet, this.language, this.onMealLogged});

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  List<Meal> _meals = const [];
  Nutrients _total = Nutrients.zero;
  double _goal = ProteinGap.defaultGoalG.toDouble();
  bool _loading = true;
  bool _analysing = false;
  List<UsualMeal> _usuals = const [];
  CalorieTarget? _target;
  late final CalorieBudgetService _budget = CalorieBudgetService(widget.foodLog.store);

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
      CalorieTarget? target;
      try {
        target = await _budget.target();
      } catch (_) {}
      var usuals = const <UsualMeal>[];
      try {
        usuals = await widget.foodLog.usuals(now: now);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _target = target;
        _usuals = usuals;
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

  static bool _riceFirst(AppLanguage? l) => const {
        AppLanguage.telugu, AppLanguage.tamil, AppLanguage.kannada, AppLanguage.malayalam,
        AppLanguage.tenglish, AppLanguage.tanglish, AppLanguage.kanglish,
      }.contains(l);

  Future<void> _setUpBudget() async {
    final a = await _budget.answers();
    final h = await _budget.heightCm();
    final w = await _budget.weightKg() ?? await widget.foodLog.bodyWeightKg();
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: HuxColors.bg,
      builder: (_) => _BudgetSetupSheet(service: _budget, sex: a?.sex, age: a?.age, activity: a?.activity, heightCm: h, weightKg: w),
    );
    if (saved == true) await _load();
  }

  Future<void> _sayIt() async {
    final words = await showVoiceLogSheet(context, language: widget.language);
    if (words == null || words.isEmpty || !mounted) return;
    // Speech has no commas: split "two roti dal and curd" into foods.
    await _logText(MealTextParser.splitRunOn(words));
  }

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

  /// Typed or quick-add text → review screen. HUX's own table first
  /// (instant, offline, forgives typos); anything it doesn't know can be
  /// estimated by AI, after one plain question — only the food words go.
  Future<void> _logText(String text) async {
    final parsed = MealTextParser.parse(text);
    var entries = [...parsed.entries];
    var confidence = <double>[for (final _ in entries) 1.0];
    var questions = <MealQuestion>[];
    var unknown = parsed.unknown;

    if (unknown.isNotEmpty && widget.analyzer != null && mounted) {
      final names = unknown.map((u) => '“$u”').join(', ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Look it up with AI?'),
          content: Text(
            '$names isn’t in HUX’s food list yet. HUX can estimate it with AI: only these words are sent '
            '(to HUX’s server, then Groq in the USA, not stored). The numbers are marked as an AI estimate.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Estimate')),
          ],
        ),
      );
      if (ok == true && mounted) {
        setState(() => _analysing = true);
        try {
          final ai = await widget.analyzer!.analyzeText(unknown.join(', '));
          // AI questions refer to AI items; shift them past the table items.
          questions = [
            for (final q in ai.questions)
              MealQuestion(itemIndex: q.itemIndex + entries.length, kind: q.kind, text: q.text, options: q.options),
          ];
          entries = [...entries, ...ai.items];
          confidence = [...confidence, ...ai.confidence];
          unknown = const [];
        } on MealAnalysisException catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text("Couldn't reach HUX — check your connection and try again.")));
          }
        } finally {
          if (mounted) setState(() => _analysing = false);
        }
      }
    }

    if (!mounted) return;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.analyzer == null
            ? "“${text.trim()}” isn’t in HUX’s food list yet. Try a photo, or another name for it."
            : "Nothing logged. Try a photo, or another name for “${text.trim()}”."),
      ));
      return;
    }
    await _review(
      MealAnalysis(items: entries, confidence: confidence, questions: questions),
      unknown: unknown,
    );
  }

  /// One tap: the same meal again, now. Undo in the snackbar.
  Future<void> _logUsual(UsualMeal u) async {
    if (_analysing) return;
    final meal = u.again(DateTime.now());
    await widget.foodLog.addMeal(meal);
    try {
      await widget.onMealLogged?.call(meal);
    } catch (_) {}
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Logged ${u.label} · ${meal.total.proteinG.round()} g protein'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          final i = _meals.lastIndexWhere((m) => m.loggedAt.isAtSameMomentAs(meal.loggedAt));
          if (i >= 0) {
            await widget.foodLog.deleteMeal(meal.loggedAt, i);
            await _load();
          }
        },
      ),
    ));
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
      final rule = await widget.foodLog.proteinRule();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Protein goal set to ${goal.round()} g a day '
              '(${rule.perKg.toStringAsFixed(1)} g per kg — ${rule.why}).')));
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
        helper: 'Guide: 0.8 g per kg for most adults, about 1.0 when losing weight or over 60, '
            '1.2 if you exercise regularly. Ask your doctor or dietitian for your own target.',
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
                  Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: huxInk))),
                  Text('${grams.round()} g', style: TextStyle(fontSize: 14, color: huxMuted)),
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
                            Expanded(child: Text(_loadError!, style: TextStyle(fontSize: 15, color: huxInk))),
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
                                          style: TextStyle(fontSize: 13, color: huxMuted)),
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

                    // ---- calories: target, what's left, a plate that fits ----
                    _CalorieCard(
                      target: _target,
                      eaten: _total.kcal,
                      diet: widget.diet,
                      riceBase: _riceFirst(widget.language),
                      onSetUp: _setUpBudget,
                    ),
                    const SizedBox(height: 12),

                    // ---- the gap, as a number + two foods ----
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: gap.done ? HuxColors.softGood : HuxColors.softPink,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(gap.done ? 'Done' : '+${gap.remainingG.round()} g',
                              style: huxSora(textStyle: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: gap.done ? const Color(0xFF17804B) : const Color(0xFFA1306B),
                              ))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: gap.done
                                ? Text('Protein goal reached',
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
                                              color: HuxColors.card,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text.rich(TextSpan(children: [
                                              TextSpan(
                                                  text: s.food.name,
                                                  style: TextStyle(
                                                      fontSize: 14, fontWeight: FontWeight.w700, color: huxInk)),
                                              TextSpan(
                                                  text: '  +${s.proteinG.round()}',
                                                  style: TextStyle(fontSize: 13, color: huxMuted)),
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
                    HuxTileLabel(
                      'Meals today',
                      trailing: _meals.isEmpty
                          ? Text('0', style: TextStyle(fontSize: 15, color: huxMuted))
                          : TextButton.icon(
                              onPressed: () => showPlateSheet(context,
                                  title: "Today's plate", entries: [for (final m in _meals) ...m.items]),
                              icon: const Icon(Icons.filter_vintage_rounded, size: 18),
                              label: Text('Plate view · ${_meals.length}'),
                            ),
                    ),
                    const SizedBox(height: 10),
                    if (_meals.isEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          height: 168,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const HuxPhoto('assets/images/photos/food.jpg', object: Hux3D.bowl, color: HuxColors.ringFood),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0x00000000), Color(0xB3000000)],
                                    stops: [0.4, 1],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 14,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Nothing logged yet',
                                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _analysing ? 'Reading your photo…' : 'Snap your plate. HUX reads the katoris.',
                                      style: const TextStyle(fontSize: 14, color: Color(0xE6FFFFFF)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      for (var i = 0; i < _meals.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        HuxTile(
                          onTap: () => showPlateSheet(context, title: _meals[i].type.label, entries: _meals[i].items),
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
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
                                    Text(
                                      _meals[i].items.map((e) => e.name).join(', '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 14, color: huxMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${_meals[i].total.proteinG.round()} g',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
                                  Text('${_meals[i].total.kcal.round()} kcal',
                                      style: TextStyle(fontSize: 13, color: huxMuted)),
                                ],
                              ),
                              IconButton(
                                tooltip: 'Delete meal',
                                icon: Icon(Icons.close_rounded, color: huxMuted, size: 20),
                                onPressed: () => _deleteMeal(i),
                              ),
                            ],
                          ),
                        ),
                      ],
                    if (_usuals.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const HuxTileLabel('Your usuals'),
                      const SizedBox(height: 10),
                      for (final u in _usuals)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: HuxTile(
                            onTap: _analysing ? null : () => _logUsual(u),
                            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(u.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxInk)),
                                      Text(
                                          '${u.type.label} · ${u.timesLogged} times · ${u.total.proteinG.round()} g protein',
                                          style: TextStyle(fontSize: 13, color: huxMuted)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.add_circle_rounded, color: HuxColors.ringFood, size: 28),
                              ],
                            ),
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
                            backgroundColor: HuxColors.card,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxInk),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
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
                          style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: HuxColors.card),
                          icon: Icon(Icons.photo_library_outlined, color: huxInk),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Say what you ate',
                          onPressed: _analysing ? null : _sayIt,
                          style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: HuxColors.card),
                          icon: Icon(Icons.mic_none_rounded, color: huxInk),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Type what you ate',
                          onPressed: _analysing ? null : _typeIt,
                          style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: HuxColors.card),
                          icon: Icon(Icons.edit_outlined, color: huxInk),
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


class _CalorieCard extends StatelessWidget {
  final CalorieTarget? target;
  final double eaten;
  final Diet? diet;
  final bool riceBase;
  final VoidCallback onSetUp;

  const _CalorieCard({required this.target, required this.eaten, required this.diet, required this.riceBase, required this.onSetUp});

  static String _n(num v) {
    final s = v.round().toString();
    return s.length > 3 ? '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}' : s;
  }

  @override
  Widget build(BuildContext context) {
    final t = target;
    if (t == null) {
      return HuxTile(
        onTap: onSetUp,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            const Hux3DObject(Hux3D.bowl, color: HuxColors.ringFood, size: 40, animate: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How much should I eat?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
                  Text('Set a daily calorie target — then HUX shows what\'s left and a plate that fits.',
                      style: TextStyle(fontSize: 13, height: 1.3, color: huxMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: huxMuted),
          ],
        ),
      );
    }
    final left = t.kcal - eaten;
    final over = left < 0;
    final plate = over ? const <(FoodItem, double)>[] : CalorieBudget.plateFor(left, diet: diet, riceBase: riceBase);
    return HuxTile(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: HuxTileLabel('Calories today')),
              InkWell(
                onTap: onSetUp,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('${_n(eaten)} of ${_n(t.kcal)}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: huxMuted)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (eaten / t.kcal).clamp(0.0, 1.0),
              minHeight: 10,
              color: over ? HuxColors.stretched : HuxColors.ringFood,
              backgroundColor: huxTrack,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            over ? '${_n(-left)} kcal over today' : '${_n(left)} kcal left',
            style: huxSora(textStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: over ? HuxColors.stretched : huxInk)),
          ),
          const SizedBox(height: 4),
          if (over)
            Text('No problem — a 15-minute walk after dinner and a lighter breakfast tomorrow evens it out.',
                style: TextStyle(fontSize: 14, height: 1.35, color: huxInk))
          else if (plate.isEmpty)
            Text('Nearly there — fruit, buttermilk or a few nuts if you\'re hungry.',
                style: TextStyle(fontSize: 14, height: 1.35, color: huxInk))
          else
            Text('A plate that fits: ${CalorieBudget.describe(plate)} (≈${_n(CalorieBudget.kcalOf(plate))} kcal)',
                style: TextStyle(fontSize: 14, height: 1.35, color: huxInk)),
          const SizedBox(height: 6),
          Text(t.why, style: TextStyle(fontSize: 12, height: 1.3, color: huxMuted)),
        ],
      ),
    );
  }
}

class _BudgetSetupSheet extends StatefulWidget {
  final CalorieBudgetService service;
  final BodySex? sex;
  final int? age;
  final ActivityLevel? activity;
  final double? heightCm;
  final double? weightKg;

  const _BudgetSetupSheet({required this.service, this.sex, this.age, this.activity, this.heightCm, this.weightKg});

  @override
  State<_BudgetSetupSheet> createState() => _BudgetSetupSheetState();
}

class _BudgetSetupSheetState extends State<_BudgetSetupSheet> {
  late BodySex? _sex = widget.sex;
  late ActivityLevel _activity = widget.activity ?? ActivityLevel.light;
  late final _age = TextEditingController(text: widget.age?.toString() ?? '');
  late final _height = TextEditingController(text: widget.heightCm?.round().toString() ?? '');
  late final _weight = TextEditingController(text: widget.weightKg?.toStringAsFixed(0) ?? '');
  String? _error;

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final age = int.tryParse(_age.text.trim());
    final h = double.tryParse(_height.text.trim());
    final w = double.tryParse(_weight.text.trim());
    if (_sex == null || age == null || h == null || w == null) {
      setState(() => _error = 'Please fill in all four.');
      return;
    }
    if (age < CalorieBudget.minAge) {
      setState(() => _error = 'Calorie targets are for adults (18+). HUX still tracks your protein and meals.');
      return;
    }
    if (age > 100 || h < 120 || h > 230 || w < 30 || w > 250) {
      setState(() => _error = 'Check the numbers: age 18–100, height 120–230 cm, weight 30–250 kg.');
      return;
    }
    await widget.service.save(sex: _sex!, age: age, activity: _activity, heightCm: h, weightKg: w);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, String suffix) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, suffixText: suffix),
          ),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your calorie target', style: huxSora(textStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: huxInk))),
            const SizedBox(height: 4),
            Text('Four answers for the standard formula (Mifflin-St Jeor). Stays on this phone.',
                style: TextStyle(fontSize: 14, height: 1.35, color: huxMuted)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              children: [
                for (final (s, l) in const [(BodySex.female, 'Woman'), (BodySex.male, 'Man'), (BodySex.unsaid, 'Prefer not to say')])
                  ChoiceChip(label: Text(l), selected: _sex == s, onSelected: (_) => setState(() => _sex = s)),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [field(_age, 'Age', 'yrs'), const SizedBox(width: 10), field(_height, 'Height', 'cm'), const SizedBox(width: 10), field(_weight, 'Weight', 'kg')]),
            const SizedBox(height: 14),
            Text('How active is a usual day?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxInk)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in ActivityLevel.values)
                  ChoiceChip(label: Text(a.label), selected: _activity == a, onSelected: (_) => setState(() => _activity = a)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(fontSize: 14, color: HuxColors.rundown)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
              child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            Text('Pregnant, breastfeeding, or managing a health condition? Ask your doctor for your target.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: huxMuted)),
          ],
        ),
      ),
    );
  }
}
