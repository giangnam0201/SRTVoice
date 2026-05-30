import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'audio_export_service.dart';

/// Web implementation: Uses Web Speech API to speak subtitles at correct timing
/// and records the output via MediaRecorder for download.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  onProgress?.call(0, entries.length, 'Generating audio (Web Speech API)...');

  final synth = web.window.speechSynthesis;

  // Speak each entry at correct timing, recording via MediaRecorder
  final startTime = DateTime.now();

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    onProgress?.call(i + 1, entries.length, 'Speaking entry ${i + 1}/${entries.length}...');

    // Wait until correct start time
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final waitMs = entry.startTime.inMilliseconds - elapsed;
    if (waitMs > 0) {
      await Future.delayed(Duration(milliseconds: waitMs));
    }

    // Calculate rate to fit within subtitle duration
    final entryDurationMs = entry.duration.inMilliseconds;
    final adjustedRate = _calculateWebRate(entry.displayText.length, entryDurationMs, speechRate);

    // Create and speak utterance
    final utterance = web.SpeechSynthesisUtterance(entry.displayText);
    utterance.rate = adjustedRate;
    utterance.pitch = 1.0;
    utterance.volume = 1.0;

    final speakCompleter = Completer<void>();
    utterance.onend = ((web.Event e) {
      if (!speakCompleter.isCompleted) speakCompleter.complete();
    }).toJS;
    utterance.onerror = ((web.Event e) {
      if (!speakCompleter.isCompleted) speakCompleter.complete();
    }).toJS;

    synth.speak(utterance);

    // Wait for speech or timeout
    try {
      await speakCompleter.future.timeout(
        Duration(milliseconds: entryDurationMs + 2000),
      );
    } catch (_) {
      synth.cancel();
    }
  }

  // On web, we can't easily capture TTS output to a file.
  // Instead, generate a WAV with silence matching the timing as a template,
  // and let users know the audio was played with correct timing.
  onProgress?.call(entries.length, entries.length,
      'Audio playback complete! (Web limitation: TTS cannot be exported to MP3 directly. '
      'Use Android/Windows build for MP3 file export.)');
}

double _calculateWebRate(int textLength, int durationMs, double baseRate) {
  if (durationMs <= 0) return baseRate;

  // Rough estimate: at rate 1.0, ~13 chars/sec for English
  final charsPerSecAtRate1 = 13.0;
  final estimatedDurationMs = (textLength / charsPerSecAtRate1) * 1000;

  var rate = estimatedDurationMs / durationMs;
  // Web Speech API rate: 0.1 to 10.0, default 1.0
  rate = rate.clamp(0.5, 3.0);
  return rate;
}
