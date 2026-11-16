/// Light / dark theme: the user's choice, or "Auto" which follows the
/// clock — dark from [nightStartsHour] in the evening to
/// [nightEndsHour] in the morning.
///
/// The choice is saved on the phone. Changing it swaps
/// [HuxPalette.current]; the app root listens and rebuilds everything.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/storage/health_store.dart';
import 'hux_tokens.dart';

enum HuxThemeChoice { auto, light, dark }

extension HuxThemeChoiceLabel on HuxThemeChoice {
  String get label => switch (this) {
        HuxThemeChoice.auto => 'Auto',
        HuxThemeChoice.light => 'Light',
        HuxThemeChoice.dark => 'Dark',
      };
}

class HuxThemeController extends ChangeNotifier {
  HuxThemeController._();

  /// One controller for the app (colours are read from a single place).
  static final instance = HuxThemeController._();

  static const _key = 'theme_choice_v1';

  /// Auto: dark from 7 PM…
  static const nightStartsHour = 19;

  /// …until 6 AM.
  static const nightEndsHour = 6;

  HealthStore? _store;
  Timer? _timer;
  DateTime Function() _now = DateTime.now;

  HuxThemeChoice _choice = HuxThemeChoice.light;
  HuxThemeChoice get choice => _choice;

  bool get isDark => HuxPalette.current.dark;

  /// True when [t] falls in the dark part of the day.
  static bool isNightAt(DateTime t) {
    final h = t.toLocal().hour;
    return h >= nightStartsHour || h < nightEndsHour;
  }

  /// What [choice] means at [t].
  static bool darkFor(HuxThemeChoice choice, DateTime t) => switch (choice) {
        HuxThemeChoice.auto => isNightAt(t),
        HuxThemeChoice.light => false,
        HuxThemeChoice.dark => true,
      };

  /// The next moment Auto flips (7 PM or 6 AM).
  static DateTime nextFlip(DateTime t) {
    final l = t.toLocal();
    final evening = DateTime(l.year, l.month, l.day, nightStartsHour);
    final morning = DateTime(l.year, l.month, l.day, nightEndsHour);
    if (l.isBefore(morning)) return morning;
    if (l.isBefore(evening)) return evening;
    return morning.add(const Duration(days: 1));
  }

  /// Reads the saved choice (Auto when nothing is saved) and applies it.
  /// Call once at start-up; until then the app is light.
  Future<void> load(HealthStore store, {DateTime Function()? now}) async {
    _store = store;
    if (now != null) _now = now;
    var choice = HuxThemeChoice.auto;
    try {
      final raw = await store.readSetting(_key);
      choice = HuxThemeChoice.values.where((c) => c.name == raw).firstOrNull ?? HuxThemeChoice.auto;
    } catch (_) {}
    _choice = choice;
    _apply();
  }

  Future<void> setChoice(HuxThemeChoice choice) async {
    _choice = choice;
    _apply();
    try {
      await _store?.writeSetting(_key, choice.name);
    } catch (_) {}
  }

  /// Re-checks the clock (call when the app comes back to the front).
  void refresh() => _apply();

  void _apply() {
    final dark = darkFor(_choice, _now());
    _timer?.cancel();
    _timer = null;
    if (_choice == HuxThemeChoice.auto && _store != null) {
      final wait = nextFlip(_now()).difference(_now()) + const Duration(seconds: 1);
      _timer = Timer(wait, _apply);
    }
    if (dark == HuxPalette.current.dark) {
      notifyListeners(); // the choice itself may have changed (for the picker)
      return;
    }
    HuxPalette.current = dark ? HuxPalette.night : HuxPalette.light;
    notifyListeners();
  }

  /// For tests: back to light, nothing saved, no timer.
  @visibleForTesting
  void reset() {
    _timer?.cancel();
    _timer = null;
    _store = null;
    _now = DateTime.now;
    _choice = HuxThemeChoice.light;
    HuxPalette.current = HuxPalette.light;
  }
}
