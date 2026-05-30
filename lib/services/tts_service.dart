import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  List<Map<String, String>> _voices = [];
  List<String> _languages = [];
  Completer<void>? _speakCompleter;

  Future<void> initialize() async {
    if (kIsWeb) {
      await _flutterTts.awaitSpeakCompletion(true);
    } else {
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
    }

    _flutterTts.setCompletionHandler(() {
      _speakCompleter?.complete();
      _speakCompleter = null;
    });

    _flutterTts.setErrorHandler((msg) {
      _speakCompleter?.completeError(msg);
      _speakCompleter = null;
    });
  }

  Future<List<Map<String, String>>> getVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null) {
        _voices = List<Map<String, String>>.from(
          (voices as List).map((v) => Map<String, String>.from(
            (v as Map).map((key, value) => MapEntry(key.toString(), value.toString())),
          )),
        );
      }
    } catch (e) {
      print('Error getting voices: $e');
    }
    return _voices;
  }

  Future<List<String>> getLanguages() async {
    try {
      final languages = await _flutterTts.getLanguages;
      if (languages != null) {
        _languages = List<String>.from(languages as List);
        _languages.sort();
      }
    } catch (e) {
      print('Error getting languages: $e');
    }
    return _languages;
  }

  Future<void> setLanguage(String language) async {
    await _flutterTts.setLanguage(language);
  }

  Future<void> setVoice(Map<String, String> voice) async {
    await _flutterTts.setVoice(voice);
  }

  Future<void> setSpeechRate(double rate) async {
    await _flutterTts.setSpeechRate(rate);
  }

  Future<void> setPitch(double pitch) async {
    await _flutterTts.setPitch(pitch);
  }

  Future<void> setVolume(double volume) async {
    await _flutterTts.setVolume(volume);
  }

  /// Speak text and wait for completion.
  Future<void> speak(String text) async {
    _speakCompleter = Completer<void>();
    await _flutterTts.speak(text);
    await _speakCompleter?.future;
  }

  /// Stop speaking.
  Future<void> stop() async {
    await _flutterTts.stop();
    _speakCompleter?.complete();
    _speakCompleter = null;
  }

  void dispose() {
    _flutterTts.stop();
  }
}
