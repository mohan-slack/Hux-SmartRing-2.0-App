/// Photo-to-meal: send a meal photo (plus an optional name the user
/// typed) to HUX's backend, which asks a vision AI to list the dishes
/// and portions in Indian household units.
///
/// Accuracy rules:
/// - The AI only IDENTIFIES dishes and portions. Whenever a dish is in
///   HUX's food table, the table's numbers are used, not the AI's.
/// - Dishes not in the table keep the AI's estimate, clearly labelled
///   "AI estimate".
/// - The AI may ask at most 2 quick questions (tap answers, no typing)
///   when unsure — e.g. "How many rotis?" or "Paneer or tofu?". Answers
///   are applied on the phone; no second AI call.
///
/// The app never holds an AI API key: the key lives only in the backend
/// function (supabase/functions/analyze-meal).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'indian_food_db.dart';
import 'nutrients.dart';

enum QuestionKind { quantity, identity }

class MealQuestion {
  final int itemIndex;
  final QuestionKind kind;
  final String text;
  final List<String> options;

  const MealQuestion({
    required this.itemIndex,
    required this.kind,
    required this.text,
    required this.options,
  });
}

class MealAnalysis {
  final List<FoodEntry> items;

  /// 0–1 per item, same order as [items].
  final List<double> confidence;
  final List<MealQuestion> questions;

  /// Short note from the AI (e.g. "oil content can't be seen").
  final String? note;

  const MealAnalysis({
    required this.items,
    required this.confidence,
    required this.questions,
    this.note,
  });

  Nutrients get total => items.fold(Nutrients.zero, (s, e) => s + e.nutrients);

  /// Apply one tapped answer. Quantity -> new amount; identity -> the
  /// item becomes the chosen dish (re-matched against the food table).
  MealAnalysis answer(MealQuestion q, String option) {
    if (q.itemIndex < 0 || q.itemIndex >= items.length) return this;
    final updated = [...items];
    final current = updated[q.itemIndex];
    switch (q.kind) {
      case QuestionKind.quantity:
        final qty = double.tryParse(option.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (qty != null && qty > 0) updated[q.itemIndex] = current.withQuantity(qty);
      case QuestionKind.identity:
        updated[q.itemIndex] = MealAnalysisParser.resolve(
          name: option,
          quantity: current.quantity,
          unit: current.unit,
          // Not in the table? Keep the previous numbers as the estimate.
          aiEstimate: current.nutrients,
        );
    }
    return MealAnalysis(
      items: updated,
      confidence: confidence,
      questions: [for (final other in questions) if (!identical(other, q)) other],
      note: note,
    );
  }
}

/// Turns the backend's JSON into a [MealAnalysis]. Lenient: bad or
/// missing fields drop that item/question instead of failing the meal.
class MealAnalysisParser {
  static const maxQuestions = 2;

  const MealAnalysisParser._();

  static MealAnalysis parse(Map<String, Object?> json) {
    final items = <FoodEntry>[];
    final confidence = <double>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final r in rawItems) {
        if (r is! Map) continue;
        final name = r['name'];
        final portion = r['portion'];
        if (name is! String || name.trim().isEmpty) continue;
        var qty = 1.0;
        var unit = FoodUnit.katori;
        if (portion is Map) {
          qty = (portion['qty'] as num?)?.toDouble() ?? 1;
          unit = FoodUnit.values.where((u) => u.name == portion['unit']).firstOrNull ?? FoodUnit.katori;
        }
        if (qty <= 0) qty = 1;
        final estimate = r['estimate'];
        items.add(resolve(
          name: name,
          quantity: qty,
          unit: unit,
          aiEstimate: estimate is Map ? Nutrients.fromJson(Map<String, Object?>.from(estimate)) : null,
        ));
        confidence.add(((r['confidence'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0));
      }
    }

    final questions = <MealQuestion>[];
    final rawQuestions = json['questions'];
    if (rawQuestions is List) {
      for (final r in rawQuestions) {
        if (questions.length >= maxQuestions) break;
        if (r is! Map) continue;
        final idx = (r['itemIndex'] as num?)?.toInt();
        final kind = QuestionKind.values.where((k) => k.name == r['kind']).firstOrNull;
        final text = r['text'];
        final options = r['options'];
        if (idx == null || idx < 0 || idx >= items.length || kind == null || text is! String || options is! List) {
          continue;
        }
        final opts = options.whereType<String>().where((o) => o.trim().isNotEmpty).take(5).toList();
        if (opts.length < 2) continue;
        questions.add(MealQuestion(itemIndex: idx, kind: kind, text: text, options: opts));
      }
    }

    final note = json['note'];
    return MealAnalysis(
      items: items,
      confidence: confidence,
      questions: questions,
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
    );
  }

  /// HUX table first; otherwise the AI's own estimate (for the whole
  /// portion); otherwise zero, flagged as an estimate.
  static FoodEntry resolve({
    required String name,
    required double quantity,
    required FoodUnit unit,
    Nutrients? aiEstimate,
  }) {
    final food = IndianFoodDb.match(name);
    if (food != null) {
      return FoodEntry(
        name: food.name,
        foodId: food.id,
        quantity: quantity,
        unit: food.unit,
        nutrients: food.perUnit * quantity,
        source: NutrientSource.database,
      );
    }
    return FoodEntry(
      name: _titleCase(name.trim()),
      foodId: null,
      quantity: quantity,
      unit: unit,
      nutrients: aiEstimate ?? Nutrients.zero,
      source: NutrientSource.aiEstimate,
    );
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class MealAnalysisException implements Exception {
  final String message;
  const MealAnalysisException(this.message);
  @override
  String toString() => message;
}

abstract class MealAnalyzer {
  Future<MealAnalysis> analyze({required Uint8List imageJpeg, String? description});
}

/// Calls the backend function. [invoke] is injected (the app passes a
/// Supabase Functions call; tests pass a fake) so this file has no
/// network or Supabase dependency of its own.
class RemoteMealAnalyzer implements MealAnalyzer {
  static const functionName = 'analyze-meal';

  /// Photos above this size are refused before upload (the picker
  /// already downsizes; this is a safety net for slow networks).
  static const maxImageBytes = 1500 * 1024;

  final Future<Object?> Function(String functionName, Map<String, Object?> body) invoke;

  const RemoteMealAnalyzer(this.invoke);

  @override
  Future<MealAnalysis> analyze({required Uint8List imageJpeg, String? description}) async {
    if (imageJpeg.isEmpty) throw const MealAnalysisException('No photo to analyse.');
    if (imageJpeg.length > maxImageBytes) {
      throw const MealAnalysisException('That photo is too large — please try again.');
    }
    final Object? raw;
    try {
      raw = await invoke(functionName, {
        'image': base64Encode(imageJpeg),
        'mediaType': 'image/jpeg',
        if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      });
    } catch (e) {
      // FunctionCallException (from the app's invoker) carries the HTTP status.
      final status = _statusOf(e);
      if (status == 401 || status == 403) {
        throw const MealAnalysisException('Your session expired. Please sign out and sign in again.');
      }
      if (status == 404) {
        throw const MealAnalysisException("Photo analysis isn't switched on yet (server function missing).");
      }
      if (status != null && status >= 500) {
        throw const MealAnalysisException('Photo analysis is busy right now. Try again, or type your meal.');
      }
      throw const MealAnalysisException("Couldn't reach HUX — check your connection and try again.");
    }
    final json = raw is String ? _tryDecode(raw) : raw;
    if (json is! Map) throw const MealAnalysisException("Couldn't read that photo — try another angle.");
    if (json['error'] == 'daily_limit') {
      throw const MealAnalysisException(
          "You've used today's photo analyses. Type your meal instead, or try again tomorrow.");
    }
    final analysis = MealAnalysisParser.parse(Map<String, Object?>.from(json));
    if (analysis.items.isEmpty) {
      throw const MealAnalysisException("No food found in that photo. Try again, or type it instead.");
    }
    return analysis;
  }

  /// HTTP status from a FunctionCallException-like error, if any.
  static int? _statusOf(Object e) {
    try {
      final s = (e as dynamic).status;
      return s is int ? s : null;
    } catch (_) {
      return null;
    }
  }

  static Object? _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}
