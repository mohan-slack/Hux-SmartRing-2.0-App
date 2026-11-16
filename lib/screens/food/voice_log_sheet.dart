/// "Say it": speak what you ate, see the words appear, tap Log.
///
/// Uses the phone's own speech recognizer (Google on Android, Apple on
/// iPhone) — HUX never records or keeps audio, only the final words,
/// which then go through the same food list as typing.
library;

import 'package:flutter/material.dart';
import '../../theme/hux_fonts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/profile/user_profile.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_kit.dart';

/// Speech languages offered, by recognizer locale.
const voiceLanguages = <(String locale, String label)>[
  ('en_IN', 'English / Hinglish'),
  ('hi_IN', 'हिंदी'),
  ('te_IN', 'తెలుగు'),
  ('ta_IN', 'தமிழ்'),
  ('kn_IN', 'ಕನ್ನಡ'),
  ('ml_IN', 'മലയാളം'),
];

/// The user's app language → the recognizer locale to start with.
/// Romanised mixes (Tenglish, Hinglish…) use Indian English: the words
/// come out in English letters, which HUX's food list reads directly.
String voiceLocaleFor(AppLanguage? l) => switch (l) {
      AppLanguage.hindi => 'hi_IN',
      AppLanguage.telugu => 'te_IN',
      AppLanguage.tamil => 'ta_IN',
      AppLanguage.kannada => 'kn_IN',
      AppLanguage.malayalam => 'ml_IN',
      _ => 'en_IN',
    };

/// Opens the sheet; returns the words to log, or null.
Future<String?> showVoiceLogSheet(BuildContext context, {AppLanguage? language}) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: HuxColors.bg,
      builder: (_) => _VoiceSheet(locale: voiceLocaleFor(language)),
    );

class _VoiceSheet extends StatefulWidget {
  final String locale;
  const _VoiceSheet({required this.locale});

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _speech = SpeechToText();
  late String _locale = widget.locale;
  String _words = '';
  bool _ready = false;
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!_ready) {
        _ready = await _speech.initialize(
          onStatus: (s) {
            if (!mounted) return;
            setState(() => _listening = s == SpeechToText.listeningStatus);
          },
          onError: (e) {
            if (!mounted) return;
            setState(() {
              _listening = false;
              _error = e.errorMsg.contains('no_match') || e.errorMsg.contains('speech_timeout')
                  ? "Didn't catch that — tap the mic and try again."
                  : "Voice isn't working right now. You can type it instead.";
            });
          },
        );
      }
      if (!_ready) {
        setState(() => _error = 'Allow the microphone for HUX in Settings to log by voice.');
        return;
      }
      setState(() => _error = null);
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          if (mounted) setState(() => _words = r.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: _locale,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = "Voice isn't available on this phone. You can type it instead.");
    }
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
    } else {
      setState(() => _words = '');
      await _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWords = _words.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Say what you ate',
                style: huxSora(textStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: huxInk))),
            const SizedBox(height: 4),
            Text('e.g. "two roti, dal and a glass of buttermilk" · "rendu idli sambar" · "do paratha aur dahi"',
                style: TextStyle(fontSize: 14, height: 1.35, color: huxMuted)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (loc, label) in voiceLanguages)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: loc == _locale,
                        showCheckmark: false,
                        onSelected: (_) async {
                          await _speech.cancel();
                          setState(() {
                            _locale = loc;
                            _words = '';
                          });
                          await _start();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: _toggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: _listening ? 96 : 84,
                  height: _listening ? 96 : 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening ? HuxColors.accentPink : huxInk,
                    boxShadow: [
                      if (_listening)
                        BoxShadow(color: HuxColors.accentPink.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4),
                    ],
                  ),
                  child: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? (_listening ? 'Listening…' : hasWords ? 'Tap the mic to say it again' : 'Tap the mic and speak'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _error != null ? HuxColors.rundown : huxMuted),
            ),
            const SizedBox(height: 12),
            HuxTile(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Text(
                  hasWords ? _words : '…',
                  style: TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w600, color: hasWords ? huxInk : huxMuted),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: hasWords ? () => Navigator.pop(context, _words.trim()) : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
              child: const Text('Log this', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            Text("Your phone's speech service turns speech into words; HUX keeps no audio.",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: huxMuted)),
          ],
        ),
      ),
    );
  }
}
