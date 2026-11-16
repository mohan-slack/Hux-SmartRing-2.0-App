/// Light / dark theme: Auto follows the clock, the choice is saved, and
/// the palette swaps.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:hux_app/theme/hux_theme_controller.dart';
import 'package:hux_app/theme/hux_tokens.dart';
import 'package:hux_app/widgets/hux/hux_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final c = HuxThemeController.instance;
  tearDown(c.reset);

  test('night is 7 PM to 6 AM', () {
    expect(HuxThemeController.isNightAt(DateTime(2026, 11, 16, 18, 59)), isFalse);
    expect(HuxThemeController.isNightAt(DateTime(2026, 11, 16, 19, 0)), isTrue);
    expect(HuxThemeController.isNightAt(DateTime(2026, 11, 16, 23, 30)), isTrue);
    expect(HuxThemeController.isNightAt(DateTime(2026, 11, 16, 5, 59)), isTrue);
    expect(HuxThemeController.isNightAt(DateTime(2026, 11, 16, 6, 0)), isFalse);
    expect(HuxThemeController.isNightAt(DateTime(2026, 11, 16, 12)), isFalse);
  });

  test('Auto follows the clock; Light and Dark ignore it', () {
    final noon = DateTime(2026, 11, 16, 12), late = DateTime(2026, 11, 16, 22);
    expect(HuxThemeController.darkFor(HuxThemeChoice.auto, noon), isFalse);
    expect(HuxThemeController.darkFor(HuxThemeChoice.auto, late), isTrue);
    expect(HuxThemeController.darkFor(HuxThemeChoice.light, late), isFalse);
    expect(HuxThemeController.darkFor(HuxThemeChoice.dark, noon), isTrue);
  });

  test('next flip is the coming 6 AM or 7 PM', () {
    expect(HuxThemeController.nextFlip(DateTime(2026, 11, 16, 3)), DateTime(2026, 11, 16, 6));
    expect(HuxThemeController.nextFlip(DateTime(2026, 11, 16, 12)), DateTime(2026, 11, 16, 19));
    expect(HuxThemeController.nextFlip(DateTime(2026, 11, 16, 21)), DateTime(2026, 11, 17, 6));
  });

  test('first run is Auto; the choice is saved and swaps the colours', () async {
    final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
    await c.load(store, now: () => DateTime(2026, 11, 16, 22));
    expect(c.choice, HuxThemeChoice.auto);
    expect(c.isDark, isTrue);
    expect(huxInk, HuxPalette.night.ink);
    expect(HuxColors.card, HuxPalette.night.card);

    var pings = 0;
    c.addListener(() => pings++);
    await c.setChoice(HuxThemeChoice.light);
    expect(c.isDark, isFalse);
    expect(huxInk, HuxPalette.light.ink);
    expect(pings, 1);

    c.reset();
    await c.load(store, now: () => DateTime(2026, 11, 16, 22));
    expect(c.choice, HuxThemeChoice.light, reason: 'saved choice wins over the clock');
    expect(c.isDark, isFalse);
  });

  test('dark text and tiles keep readable contrast', () {
    double lum(int argb) {
      double ch(int v) {
        final s = v / 255;
        return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * ch((argb >> 16) & 255) + 0.7152 * ch((argb >> 8) & 255) + 0.0722 * ch(argb & 255);
    }

    double ratio(int a, int b) {
      final la = lum(a), lb = lum(b);
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    for (final p in [HuxPalette.light, HuxPalette.night]) {
      expect(ratio(p.ink.toARGB32(), p.card.toARGB32()), greaterThan(7), reason: 'ink on card');
      expect(ratio(p.muted.toARGB32(), p.card.toARGB32()), greaterThan(4.5), reason: 'muted on card');
      expect(ratio(0xFFFFFFFF, p.solid.toARGB32()), greaterThan(4.5), reason: 'white on solid');
    }
  });
}
