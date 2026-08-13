/// HUX Sleep Wording
/// -------------------
/// Centralizes the "last night" <-> "last sleep" swap that Night Shift
/// mode needs. When the user's main sleep happens in the daytime,
/// every place the readout would otherwise say "last night" / "overnight"
/// / "tonight" reads through here instead — so turning Night Shift on
/// or off is ONE switch (this file), not a find-and-replace across
/// meaning_engine.dart and every content string that mentions sleep
/// timing.
///
/// Pure Dart, no Flutter, no storage — just a bundle of strings keyed
/// on a single boolean.
class SleepWording {
  final bool nightShiftActive;

  const SleepWording({this.nightShiftActive = false});

  /// Standalone noun phrase: "last night" / "your last sleep".
  String get lastSleepPeriod =>
      nightShiftActive ? 'your last sleep' : 'last night';

  /// Possessive, sentence-initial: "Last night's" / "Your last sleep's".
  String get lastSleepPossessive =>
      nightShiftActive ? "Your last sleep's" : "Last night's";

  /// Adverbial: "overnight" / "during your last sleep".
  String get duringLastSleep =>
      nightShiftActive ? 'during your last sleep' : 'overnight';

  /// Forward-looking: "tonight" / "before your next sleep".
  String get nextSleepPeriod =>
      nightShiftActive ? 'before your next sleep' : 'tonight';
}
