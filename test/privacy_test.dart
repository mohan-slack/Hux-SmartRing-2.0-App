/// Privacy & account: consent record, download my data, delete local
/// data, delete account (order and failure safety).
/// Run with: flutter test

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/auth/auth_models.dart';
import 'package:hux_app/core/auth/auth_service.dart';
import 'package:hux_app/core/legal/privacy_notice.dart';
import 'package:hux_app/core/legal/privacy_service.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeAuth implements AuthService {
  final log = <String>[];
  bool failDelete = false;

  @override
  Stream<AuthUser?> get authStateChanges => const Stream.empty();
  @override
  AuthUser? get currentUser => const AuthUser(id: 'u1', email: 'a@b.in');
  @override
  Future<void> signInWithEmail({required String email, required String password}) async {}
  @override
  Future<void> signUpWithEmail({required String email, required String password}) async {}
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signInWithApple() async {}
  @override
  Future<void> sendPasswordResetCode(String email) async {}
  @override
  Future<void> verifyPasswordResetCode({required String email, required String code, required String newPassword}) async {}
  @override
  Future<void> verifySignUpCode({required String email, required String code}) async {}
  @override
  Future<void> resendSignUpCode(String email) async {}
  @override
  Future<void> signOut() async => log.add('signOut');
  @override
  Future<void> deleteAccount() async {
    log.add('deleteAccount');
    if (failDelete) throw const AuthException("Couldn't delete your account. Please try again.");
  }
}

void main() {
  sqfliteFfiInit();
  Future<SqliteHealthStore> openStore() => SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  group('Consent', () {
    test('needed until agreed; re-asked when the notice version changes', () async {
      final store = await openStore();
      final svc = PrivacyService(store, now: () => DateTime.utc(2026, 10, 22));
      expect(await svc.needsConsent(), isTrue);
      await svc.recordConsent(adultConfirmed: true);
      expect(await svc.needsConsent(), isFalse);
      expect((await svc.consent())!.version, PrivacyNotice.noticeVersion);

      await store.writeSetting(
          PrivacyService.consentKey, jsonEncode({'version': 'old', 'at': '2026-01-01T00:00:00Z', 'adult': true}));
      expect(await svc.needsConsent(), isTrue);
      await store.close();
    });

    test('adults only', () async {
      final store = await openStore();
      expect(() => PrivacyService(store).recordConsent(adultConfirmed: false), throwsArgumentError);
      expect(await PrivacyService(store).needsConsent(), isTrue);
      await store.close();
    });

    test('every data use says why and where', () {
      for (final u in PrivacyNotice.uses) {
        expect(u.what, isNotEmpty);
        expect(u.why, isNotEmpty);
        expect(u.where, isNotEmpty);
      }
      expect(PrivacyNotice.uses.where((u) => u.where.contains('Groq')).every((u) => u.optional), isTrue);
    });
  });

  group('Download my data', () {
    test('includes readings, sleep and app data, as valid JSON', () async {
      final store = await openStore();
      await store.setDataOwnerId('u1');
      await store.saveSnapshots([HealthSnapshot(timestamp: DateTime.utc(2026, 10, 20, 8), steps: 4321)]);
      final bed = DateTime.utc(2026, 10, 20, 17);
      await store.saveSleepSessions([
        SleepSession(
          bedtime: bed,
          wakeTime: bed.add(const Duration(hours: 7)),
          segments: [SleepSegment(start: bed, end: bed.add(const Duration(hours: 7)), stage: SleepStage.deep)],
        ),
      ]);
      await store.writeSetting('journal_v1', jsonEncode({'2026-10-20': ['sweets']}));

      final out = jsonDecode(await PrivacyService(store, auth: FakeAuth(), now: () => DateTime.utc(2026, 10, 22))
          .exportJson()) as Map<String, Object?>;
      expect((out['account'] as Map)['email'], 'a@b.in');
      expect(((out['readings'] as List).single as Map)['steps'], 4321);
      expect(((out['sleep'] as List).single as Map)['totalSleepMinutes'], 420);
      expect((out['appData'] as Map)['journal_v1'], {'2026-10-20': ['sweets']});
      expect((out['appData'] as Map).containsKey('owner'), isFalse); // internal keys stay out
      await store.close();
    });
  });

  group('Delete', () {
    test('delete data on this phone: wipes everything and stops reminders', () async {
      final store = await openStore();
      var stopped = false;
      await store.writeSetting('journal_v1', '{}');
      await PrivacyService(store, stopReminders: () async => stopped = true).deleteLocalData();
      expect(await store.allSettings(), isEmpty);
      expect(stopped, isTrue);
      await store.close();
    });

    test('a reminder error never blocks deleting data', () async {
      final store = await openStore();
      await store.writeSetting('journal_v1', '{}');
      await PrivacyService(store, stopReminders: () async => throw Exception('x')).deleteLocalData();
      expect(await store.allSettings(), isEmpty);
      await store.close();
    });

    test('delete account: server first, then phone, then sign out', () async {
      final store = await openStore();
      final auth = FakeAuth();
      await store.writeSetting('journal_v1', '{}');
      await PrivacyService(store, auth: auth).deleteAccount();
      expect(auth.log, ['deleteAccount', 'signOut']);
      expect(await store.allSettings(), isEmpty);
      await store.close();
    });

    test('if the server delete fails, nothing on the phone is lost', () async {
      final store = await openStore();
      final auth = FakeAuth()..failDelete = true;
      await store.writeSetting('journal_v1', '{}');
      await expectLater(PrivacyService(store, auth: auth).deleteAccount(), throwsA(isA<AuthException>()));
      expect(await store.allSettings(), {'journal_v1': '{}'});
      expect(auth.log, ['deleteAccount']);
      await store.close();
    });
  });
}
