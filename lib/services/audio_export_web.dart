import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'audio_export_service.dart';

/// Web implementation: Speaks each subtitle at correct timing using Web Speech API.
/// Adjusts speech rate per sentence to match subtitle duration.
/// On web we cannot export to file, so we just play with correct timing.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  onProgress?.call(0, entries.length, 'Playing with subtitle timing (Web)...');

  final synth = web.window.speechSynthesis;
  final startTime = DateTime.now();

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];

    // Wait until correct start time
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final waitMs = entry.startTime.inMilliseconds - elapsed;
    if (waitMs > 0) {
      await Future.delayed(Duration(milliseconds: waitMs));
    }

    onProgress?.call(i + 1, entries.length, 'Speaking ${i + 1}/${entries.length}...');

    // Calculate rate for THIS sentence to fit its duration
    final entryDurationMs = entry.duration.inMilliseconds;
    final adjustedRate = _calculateWebRate(entry.displayText, entryDurationMs, speechRate);

    // Speak
    final utterance = web.SpeechSynthesisUtterance(entry.displayText);
    utterance.rate = adjustedRate;
    utterance.pitch = 1.0;
    utterance.volume = 1.0;

    final completer = Completer<void>();
    utterance.onend = ((web.Event e) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    utterance.onerror = ((web.Event e) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;

    synth.speak(utterance);

    try {
      await completer.future.timeout(Duration(milliseconds: entryDurationMs + 3000));
    } catch (_) {
      synth.cancel();
    }
  }

  onProgress?.call(entries.length, entries.length,
      'Playback complete! (Web cannot export to MP3 file - use Android/Windows for file export)');
}

/// Calculate speech rate for a specific sentence on web.
double _calculateWebRate(String text, int durationMs, double baseRate) {
  if (durationMs <= 0) return 1.0;

  // Web Speech API rate: 0.1 to 10.0, default 1.0
  // At rate 1.0, roughly ~13 chars/sec for English
  final charCount = text.length;
  final estimatedMsAtRate1 = (charCount / 13.0) * 1000;

  var rate = estimatedMsAtRate1 / durationMs;
  rate = rate.clamp(0.5, 4.0);
  return rate;
}
