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
    });

    _flutterTts.setErrorHandler((msg) {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.completeError(Exception('TTS Error: $msg'));
      }
    });

    _isInitialized = true;
  }

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
        result.sort((a, b) {
          final c = a['locale']!.compareTo(b['locale']!);
          if (c != 0) return c;
          return a['name']!.compareTo(b['name']!);
        });
        return result;
      }
    } catch (e) {
      print('Error getting voices: $e');
    }
    return [];
  }

  List<Map<String, String>> filterVoicesByLanguage(
    List<Map<String, String>> allVoices, String languageCode) {
    return allVoices.where((voice) {
      final locale = voice['locale'] ?? '';
      return locale.toLowerCase().startsWith(languageCode.toLowerCase().split('-').first);
    }).toList();
  }

  String getVoiceDisplayName(Map<String, String> voice) {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    String display = name;
    // Clean up Android voice names like "com.google.android.tts:en-us-x-sfg#male_1-local"
    if (display.contains(':')) display = display.split(':').last;
    if (display.contains('#')) {
      final parts = display.split('#');
      display = parts.last;
    }
    // Replace underscores/dashes with spaces and capitalize
    display = display.replaceAll('_', ' ').replaceAll('-', ' ');
    if (display.isNotEmpty) {
      display = display.split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
    }
    return '$display ($locale)';
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

  Future<void> setLanguage(String language) async => await _flutterTts.setLanguage(language);
  Future<void> setVoice(Map<String, String> voice) async => await _flutterTts.setVoice(voice);
  Future<void> setSpeechRate(double rate) async => await _flutterTts.setSpeechRate(rate);
  Future<void> setPitch(double pitch) async => await _flutterTts.setPitch(pitch);
  Future<void> setVolume(double volume) async => await _flutterTts.setVolume(volume);

  /// Speak text and wait for completion.
  Future<void> speak(String text) async {
    _speakCompleter = Completer<void>();
    final result = await _flutterTts.speak(text);
    if (result != 1) {
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) _speakCompleter!.complete();
      return;
    }
    try {
      await _speakCompleter?.future.timeout(const Duration(seconds: 60));
    } catch (_) {}
  }

  /// Synthesize to file. Waits for the TTS engine to finish writing.
  Future<int> synthesizeToFile(String text, String filePath) async {
    if (kIsWeb) return 0;
    _speakCompleter = Completer<void>();
    try {
      final result = await _flutterTts.synthesizeToFile(text, filePath);
      if (result == 1) {
        // Wait for TTS completion callback
        await _speakCompleter?.future.timeout(const Duration(seconds: 30));
        return 1;
      }
    } catch (e) {
      print('synthesizeToFile error: $e');
    }
    return 0;
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    if (_speakCompleter != null && !_speakCompleter!.isCompleted) _speakCompleter!.complete();
    _speakCompleter = null;
  }

  void dispose() => _flutterTts.stop();
}
