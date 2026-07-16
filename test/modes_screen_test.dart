/// Widget tests for [ModesScreen]. Run with: flutter test
///
/// See today_screen_test.dart for why real async DB work here goes
/// through `tester.runAsync()` rather than `pumpAndSettle()` alone.
///
/// Deliberately avoids driving Flutter's real `showDatePicker` dialog:
/// it proved unreliable to automate in this environment (a tap into
/// its calendar grid hung indefinitely). Tests that need an ACTIVE
/// mode pre-seed it directly via [ModeService.startMode] instead —
/// the setup-sheet-to-service wiring for a chosen date is a single,
/// direct call (see `_onTapMode`'s `Navigator.pop` handoff), so the
/// picker itself is the only untested link, and it's a stock Flutter
/// widget outside this app's code.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/modes/mode.dart';
import 'package:hux_app/core/modes/mode_service.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:hux_app/screens/modes_screen.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  testWidgets('lists all three modes with no active card when none is set',
      (tester) async {
    late SqliteHealthStore store;
    await tester.runAsync(() async {
      store = await openStore();
    });
    addTearDown(() => store.close());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ModesScreen(modeService: ModeService(store))),
    ));
    await settle(tester);

    expect(find.text('Big Day'), findsOneWidget);
    expect(find.text('Shaadi'), findsOneWidget);
    expect(find.text('Exam Season'), findsOneWidget);
    expect(find.textContaining('Active:'), findsNothing);
  });

  testWidgets(
      'tapping a mode opens its setup sheet, disabled until a date is '
      'chosen', (tester) async {
    late SqliteHealthStore store;
    await tester.runAsync(() async {
      store = await openStore();
    });
    addTearDown(() => store.close());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ModesScreen(modeService: ModeService(store))),
    ));
    await settle(tester);

    // _onTapMode awaits a real activeConfig() DB read before showing
    // the sheet, so this needs settle() (see today_screen_test.dart),
    // followed by pumpAndSettle() for the sheet's entrance animation.
    await tester.tap(find.text('Shaadi'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Set up Shaadi'), findsOneWidget);
    expect(find.text('Choose a date'), findsOneWidget);
    final startButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start mode'));
    expect(startButton.onPressed, isNull,
        reason: 'no date chosen yet');
  });

  testWidgets('shows the active mode card and ends it with confirmation',
      (tester) async {
    late SqliteHealthStore store;
    late ModeService modeService;
    await tester.runAsync(() async {
      store = await openStore();
      modeService = ModeService(store);
      await modeService.startMode(EventModeConfig(
        id: ModeId.shaadi,
        targetDate: DateTime.now().add(const Duration(days: 10)),
        label: 'Test wedding',
        startedAt: DateTime.now(),
      ));
    });
    addTearDown(() => store.close());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ModesScreen(modeService: modeService)),
    ));
    await settle(tester);

    expect(find.textContaining('Active: Shaadi'), findsOneWidget);
    expect(find.textContaining('Test wedding'), findsOneWidget);
    expect(find.textContaining('10 days to go'), findsOneWidget);

    // End it, with confirmation (pure UI: opening the dialog).
    await tester.tap(find.text('End mode'));
    await tester.pumpAndSettle();
    expect(find.text('End this mode?'), findsOneWidget);

    // Two "End mode" texts now exist (the card's button and the
    // dialog's confirm button) — target the dialog's directly.
    // Confirming triggers a real endMode() write, so settle().
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('End mode'),
    ));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Active:'), findsNothing);
    EventModeConfig? afterEnd;
    await tester.runAsync(() async {
      afterEnd = await modeService.activeConfig();
    });
    expect(afterEnd, isNull);
  });

  testWidgets('starting a different mode while one is active asks to '
      'replace it', (tester) async {
    late SqliteHealthStore store;
    late ModeService modeService;
    await tester.runAsync(() async {
      store = await openStore();
      modeService = ModeService(store);
      await modeService.startMode(EventModeConfig(
        id: ModeId.bigDay,
        targetDate: DateTime.now().add(const Duration(days: 5)),
        startedAt: DateTime.now(),
      ));
    });
    addTearDown(() => store.close());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ModesScreen(modeService: modeService)),
    ));
    await settle(tester);

    expect(find.textContaining('Active: Big Day'), findsOneWidget);

    // _onTapMode awaits a real activeConfig() DB read before deciding
    // to show the replace-confirmation dialog — settle(), not
    // pumpAndSettle() — followed by pumpAndSettle() for the dialog's
    // own entrance animation.
    await tester.tap(find.text('Exam Season'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Replace active mode?'), findsOneWidget);

    // Cancel: the original mode must still be active.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A bare `await modeService...` here (outside runAsync) can hang —
    // same real-vs-fake-timer issue as everywhere else in this file.
    EventModeConfig? config;
    await tester.runAsync(() async {
      config = await modeService.activeConfig();
    });
    expect(config!.id, ModeId.bigDay);
  });
}
