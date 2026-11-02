/// HUX coach chat: consent, local chat history, and talking to the
/// backend function `coach-chat` (the AI key lives there, never here).
///
/// Privacy:
/// - Nothing is sent until the user agrees ([giveConsent]); they can
///   withdraw any time ([withdrawConsent]) — that also deletes the chat.
/// - Each message carries only the small [CoachContext] summary and the
///   last few chat turns. Chat history is kept ON THE PHONE only.
library;

import 'dart:convert';

import '../storage/health_store.dart';
import 'coach_context.dart';
import 'safety.dart';

enum ChatRole { user, coach }

/// Specialist threads. Each keeps its own chat on the phone and tells the
/// backend which focus to use. [general] is the original single chat.
enum CoachTopic { general, sleep, food, move }

extension CoachTopicLabel on CoachTopic {
  String get label => switch (this) {
        CoachTopic.general => 'All-round',
        CoachTopic.sleep => 'Sleep',
        CoachTopic.food => 'Food',
        CoachTopic.move => 'Movement',
      };

  /// One line under the name: what this coach is for.
  String get blurb => switch (this) {
        CoachTopic.general => 'Your day, energy and anything else',
        CoachTopic.sleep => 'Bedtime, wind-down, naps, caffeine',
        CoachTopic.food => 'Meals, protein, portions, timing',
        CoachTopic.move => 'Walks, workouts, form, recovery',
      };
}

class ChatMessage {
  final ChatRole role;
  final String text;
  final DateTime at;

  /// Shown above a user message that matched [SafetyCheck].
  final SafetyKind? safety;

  /// A coach reply the user reported (Google Play AI-content policy).
  final bool reported;

  const ChatMessage({required this.role, required this.text, required this.at, this.safety, this.reported = false});

  ChatMessage markReported() => ChatMessage(role: role, text: text, at: at, safety: safety, reported: true);

  Map<String, Object?> toJson() => {
        'r': role.name,
        't': text,
        'at': at.toUtc().toIso8601String(),
        if (safety != null) 's': safety!.name,
        if (reported) 'rep': true,
      };

  static ChatMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    final role = ChatRole.values.where((r) => r.name == j['r']).firstOrNull;
    final text = j['t'];
    final at = DateTime.tryParse('${j['at']}');
    if (role == null || text is! String || at == null) return null;
    return ChatMessage(
      role: role,
      text: text,
      at: at,
      safety: SafetyKind.values.where((s) => s.name == j['s']).firstOrNull,
      reported: j['rep'] == true,
    );
  }
}

/// Why a coach reply was reported.
enum ReportReason { harmful, wrong, offensive, other }

extension ReportReasonLabel on ReportReason {
  String get label => switch (this) {
        ReportReason.harmful => 'Unsafe or harmful advice',
        ReportReason.wrong => 'Wrong or misleading',
        ReportReason.offensive => 'Offensive or inappropriate',
        ReportReason.other => 'Something else',
      };
}

enum CoachErrorKind { noConsent, offline, dailyLimit, unavailable, tooLong, signedOut, notDeployed }

/// Thrown by the app's [FunctionInvoker] when the backend answered with
/// an HTTP error (so HUX can say WHY, instead of "couldn't reach").
class FunctionCallException implements Exception {
  final int? status;
  final String? detail;
  const FunctionCallException(this.status, [this.detail]);

  @override
  String toString() => 'FunctionCallException($status${detail == null ? '' : ': $detail'})';
}

const _isRelease = bool.fromEnvironment('dart.vm.product');

class CoachException implements Exception {
  final CoachErrorKind kind;

  /// Technical detail (HTTP status / server message), shown in debug only.
  final String? detail;
  const CoachException(this.kind, [this.detail]);

  /// Maps a failed backend call to a clear error.
  factory CoachException.fromCall(Object error) {
    if (error is FunctionCallException) {
      final s = error.status;
      final d = 'HTTP $s${error.detail == null ? '' : ' — ${error.detail}'}';
      if (s == 401 || s == 403) return CoachException(CoachErrorKind.signedOut, d);
      if (s == 404) return CoachException(CoachErrorKind.notDeployed, d);
      if (s != null && s >= 500) return CoachException(CoachErrorKind.unavailable, d);
      return CoachException(CoachErrorKind.offline, d);
    }
    return CoachException(CoachErrorKind.offline, error.toString());
  }

  String get message => (switch (kind) {
        CoachErrorKind.noConsent => 'Please agree to sharing first.',
        CoachErrorKind.offline => "Couldn't reach the coach. Check your internet and try again.",
        CoachErrorKind.dailyLimit => "You've reached today's coach limit. It resets tomorrow.",
        CoachErrorKind.unavailable => 'The coach is busy right now. Please try again in a bit.',
        CoachErrorKind.tooLong => 'That message is a bit long — please keep it under '
            '${CoachService.maxMessageChars} characters.',
        CoachErrorKind.signedOut => 'Your session expired. Please sign out and sign in again.',
        CoachErrorKind.notDeployed => "The coach isn't switched on yet (server function missing).",
      }) +
      (!_isRelease && detail != null ? '\n[debug: $detail]' : '');

  @override
  String toString() => 'CoachException($kind)';
}

/// Calls a backend function by name with a JSON body; returns its JSON.
typedef FunctionInvoker = Future<Object?> Function(String functionName, Map<String, Object?> body);

class CoachService {
  static const functionName = 'coach-chat';
  static const reportFunctionName = 'coach-report';
  static const _historyKey = 'coach_chat_v1';
  static const _consentKey = 'coach_consent_v1';

  /// Chat turns sent with each message (the backend caps this too).
  static const turnsSent = 12;

  /// Messages kept on the phone.
  static const keepMessages = 200;
  static const maxMessageChars = 1000;

  final HealthStore _store;
  final FunctionInvoker? _invoke;
  final Future<CoachContext> Function() _loadContext;
  final DateTime Function() _now;

  /// [invoke] null = no backend configured (the screen says so).
  CoachService(
    this._store, {
    FunctionInvoker? invoke,
    required Future<CoachContext> Function() loadContext,
    DateTime Function()? now,
  })  : _invoke = invoke,
        _loadContext = loadContext,
        _now = now ?? DateTime.now;

  bool get hasBackend => _invoke != null;

  Future<bool> hasConsent() async => (await _store.readSetting(_consentKey)) == 'yes';

  Future<void> giveConsent() => _store.writeSetting(_consentKey, 'yes');

  /// Where [topic]'s chat is kept. General keeps the original key so
  /// existing chats survive the update.
  static String historyKeyFor(CoachTopic topic) =>
      topic == CoachTopic.general ? _historyKey : '${_historyKey}_${topic.name}';

  /// Stops sharing AND deletes the chat history on the phone.
  Future<void> withdrawConsent() async {
    await _store.writeSetting(_consentKey, 'no');
    await clearHistory();
  }

  Future<CoachContext> previewContext() => _loadContext();

  Future<List<ChatMessage>> history({CoachTopic topic = CoachTopic.general}) async {
    final raw = await _store.readSetting(historyKeyFor(topic));
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final out = <ChatMessage>[];
      for (final j in list) {
        final m = ChatMessage.fromJson(j);
        if (m != null) out.add(m);
      }
      return out;
    } catch (_) {
      return const []; // Corrupt history: start fresh rather than crash.
    }
  }

  /// Clears [topic]'s chat, or every chat when [topic] is null.
  Future<void> clearHistory({CoachTopic? topic}) async {
    for (final t in topic == null ? CoachTopic.values : [topic]) {
      await _store.writeSetting(historyKeyFor(t), '[]');
    }
  }

  /// Last message per topic (for the thread list), newest chats first.
  Future<Map<CoachTopic, ChatMessage?>> lastMessages() async => {
        for (final t in CoachTopic.values) t: (await history(topic: t)).lastOrNull,
      };

  Future<void> _saveHistory(List<ChatMessage> all, CoachTopic topic) {
    final kept = all.length > keepMessages ? all.sublist(all.length - keepMessages) : all;
    return _store.writeSetting(historyKeyFor(topic), jsonEncode([for (final m in kept) m.toJson()]));
  }

  /// Sends [text]; returns the updated history (user message + reply).
  /// The user's message is saved even if the reply fails, so nothing
  /// they typed is lost.
  Future<List<ChatMessage>> send(String text, {CoachTopic topic = CoachTopic.general}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return history(topic: topic);
    if (trimmed.length > maxMessageChars) throw const CoachException(CoachErrorKind.tooLong);
    if (!await hasConsent()) throw const CoachException(CoachErrorKind.noConsent);
    final invoke = _invoke;
    if (invoke == null) throw const CoachException(CoachErrorKind.unavailable);

    final safety = SafetyCheck.check(trimmed)?.kind;
    final all = [
      ...await history(topic: topic),
      ChatMessage(role: ChatRole.user, text: trimmed, at: _now(), safety: safety),
    ];
    await _saveHistory(all, topic);

    return _reply(all, safety, topic);
  }

  /// Re-sends the last message if it never got a reply (after an error).
  /// Returns the updated history; throws [CoachException] like [send].
  Future<List<ChatMessage>> retryLast({CoachTopic topic = CoachTopic.general}) async {
    final all = await history(topic: topic);
    if (all.isEmpty || all.last.role != ChatRole.user) return all;
    if (!await hasConsent()) throw const CoachException(CoachErrorKind.noConsent);
    if (_invoke == null) throw const CoachException(CoachErrorKind.unavailable);
    return _reply(all, all.last.safety, topic);
  }

  /// True when the last message is the user's (no reply yet).
  static bool awaitingReply(List<ChatMessage> all) => all.isNotEmpty && all.last.role == ChatRole.user;

  Future<List<ChatMessage>> _reply(List<ChatMessage> all, SafetyKind? safety, CoachTopic topic) async {
    final invoke = _invoke!;
    final context = await _loadContext();
    final recent = all.length > turnsSent ? all.sublist(all.length - turnsSent) : all;
    final Object? raw;
    try {
      raw = await invoke(functionName, {
        'messages': [
          for (final m in recent) {'role': m.role == ChatRole.user ? 'user' : 'assistant', 'content': m.text},
        ],
        'context': context.toJson(),
        'style': context.style?.name ?? 'dost',
        'language': context.language?.name ?? 'english',
        if (safety != null) 'safety': safety.name,
        if (topic != CoachTopic.general) 'topic': topic.name,
      });
    } catch (e) {
      throw CoachException.fromCall(e);
    }

    final reply = parseReply(raw);
    final withReply = [...all, ChatMessage(role: ChatRole.coach, text: reply, at: _now())];
    await _saveHistory(withReply, topic);
    return withReply;
  }

  /// Reports the coach reply at [index] in [history] (Google Play's
  /// AI-generated content policy: users must be able to flag replies in
  /// the app). Sends ONLY that reply, the question before it, and the
  /// reason — never the health summary. Returns the updated history.
  Future<List<ChatMessage>> report(int index, ReportReason reason, {CoachTopic topic = CoachTopic.general}) async {
    final all = [...await history(topic: topic)];
    if (index < 0 || index >= all.length || all[index].role != ChatRole.coach) {
      throw ArgumentError('Not a coach reply');
    }
    final invoke = _invoke;
    if (invoke == null) throw const CoachException(CoachErrorKind.unavailable);
    String? question;
    for (var i = index - 1; i >= 0; i--) {
      if (all[i].role == ChatRole.user) {
        question = all[i].text;
        break;
      }
    }
    try {
      await invoke(reportFunctionName, {
        'reason': reason.name,
        'reply': all[index].text,
        if (question != null) 'question': question,
      });
    } catch (e) {
      throw CoachException.fromCall(e);
    }
    all[index] = all[index].markReported();
    await _saveHistory(all, topic);
    return all;
  }

  /// The backend answers `{"reply": "..."}` or `{"error": "daily_limit"}`.
  static String parseReply(Object? raw) {
    Object? data = raw;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        throw const CoachException(CoachErrorKind.unavailable);
      }
    }
    if (data is! Map) throw const CoachException(CoachErrorKind.unavailable);
    if (data['error'] == 'daily_limit') throw const CoachException(CoachErrorKind.dailyLimit);
    final reply = data['reply'];
    if (reply is! String || reply.trim().isEmpty) throw const CoachException(CoachErrorKind.unavailable);
    return reply.trim();
  }
}
