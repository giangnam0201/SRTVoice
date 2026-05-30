import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'audio_export_service.dart';

/// Native (Android/Windows) implementation:
/// Uses speak() with proper timing to play audio live,
/// and synthesizeToFile as backup for file generation.
/// If synthesizeToFile fails (0-byte files), falls back to speak-only mode.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  final tempDir = await getTemporaryDirectory();
  final outputDir = Directory('${tempDir.path}/srt_voice_temp');
  if (await outputDir.exists()) {
    await outputDir.delete(recursive: true);
  }
  await outputDir.create(recursive: true);

  final timestamp = DateTime.now().millisecondsSinceEpoch;

  onProgress?.call(0, entries.length, 'Generating audio segments...');

  // First try synthesizeToFile for each segment
  final segmentFiles = <int, File>{};
  bool synthesizeWorks = true;

  // Test with first entry
  final testPath = '${outputDir.path}/test_seg.wav';
  await ttsService.setSpeechRate(speechRate);
  await ttsService.synthesizeToFile(entries.first.displayText, testPath);
  await Future.delayed(const Duration(milliseconds: 800));

  final testFile = File(testPath);
  if (!await testFile.exists() || await testFile.length() <= 44) {
    synthesizeWorks = false;
  }

  if (synthesizeWorks) {
    // synthesizeToFile works! Generate all segments
    segmentFiles[0] = testFile;

    for (int i = 1; i < entries.length; i++) {
      final entry = entries[i];
      final segmentPath = '${outputDir.path}/seg_$i.wav';

      final entryDurationMs = entry.duration.inMilliseconds;
      final adjustedRate = _calculateRate(entry.displayText, entryDurationMs, speechRate);
      await ttsService.setSpeechRate(adjustedRate);

      await ttsService.synthesizeToFile(entry.displayText, segmentPath);
      await Future.delayed(const Duration(milliseconds: 600));

      final file = File(segmentPath);
      if (await file.exists() && await file.length() > 44) {
        segmentFiles[i] = file;
      }

      onProgress?.call(i + 1, entries.length, 'Generated ${i + 1}/${entries.length}');
    }

    // Also generate first entry with correct rate
    final firstEntryDuration = entries.first.duration.inMilliseconds;
    final firstRate = _calculateRate(entries.first.displayText, firstEntryDuration, speechRate);
    if (firstRate != speechRate) {
      await ttsService.setSpeechRate(firstRate);
      final firstSegPath = '${outputDir.path}/seg_0_fixed.wav';
      await ttsService.synthesizeToFile(entries.first.displayText, firstSegPath);
      await Future.delayed(const Duration(milliseconds: 600));
      final f = File(firstSegPath);
      if (await f.exists() && await f.length() > 44) {
        segmentFiles[0] = f;
      }
    }

    // Combine into final WAV
    await _combineSegments(entries, segmentFiles, outputDir, timestamp, onProgress);
  } else {
    // synthesizeToFile doesn't work on this device
    // Fall back to speaking with timing (live playback only)
    onProgress?.call(0, entries.length,
        'synthesizeToFile not supported. Using live playback with timing...');

    await _speakWithTiming(entries, ttsService, speechRate, onProgress);
  }

  // Clean up
  try { await outputDir.delete(recursive: true); } catch (_) {}
}

/// Combine WAV segments into one file with correct timing gaps.
Future<void> _combineSegments(
  List<SubtitleEntry> entries,
  Map<int, File> segmentFiles,
  Directory outputDir,
  int timestamp,
  Function(int current, int total, String status)? onProgress,
) async {
  if (segmentFiles.isEmpty) {
    onProgress?.call(0, 0, 'ERROR: No audio segments generated.');
    return;
  }

  // Read first file to detect format
  int sampleRate = 22050;
  int channels = 1;
  int bitsPerSample = 16;

  final firstBytes = await segmentFiles.values.first.readAsBytes();
  if (firstBytes.length > 44 && firstBytes[0] == 0x52 && firstBytes[1] == 0x49) {
    final hdr = ByteData.sublistView(firstBytes);
    channels = hdr.getUint16(22, Endian.little);
    sampleRate = hdr.getUint32(24, Endian.little);
    bitsPerSample = hdr.getUint16(34, Endian.little);
  }

  final bytesPerMs = (sampleRate * channels * (bitsPerSample ~/ 8)) / 1000;
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final audioData = BytesBuilder();
  var currentMs = 0;

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final startMs = entry.startTime.inMilliseconds;

    // Silence before entry
    if (startMs > currentMs) {
      final silenceBytes = ((startMs - currentMs) * bytesPerMs).round();
      final aligned = silenceBytes - (silenceBytes % blockAlign);
      if (aligned > 0) audioData.add(Uint8List(aligned));
      currentMs = startMs;
    }

    // Add segment audio
    final segFile = segmentFiles[i];
    if (segFile != null) {
      final bytes = await segFile.readAsBytes();
      final dataOffset = _findDataChunk(bytes);
      if (dataOffset > 0 && dataOffset < bytes.length) {
        final audio = bytes.sublist(dataOffset);
        audioData.add(audio);
        currentMs += (audio.length / bytesPerMs).round();
      }
    }

    // Pad to end time
    final endMs = entry.endTime.inMilliseconds;
    if (currentMs < endMs) {
      final padBytes = ((endMs - currentMs) * bytesPerMs).round();
      final aligned = padBytes - (padBytes % blockAlign);
      if (aligned > 0) audioData.add(Uint8List(aligned));
      currentMs = endMs;
    }
  }

  // Write final WAV
  final raw = audioData.toBytes();
  final header = createWavHeader(dataSize: raw.length, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample);
  final wav = BytesBuilder();
  wav.add(header);
  wav.add(raw);
  final wavBytes = wav.toBytes();

  // Save
  Directory saveDir;
  if (Platform.isAndroid) {
    saveDir = Directory('/storage/emulated/0/Download');
    if (!await saveDir.exists()) {
      saveDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    }
  } else {
    saveDir = await getApplicationDocumentsDirectory();
  }

  final fileName = 'SRTVoice_$timestamp.wav';
  final outPath = '${saveDir.path}/$fileName';
  await File(outPath).writeAsBytes(wavBytes);

  final sizeMb = wavBytes.length / (1024 * 1024);
  final durSec = currentMs / 1000;
  onProgress?.call(entries.length, entries.length,
      'Done! File: $fileName\nSize: ${sizeMb.toStringAsFixed(1)} MB | Duration: ${durSec.toStringAsFixed(1)}s\nSaved to: ${saveDir.path}');
}

/// Fallback: speak each subtitle at correct timing (no file output).
Future<void> _speakWithTiming(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  Function(int current, int total, String status)? onProgress,
) async {
  final startTime = DateTime.now();

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];

    // Wait until correct start time
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final waitMs = entry.startTime.inMilliseconds - elapsed;
    if (waitMs > 0) await Future.delayed(Duration(milliseconds: waitMs));

    // Adjust rate for this sentence
    final entryDurationMs = entry.duration.inMilliseconds;
    final adjustedRate = _calculateRate(entry.displayText, entryDurationMs, speechRate);
    await ttsService.setSpeechRate(adjustedRate);

    onProgress?.call(i + 1, entries.length,
        'Speaking ${i + 1}/${entries.length} (rate: ${adjustedRate.toStringAsFixed(2)})');

    await ttsService.speak(entry.displayText);
  }

  onProgress?.call(entries.length, entries.length,
      'Playback complete! (File export not supported on this device - synthesizeToFile unavailable)');
}

/// Find the data chunk offset in a WAV file.
int _findDataChunk(Uint8List bytes) {
  for (int i = 12; i < bytes.length - 8; i++) {
    if (bytes[i] == 0x64 && bytes[i + 1] == 0x61 &&
        bytes[i + 2] == 0x74 && bytes[i + 3] == 0x61) {
      return i + 8;
    }
  }
  return 44; // fallback
}

/// Calculate rate per sentence.
double _calculateRate(String text, int durationMs, double baseRate) {
  if (durationMs <= 200) return baseRate;
  final charCount = text.length;
  final charsPerSec = baseRate * 14.0;
  final estimatedMs = (charCount / charsPerSec) * 1000;
  var rate = baseRate * (estimatedMs / durationMs);
  return rate.clamp(0.25, 2.5);
}
