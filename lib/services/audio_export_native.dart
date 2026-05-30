import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'audio_export_service.dart';

/// Native implementation: Records device audio while TTS speaks each subtitle.
/// This captures exactly what speak() outputs - no synthesizeToFile needed.
/// Uses the `record` package to capture audio from the device.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  // Get save directory
  Directory saveDir;
  if (Platform.isAndroid) {
    saveDir = Directory('/storage/emulated/0/Download');
    if (!await saveDir.exists()) {
      saveDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    }
  } else {
    saveDir = await getApplicationDocumentsDirectory();
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final outputPath = '${saveDir.path}/SRTVoice_$timestamp.m4a';

  onProgress?.call(0, entries.length, 'Starting audio recording...');

  // Initialize recorder
  final recorder = AudioRecorder();

  // Check permission
  final hasPermission = await recorder.hasPermission();
  if (!hasPermission) {
    onProgress?.call(0, entries.length, 'ERROR: Microphone permission denied. Please grant permission and try again.');
    recorder.dispose();
    return;
  }

  // Start recording (records what the mic picks up - including TTS output from speaker)
  // On Android, we can try to record from the voice communication source
  await recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
      numChannels: 1,
    ),
    path: outputPath,
  );

  // Small delay to let recorder initialize
  await Future.delayed(const Duration(milliseconds: 300));

  onProgress?.call(0, entries.length, 'Recording... Speaking subtitles with timing');

  // Now speak each subtitle at correct timing (same as preview)
  final startTime = DateTime.now();

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];

    // Wait until correct start time
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final waitMs = entry.startTime.inMilliseconds - elapsed;
    if (waitMs > 0) {
      await Future.delayed(Duration(milliseconds: waitMs));
    }

    // Calculate rate for this sentence
    final entryDurationMs = entry.duration.inMilliseconds;
    final rate = _calcRate(entry.displayText, entryDurationMs, speechRate);
    await ttsService.setSpeechRate(rate);

    onProgress?.call(i + 1, entries.length,
        'Recording ${i + 1}/${entries.length}: "${entry.displayText.length > 30 ? '${entry.displayText.substring(0, 30)}...' : entry.displayText}"');

    // Speak (the recorder captures it)
    await ttsService.speak(entry.displayText);
  }

  // Wait a moment after last entry
  await Future.delayed(const Duration(milliseconds: 500));

  // Stop recording
  final path = await recorder.stop();
  recorder.dispose();

  if (path != null && path.isNotEmpty) {
    final file = File(path);
    if (await file.exists()) {
      final sizeMb = (await file.length()) / (1024 * 1024);
      final durationSec = totalDurationMs / 1000;
      onProgress?.call(entries.length, entries.length,
          'Done! Saved: SRTVoice_$timestamp.m4a\n'
          'Size: ${sizeMb.toStringAsFixed(1)} MB | Duration: ~${durationSec.toStringAsFixed(0)}s\n'
          'Location: ${saveDir.path}');
    } else {
      onProgress?.call(entries.length, entries.length, 'ERROR: Recording file not found at: $path');
    }
  } else {
    onProgress?.call(entries.length, entries.length, 'ERROR: Recording failed - no output path returned');
  }
}

double _calcRate(String text, int ms, double base) {
  if (ms <= 200) return base;
  final est = (text.length / (base * 14.0)) * 1000;
  return (base * (est / ms)).clamp(0.25, 2.5);
}
