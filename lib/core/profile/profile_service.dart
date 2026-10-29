/// HUX Profile Service
/// -------------------
/// Persists the onboarding answers and how often each feature is opened,
/// and asks [PersonalisationEngine] for today's featured cards. The only
/// class screens talk to for personalisation.
library;

import 'dart:convert';

import '../storage/health_store.dart';
import 'feature_catalog.dart';
import 'personalisation_engine.dart';
import 'user_profile.dart';

class ProfileService {
  static const _profileKey = 'user_profile';
  static const _opensKey = 'feature_opens';

  /// Usage counts only look back this far, so cards re-rank weekly.
  static const usageWindow = Duration(days: 7);

  /// Opens older than this are dropped when saving (keeps the row small).
  static const _keepOpensFor = Duration(days: 30);

  final HealthStore _store;
  final PersonalisationEngine _engine;

  ProfileService(this._store, {PersonalisationEngine engine = const PersonalisationEngine()})
      : _engine = engine;

  /// Null until the user has finished (or skipped) onboarding once.
  Future<UserProfile?> loadProfile() async {
    final raw = await _store.readSetting(_profileKey);
    if (raw == null) return null;
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      // Corrupt row: treat as "onboarding not done" rather than crash.
      return null;
    }
  }

  Future<void> saveProfile(UserProfile profile) =>
      _store.writeSetting(_profileKey, jsonEncode(profile.toJson()));

  Future<void> recordOpen(FeatureId id, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final opens = await _loadOpens();
    final cutoff = at.subtract(_keepOpensFor).millisecondsSinceEpoch;
    final list = [...?opens[id.name], at.millisecondsSinceEpoch]
        .where((ms) => ms >= cutoff)
        .toList();
    opens[id.name] = list;
    for (final key in opens.keys.toList()) {
      opens[key] = opens[key]!.where((ms) => ms >= cutoff).toList();
      if (opens[key]!.isEmpty) opens.remove(key);
    }
    await _store.writeSetting(_opensKey, jsonEncode(opens));
  }

  /// Opens per feature within [usageWindow] of [now].
  Future<Map<FeatureId, int>> recentOpens({DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final cutoff = at.subtract(usageWindow).millisecondsSinceEpoch;
    final opens = await _loadOpens();
    final result = <FeatureId, int>{};
    for (final id in FeatureId.values) {
      final count = (opens[id.name] ?? const <int>[]).where((ms) => ms >= cutoff).length;
      if (count > 0) result[id] = count;
    }
    return result;
  }

  /// Today's 2–4 featured cards for the saved profile (or defaults).
  Future<List<FeatureId>> featured({DateTime? now}) async {
    final profile = await loadProfile() ?? const UserProfile();
    final opens = await recentOpens(now: now);
    return _engine.featuredFor(profile, opens: opens);
  }

  static const _votesKey = 'feature_votes';

  /// "I want this sooner" on a coming-soon feature. Kept locally for now;
  /// sent to the backend (anonymously, with consent) once it exists.
  Future<void> vote(FeatureId id) async {
    final votes = await votedFeatures();
    votes.add(id);
    await _store.writeSetting(_votesKey, jsonEncode(votes.map((v) => v.name).toList()));
  }

  Future<Set<FeatureId>> votedFeatures() async {
    final raw = await _store.readSetting(_votesKey);
    if (raw == null) return {};
    try {
      final names = (jsonDecode(raw) as List).whereType<String>().toSet();
      return {for (final id in FeatureId.values) if (names.contains(id.name)) id};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, List<int>>> _loadOpens() async {
    final raw = await _store.readSetting(_opensKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return {
        for (final e in decoded.entries)
          if (e.value is List) e.key: (e.value as List).whereType<int>().toList(),
      };
    } catch (_) {
      return {};
    }
  }
}
