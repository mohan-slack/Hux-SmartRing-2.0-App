/// totalSleep counts overlapping segments once (phone + watch nights).
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/ring/ring_models.dart';

void main() {
  SleepSegment seg(int h1, int m1, int h2, int m2, SleepStage st) => SleepSegment(
        start: DateTime(2026, 10, 30, h1, m1),
        end: DateTime(2026, 10, 30, h2, m2),
        stage: st,
      );

  SleepSession night(List<SleepSegment> segs) => SleepSession(
        bedtime: segs.first.start,
        wakeTime: segs.last.end,
        segments: segs,
      );

  test('duplicate sources are not added up', () {
    final s = night([
      seg(0, 5, 7, 5, SleepStage.light), // "asleep" from the phone
      seg(0, 10, 3, 0, SleepStage.deep), // watch stages on top
      seg(3, 0, 7, 0, SleepStage.rem),
    ]);
    expect(s.totalSleep, const Duration(hours: 7));
  });

  test('awake gaps are left out', () {
    final s = night([
      seg(0, 0, 3, 0, SleepStage.light),
      seg(3, 0, 3, 30, SleepStage.awake),
      seg(3, 30, 7, 0, SleepStage.deep),
    ]);
    expect(s.totalSleep, const Duration(hours: 6, minutes: 30));
  });
}
