import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'audio_export_service.dart';

/// Native (Android/Windows) implementation:
/// Generates each subtitle as a separate WAV file with adjusted speech rate,
/// then combines all segments with silence gaps into one final WAV file.
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

  onProgress?.call(0, entries.length, 'Generating speech segments...');

  // Generate each segment ONE BY ONE (Android TTS can't do parallel synthesizeToFile)
  final segmentFiles = <int, File>{};

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final segmentPath = '${outputDir.path}/seg_$i.wav';

    // Calculate speech rate for THIS specific entry to fit its duration
    final entryDurationMs = entry.duration.inMilliseconds;
    final adjustedRate = _calculateRate(entry.displayText, entryDurationMs, speechRate);

    // Set the rate for this specific segment
    await ttsService.setSpeechRate(adjustedRate);

    // Synthesize this segment to file
    final result = await ttsService.synthesizeToFile(entry.displayText, segmentPath);

    if (result == 1) {
      final file = File(segmentPath);
      if (await file.exists() && await file.length() > 44) {
        segmentFiles[i] = file;
      }
    }

    onProgress?.call(
      i + 1,
      entries.length,
      'Generated segment ${i + 1}/${entries.length} (rate: ${adjustedRate.toStringAsFixed(2)})',
    );
  }

  onProgress?.call(entries.length, entries.length, 'Combining segments with timing...');

  // Now combine all segments into one WAV file with correct timing
  const sampleRate = 22050; // Standard for TTS
  const channels = 1;
  const bitsPerSample = 16;
  const bytesPerSample = 2;
  final bytesPerMs = (sampleRate * channels * bytesPerSample) / 1000;

  final audioData = BytesBuilder();
  var currentPositionMs = 0;

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final startMs = entry.startTime.inMilliseconds;

    // Add silence gap before this entry if needed
    if (startMs > currentPositionMs) {
      final silenceMs = startMs - currentPositionMs;
      final silenceBytes = (silenceMs * bytesPerMs).round();
      // Make sure it's even (16-bit samples)
      final alignedBytes = silenceBytes - (silenceBytes % 2);
      if (alignedBytes > 0) {
        audioData.add(Uint8List(alignedBytes));
      }
      currentPositionMs = startMs;
    }

    // Add the speech segment audio data
    final segmentFile = segmentFiles[i];
    if (segmentFile != null && await segmentFile.exists()) {
      final segmentBytes = await segmentFile.readAsBytes();
      // Skip WAV header (44 bytes)
      if (segmentBytes.length > 44) {
        final audioContent = segmentBytes.sublist(44);
        audioData.add(audioContent);
        // Calculate how many ms of audio we added
        final addedMs = (audioContent.length / bytesPerMs).round();
        currentPositionMs += addedMs;
      }
    }

    // If current position is past the end time, that's fine
    // If it's before end time, add silence to pad to end time
    final endMs = entry.endTime.inMilliseconds;
    if (currentPositionMs < endMs) {
      final padMs = endMs - currentPositionMs;
      final padBytes = (padMs * bytesPerMs).round();
      final alignedPad = padBytes - (padBytes % 2);
      if (alignedPad > 0) {
        audioData.add(Uint8List(alignedPad));
      }
      currentPositionMs = endMs;
    }
  }

  // Build final WAV file
  final rawAudio = audioData.toBytes();
  final wavHeader = createWavHeader(
    dataSize: rawAudio.length,
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
  );

  final finalWav = BytesBuilder();
  finalWav.add(wavHeader);
  finalWav.add(rawAudio);

  // Save to Downloads or Documents with a proper name
  Directory? saveDir;
  if (Platform.isAndroid) {
    // Save to external storage Downloads
    saveDir = Directory('/storage/emulated/0/Download');
    if (!await saveDir.exists()) {
      saveDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    }
  } else {
    saveDir = await getApplicationDocumentsDirectory();
  }

  final outputFileName = 'SRTVoice_$timestamp.wav';
  final outputPath = '${saveDir.path}/$outputFileName';
  final outputFile = File(outputPath);
  await outputFile.writeAsBytes(finalWav.toBytes());

  // Clean up temp files
  try {
    await outputDir.delete(recursive: true);
  } catch (_) {}

  final fileSizeMb = (await outputFile.length()) / (1024 * 1024);
  onProgress?.call(
    entries.length,
    entries.length,
    'Done! Saved: $outputFileName (${fileSizeMb.toStringAsFixed(1)} MB)\nPath: $outputPath',
  );
}

/// Calculate the speech rate for a specific subtitle entry.
/// Adjusts rate so the spoken text fits within the entry's duration.
double _calculateRate(String text, int durationMs, double baseRate) {
  if (durationMs <= 0) return baseRate;

  // Rough estimation of speaking duration at base rate:
  // At rate 0.5: ~6-8 chars/sec for most languages
  // At rate 1.0: ~12-15 chars/sec
  // We estimate based on character count
  final charCount = text.length;
  
  // Estimated ms to speak at the base rate
  // At baseRate=0.5, assume ~7 chars/sec = ~143ms per char
  // At baseRate=1.0, assume ~14 chars/sec = ~71ms per char
  final msPerChar = 143.0 / (baseRate * 2);
  final estimatedMs = charCount * msPerChar;

  // Calculate needed rate adjustment
  // If estimated > duration, we need to speed up (higher rate)
  // If estimated < duration, we need to slow down (lower rate)
  var neededRate = baseRate * (estimatedMs / durationMs);

  // Clamp to valid Android TTS range (0.1 to 4.0, but practical is 0.25 to 2.0)
  neededRate = neededRate.clamp(0.25, 2.0);

  return neededRate;
}
