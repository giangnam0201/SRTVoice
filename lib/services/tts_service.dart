import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  Completer<void>? _speakCompleter;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    if (!kIsWeb) {
      await _flutterTts.setSharedInstance(true);
    }
    
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);

    _flutterTts.setCompletionHandler(() {
      _speakCompleter?.complete();
      _speakCompleter = null;
    });

    _flutterTts.setErrorHandler((msg) {
      _speakCompleter?.completeError(Exception('TTS Error: $msg'));
      _speakCompleter = null;
    });

    _isInitialized = true;
  }

  Future<List<Map<String, String>>> getVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null && voices is List) {
        return List<Map<String, String>>.from(
          voices.map((v) {
            if (v is Map) {
              return Map<String, String>.from(
                v.map((key, value) => MapEntry(key.toString(), value.toString())),
              );
            }
            return <String, String>{};
          }),
        ).where((v) => v.isNotEmpty).toList();
      }
    } catch (e) {
      print('Error getting voices: $e');
    }
    return [];
  }

  Future<List<String>> getLanguages() async {
    try {
      final languages = await _flutterTts.getLanguages;
      if (languages != null && languages is List) {
        final list = List<String>.from(languages);
        list.sort();
        return list;
      }
    } catch (e) {
      print('Error getting languages: $e');
    }
    return [];
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
    final result = await _flutterTts.speak(text);
    if (result != 1) {
      _speakCompleter?.complete();
      _speakCompleter = null;
      return;
    }
    try {
      await _speakCompleter?.future.timeout(const Duration(seconds: 60));
    } catch (e) {
      // Timeout or error, continue
    }
  }

  /// Synthesize text to a file (Android/Windows/iOS only, not web).
  /// Returns the file name used.
  Future<String?> synthesizeToFile(String text, String fileName) async {
    if (kIsWeb) return null;
    try {
      final result = await _flutterTts.synthesizeToFile(text, fileName);
      if (result == 1) return fileName;
    } catch (e) {
      print('Error synthesizing to file: $e');
    }
    return null;
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
