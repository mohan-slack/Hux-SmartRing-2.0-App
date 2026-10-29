/// Coach chat: on-phone safety check, what is shared, consent, history,
/// and talking to the backend (faked).
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/coach/coach_context.dart';
import 'package:hux_app/core/coach/coach_service.dart';
import 'package:hux_app/core/coach/safety.dart';
import 'package:hux_app/core/profile/user_profile.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeBackend {
  final calls = <({String name, Map<String, Object?> body})>[];
  Object? Function(Map<String, Object?> body) respond = (_) => {'reply': 'Take a 10-minute walk after lunch.'};
  bool fail = false;

  Future<Object?> invoke(String name, Map<String, Object?> body) async {
    calls.add((name: name, body: body));
    if (fail) throw Exception('offline');
    return respond(body);
  }
}

const ctx = CoachContext(
  partOfDay: 'morning',
  goals: ['Sleep better'],
  diet: 'Veg',
  style: CoachStyle.amma,
  language: AppLanguage.hinglish,
  charge: 42,
  chargeLabel: 'Low',
  stepsToday: 1200,
  stepGoal: 6000,
);

void main() {
  sqfliteFfiInit();

  group('SafetyCheck', () {
    test('emergencies in English and Hinglish', () {
      expect(SafetyCheck.check('I have chest pain since morning')?.kind, SafetyKind.emergency);
      expect(SafetyCheck.check('seene mein dard ho raha hai')?.kind, SafetyKind.emergency);
      expect(SafetyCheck.check("I  CAN'T   breathe properly")?.kind, SafetyKind.emergency);
    });

    test('self-harm wins and points to Tele-MANAS', () {
      final card = SafetyCheck.check('chest pain and I want to die');
      expect(card?.kind, SafetyKind.selfHarm);
      expect(card!.calls.first.number, '14416');
      expect(SafetyCheck.check('main marna chahta hoon')?.kind, SafetyKind.selfHarm);
    });

    test('everyday words are not flagged', () {
      expect(SafetyCheck.check('My swim strokes got better'), isNull);
      expect(SafetyCheck.check('killing it at the gym today'), isNull);
      expect(SafetyCheck.check('how much protein in dal?'), isNull);
    });
  });

  group('CoachContext', () {
    test('only filled fields are sent; nothing identifying', () {
      final j = ctx.toJson();
      expect(j['charge'], 42);
      expect(j['goals'], ['Sleep better']);
      expect(j.containsKey('usualSleepMin'), isFalse);
      expect(j.keys.any((k) => k.contains('name') || k.contains('email')), isFalse);
    });

    test('preview matches what is sent', () {
      final lines = ctx.preview();
      expect(lines, contains('HUX Charge: 42 (Low)'));
      expect(lines, contains('Steps today: 1200 of 6000'));
      expect(lines.last, 'Time of day: morning');
    });

    test('part of day', () {
      expect(CoachContext.partOfDayFor(3), 'night');
      expect(CoachContext.partOfDayFor(9), 'morning');
      expect(CoachContext.partOfDayFor(14), 'afternoon');
      expect(CoachContext.partOfDayFor(19), 'evening');
      expect(CoachContext.partOfDayFor(23), 'night');
    });

    test('loader works for a brand-new user with no data', () async {
      final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
      final c = await CoachContextLoader(store: store, now: () => DateTime(2026, 10, 22, 8)).load();
      expect(c.partOfDay, 'morning');
      expect(c.charge, isNull);
      expect(c.proteinTodayG, isNull);
      expect(c.streakDays, 0);
      await store.close();
    });
  });

  group('CoachService', () {
    Future<(SqliteHealthStore, FakeBackend, CoachService)> setup({bool backend = true}) async {
      final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
      final fake = FakeBackend();
      final svc = CoachService(
        store,
        invoke: backend ? fake.invoke : null,
        loadContext: () async => ctx,
        now: () => DateTime.utc(2026, 10, 22, 3),
      );
      return (store, fake, svc);
    }

    test('nothing is sent before consent', () async {
      final (store, fake, svc) = await setup();
      await expectLater(
          svc.send('hi'), throwsA(isA<CoachException>().having((e) => e.kind, 'kind', CoachErrorKind.noConsent)));
      expect(fake.calls, isEmpty);
      await store.close();
    });

    test('sends message + context + style/language; saves both sides', () async {
      final (store, fake, svc) = await setup();
      await svc.giveConsent();
      final h = await svc.send('  What should I do today?  ');
      expect(h.map((m) => m.role), [ChatRole.user, ChatRole.coach]);
      expect(h.first.text, 'What should I do today?');
      final call = fake.calls.single;
      expect(call.name, 'coach-chat');
      expect(call.body['style'], 'amma');
      expect(call.body['language'], 'hinglish');
      expect((call.body['context'] as Map)['charge'], 42);
      expect(call.body['messages'], [
        {'role': 'user', 'content': 'What should I do today?'},
      ]);
      expect((await svc.history()).length, 2);
      await store.close();
    });

    test('only the last 12 messages are sent', () async {
      final (store, fake, svc) = await setup();
      await svc.giveConsent();
      for (var i = 0; i < 8; i++) {
        await svc.send('question $i');
      }
      final sent = fake.calls.last.body['messages'] as List;
      expect(sent.length, CoachService.turnsSent);
      expect((sent.last as Map)['content'], 'question 7');
      await store.close();
    });

    test('daily limit and offline: clear errors, typed message kept', () async {
      final (store, fake, svc) = await setup();
      await svc.giveConsent();
      fake.respond = (_) => {'error': 'daily_limit'};
      await expectLater(svc.send('hello'),
          throwsA(isA<CoachException>().having((e) => e.kind, 'kind', CoachErrorKind.dailyLimit)));
      fake.fail = true;
      await expectLater(svc.send('again'),
          throwsA(isA<CoachException>().having((e) => e.kind, 'kind', CoachErrorKind.offline)));
      expect((await svc.history()).map((m) => m.text), ['hello', 'again']);
      await store.close();
    });

    test('too long, or no backend', () async {
      final (store, _, svc) = await setup();
      await svc.giveConsent();
      await expectLater(svc.send('x' * (CoachService.maxMessageChars + 1)),
          throwsA(isA<CoachException>().having((e) => e.kind, 'kind', CoachErrorKind.tooLong)));
      await store.close();

      final (store2, _, offline) = await setup(backend: false);
      await offline.giveConsent();
      expect(offline.hasBackend, isFalse);
      await expectLater(offline.send('hi'),
          throwsA(isA<CoachException>().having((e) => e.kind, 'kind', CoachErrorKind.unavailable)));
      await store2.close();
    });

    test('a red-flag message is marked and the backend is told', () async {
      final (store, fake, svc) = await setup();
      await svc.giveConsent();
      final h = await svc.send('I have chest pain');
      expect(h.first.safety, SafetyKind.emergency);
      expect(fake.calls.single.body['safety'], 'emergency');
      expect((await svc.history()).first.safety, SafetyKind.emergency); // survives reload
      await store.close();
    });

    test('stopping sharing deletes the chat', () async {
      final (store, _, svc) = await setup();
      await svc.giveConsent();
      await svc.send('hi');
      await svc.withdrawConsent();
      expect(await svc.hasConsent(), isFalse);
      expect(await svc.history(), isEmpty);
      await store.close();
    });

    test('reporting a reply sends only the reply, question and reason', () async {
      final (store, fake, svc) = await setup();
      await svc.giveConsent();
      await svc.send('How much protein in dal?');
      final h = await svc.report(1, ReportReason.wrong);
      final call = fake.calls.last;
      expect(call.name, 'coach-report');
      expect(call.body, {
        'reason': 'wrong',
        'reply': 'Take a 10-minute walk after lunch.',
        'question': 'How much protein in dal?',
      });
      expect(h[1].reported, isTrue);
      expect((await svc.history())[1].reported, isTrue); // survives reload
      await expectLater(svc.report(0, ReportReason.other), throwsArgumentError); // user message
      await store.close();
    });

    test('reply parsing', () {
      expect(CoachService.parseReply('{"reply":" ok "}'), 'ok');
      expect(() => CoachService.parseReply({'reply': ''}), throwsA(isA<CoachException>()));
      expect(() => CoachService.parseReply('not json'), throwsA(isA<CoachException>()));
    });
  });
}
