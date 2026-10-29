/// Text-to-speech behind an interface (tests use a fake).
library;

import 'package:flutter_tts/flutter_tts.dart';

abstract class Speaker {
  /// Returns false when the phone has no voice for [languageTag].
  Future<bool> setLanguage(String languageTag);
  Future<void> speak(String text);
  Future<void> stop();
}

class TtsSpeaker implements Speaker {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<bool> setLanguage(String languageTag) async {
    try {
      final available = await _tts.isLanguageAvailable(languageTag);
      if (available != true) return false;
      await _tts.setLanguage(languageTag);
      await _tts.setSpeechRate(0.5);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Voice is a bonus; the on-screen timer still works.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing to stop.
    }
  }
}
