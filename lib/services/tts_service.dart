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
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
      _speakCompleter = null;
    });

    _flutterTts.setErrorHandler((msg) {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.completeError(Exception('TTS Error: $msg'));
      }
      _speakCompleter = null;
    });

    _isInitialized = true;
  }

  /// Get voices filtered and formatted nicely.
  /// Returns list of maps with 'name' and 'locale' keys.
  Future<List<Map<String, String>>> getVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null && voices is List) {
        final result = <Map<String, String>>[];
        for (final v in voices) {
          if (v is Map) {
            final name = (v['name'] ?? v['Name'] ?? '').toString();
            final locale = (v['locale'] ?? v['Locale'] ?? '').toString();
            if (name.isNotEmpty && locale.isNotEmpty) {
              result.add({'name': name, 'locale': locale});
            }
          }
        }
        // Sort by locale then by name
        result.sort((a, b) {
          final localeCompare = a['locale']!.compareTo(b['locale']!);
          if (localeCompare != 0) return localeCompare;
          return a['name']!.compareTo(b['name']!);
        });
        return result;
      }
    } catch (e) {
      print('Error getting voices: $e');
    }
    return [];
  }

  /// Get voices filtered by a specific language code.
  List<Map<String, String>> filterVoicesByLanguage(
    List<Map<String, String>> allVoices,
    String languageCode,
  ) {
    return allVoices.where((voice) {
      final locale = voice['locale'] ?? '';
      return locale.toLowerCase().startsWith(languageCode.toLowerCase());
    }).toList();
  }

  /// Get a readable display name for a voice.
  String getVoiceDisplayName(Map<String, String> voice) {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    // Clean up the name - remove package prefixes
    String displayName = name;
    if (displayName.contains('#')) {
      displayName = displayName.split('#').last;
    }
    if (displayName.contains('.')) {
      displayName = displayName.split('.').last;
    }
    // Capitalize
    if (displayName.isNotEmpty) {
      displayName = displayName[0].toUpperCase() + displayName.substring(1);
    }
    return '$displayName ($locale)';
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
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
      _speakCompleter = null;
      return;
    }
    try {
      await _speakCompleter?.future.timeout(const Duration(seconds: 60));
    } catch (e) {
      // Timeout, continue
    }
  }

  /// Synthesize text to a WAV file (Android/Windows only).
  /// Returns 1 on success.
  Future<int> synthesizeToFile(String text, String filePath) async {
    if (kIsWeb) return 0;
    try {
      _speakCompleter = Completer<void>();
      final result = await _flutterTts.synthesizeToFile(text, filePath);
      if (result == 1) {
        // Wait for completion
        try {
          await _speakCompleter?.future.timeout(const Duration(seconds: 60));
        } catch (_) {}
        return 1;
      }
    } catch (e) {
      print('Error synthesizing to file: $e');
    }
    return 0;
  }

  /// Stop speaking.
  Future<void> stop() async {
    await _flutterTts.stop();
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
      _speakCompleter!.complete();
    }
    _speakCompleter = null;
  }

  void dispose() {
    _flutterTts.stop();
  }
}
