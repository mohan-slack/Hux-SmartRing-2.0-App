/// Tests for [SleepWording] — the single switch behind the "last
/// night" <-> "last sleep" swap Night Shift mode drives.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/sleep_wording.dart';

void main() {
  group('Night Shift inactive (default)', () {
    const wording = SleepWording();

    test('uses ordinary "last night" wording throughout', () {
      expect(wording.lastSleepPeriod, 'last night');
      expect(wording.lastSleepPossessive, "Last night's");
      expect(wording.duringLastSleep, 'overnight');
      expect(wording.nextSleepPeriod, 'tonight');
    });
  });

  group('Night Shift active', () {
    const wording = SleepWording(nightShiftActive: true);

    test('never says "last night" anywhere', () {
      final all = [
        wording.lastSleepPeriod,
        wording.lastSleepPossessive,
        wording.duringLastSleep,
        wording.nextSleepPeriod,
      ].join(' ').toLowerCase();

      expect(all.contains('last night'), isFalse);
      expect(all.contains('overnight'), isFalse);
      expect(all.contains('tonight'), isFalse);
    });

    test('every field mentions sleep in a day-sleeper-appropriate way', () {
      expect(wording.lastSleepPeriod, 'your last sleep');
      expect(wording.lastSleepPossessive, "Your last sleep's");
      expect(wording.duringLastSleep, 'during your last sleep');
      expect(wording.nextSleepPeriod, 'before your next sleep');
    });
  });
}
