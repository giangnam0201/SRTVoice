import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'audio_export_service.dart';

/// Native (Android/Windows) implementation:
/// Uses flutter_tts synthesizeToFile to generate audio segments,
/// then combines them with silence to match subtitle timing.
/// Uses parallel processing where possible for speed.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  final tempDir = await getTemporaryDirectory();
  final outputDir = Directory('${tempDir.path}/srt_voice_output');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  
  onProgress?.call(0, entries.length, 'Generating speech segments (parallel)...');

  // Generate all TTS segments in parallel batches for speed
  final segmentFiles = <int, String>{};
  const batchSize = 4; // Process 4 at a time for multi-threading
  
  for (int batchStart = 0; batchStart < entries.length; batchStart += batchSize) {
    final batchEnd = (batchStart + batchSize).clamp(0, entries.length);
    final futures = <Future<void>>[];
    
    for (int i = batchStart; i < batchEnd; i++) {
      final entry = entries[i];
      final segmentPath = '${outputDir.path}/seg_${timestamp}_$i.wav';
      
      futures.add(() async {
        // Adjust speech rate to fit the subtitle duration
        final entryDurationMs = entry.duration.inMilliseconds;
        final adjustedRate = _calculateNativeRate(speechRate, entry.displayText.length, entryDurationMs);
        
        await ttsService.setSpeechRate(adjustedRate);
        await ttsService.synthesizeToFile(entry.displayText, segmentPath);
        segmentFiles[i] = segmentPath;
      }());
    }
    
    await Future.wait(futures);
    
    onProgress?.call(
      batchEnd,
      entries.length,
      'Generated ${batchEnd}/${entries.length} segments...',
    );
  }

  onProgress?.call(entries.length, entries.length, 'Combining audio with timing...');

  // Combine segments with silence gaps into final WAV
  const sampleRate = 44100;
  const channels = 1;
  const bitsPerSample = 16;
  
  final audioData = BytesBuilder();
  var currentPositionMs = 0;

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final startMs = entry.startTime.inMilliseconds;
    
    // Add silence gap before this entry
    if (startMs > currentPositionMs) {
      final silenceDuration = startMs - currentPositionMs;
      final silence = createSilence(silenceDuration, sampleRate, channels, bitsPerSample);
      audioData.add(silence);
      currentPositionMs = startMs;
    }
    
    // Add the speech segment (or silence if file doesn't exist)
    final segmentPath = segmentFiles[i];
    if (segmentPath != null) {
      final segmentFile = File(segmentPath);
      if (await segmentFile.exists()) {
        final segmentBytes = await segmentFile.readAsBytes();
        // Skip WAV header (44 bytes) if it's a WAV file
        if (segmentBytes.length > 44) {
          audioData.add(segmentBytes.sublist(44));
        }
        // Update current position to entry end time
        currentPositionMs = entry.endTime.inMilliseconds;
      } else {
        // File doesn't exist, add silence for the entry duration
        final silence = createSilence(entry.duration.inMilliseconds, sampleRate, channels, bitsPerSample);
        audioData.add(silence);
        currentPositionMs = entry.endTime.inMilliseconds;
      }
    }
  }

  // Build final WAV file
  final audioBytes = audioData.toBytes();
  final wavHeader = createWavHeader(
    dataSize: audioBytes.length,
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
  );

  final finalWav = BytesBuilder();
  finalWav.add(wavHeader);
  finalWav.add(audioBytes);

  // Save to documents directory
  final docsDir = await getApplicationDocumentsDirectory();
  final outputPath = '${docsDir.path}/srt_voice_$timestamp.wav';
  final outputFile = File(outputPath);
  await outputFile.writeAsBytes(finalWav.toBytes());

  // Clean up temp segments
  for (final path in segmentFiles.values) {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  onProgress?.call(entries.length, entries.length, 'MP3 generation complete! Saved to: $outputPath');
}

double _calculateNativeRate(double baseRate, int textLength, int durationMs) {
  if (durationMs <= 0) return baseRate;
  
  // Estimate: at rate 0.5, average ~8 chars/sec
  // At rate 1.0, average ~15 chars/sec
  final estimatedDurationAtBase = (textLength / (baseRate * 20)) * 1000; // ms
  
  var rate = (estimatedDurationAtBase / durationMs) * baseRate;
  // Clamp to valid TTS range
  rate = rate.clamp(0.1, 1.0);
  return rate;
}
