/// Coach notes: a few things the user wants the coach to always keep in
/// mind ("Knee pain — no jumping", "Vegetarian on Tuesdays", "Night
/// shift Mon–Wed"). Kept ON THE PHONE, edited only by the user, and sent
/// with each coach message (part of the shared summary they agreed to).
///
/// Deliberately not "AI memory": the coach never writes here, so nothing
/// is remembered that the user didn't choose — and they can see and
/// delete every line.
library;

import 'dart:convert';

import '../storage/health_store.dart';

class CoachNotes {
  static const _key = 'coach_notes_v1';
  static const maxNotes = 5;
  static const maxChars = 80;

  final HealthStore _store;

  CoachNotes(this._store);

  /// One clean line: trimmed, single spaces, no angle brackets, capped.
  static String? clean(String raw) {
    final t = raw.replaceAll(RegExp(r'[<>{}\[\]`]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return null;
    return t.length > maxChars ? t.substring(0, maxChars).trim() : t;
  }

  Future<List<String>> all() async {
    final raw = await _store.readSetting(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final n in jsonDecode(raw) as List) if (n is String && clean(n) != null) clean(n)!]
          .take(maxNotes)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<String> notes) => _store.writeSetting(_key, jsonEncode(notes.take(maxNotes).toList()));

  /// Adds a note; false when it's empty, a duplicate, or the list is full.
  Future<bool> add(String raw) async {
    final n = clean(raw);
    if (n == null) return false;
    final list = [...await all()];
    if (list.length >= maxNotes || list.any((e) => e.toLowerCase() == n.toLowerCase())) return false;
    await _save([...list, n]);
    return true;
  }

  Future<void> remove(int index) async {
    final list = [...await all()];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _save(list);
  }

  Future<void> clear() => _save(const []);
}
