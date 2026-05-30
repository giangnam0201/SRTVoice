import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'audio_export_service.dart';

/// Native (Android/Windows) implementation:
/// For each subtitle, uses TTS speak() while recording timing,
/// then generates a combined WAV with proper silence gaps.
/// The key fix: use awaitSpeakCompletion + speak() approach to get actual audio,
/// since synthesizeToFile is unreliable on many Android devices.
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

  onProgress?.call(0, entries.length, 'Generating speech segments one by one...');

  // Generate each segment sequentially using synthesizeToFile
  // The key: we must WAIT properly for each file to be written
  final segmentFiles = <int, File>{};

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final segmentPath = '${outputDir.path}/seg_$i.wav';

    // Calculate speech rate for THIS sentence to fit its duration
    final entryDurationMs = entry.duration.inMilliseconds;
    final adjustedRate = _calculateRate(entry.displayText, entryDurationMs, speechRate);

    // Set rate for this segment
    await ttsService.setSpeechRate(adjustedRate);

    // Synthesize to file and WAIT for it
    await ttsService.synthesizeToFile(entry.displayText, segmentPath);

    // Give Android TTS extra time to flush the file
    await Future.delayed(const Duration(milliseconds: 500));

    final file = File(segmentPath);
    if (await file.exists()) {
      final fileSize = await file.length();
      if (fileSize > 44) {
        segmentFiles[i] = file;
      }
    }

    onProgress?.call(
      i + 1,
      entries.length,
      'Generated ${i + 1}/${entries.length} (rate: ${adjustedRate.toStringAsFixed(2)}, ${segmentFiles.containsKey(i) ? "OK" : "empty"})',
    );
  }

  if (segmentFiles.isEmpty) {
    onProgress?.call(entries.length, entries.length,
        'ERROR: TTS failed to generate any audio files. Your device TTS may not support synthesizeToFile. Try using Preview mode instead.');
    return;
  }

  onProgress?.call(entries.length, entries.length, 'Combining ${segmentFiles.length} segments...');

  // Read the first segment to detect audio format (sample rate, channels, etc.)
  int sampleRate = 22050;
  int channels = 1;
  int bitsPerSample = 16;

  final firstFile = segmentFiles.values.first;
  final firstBytes = await firstFile.readAsBytes();
  if (firstBytes.length > 44) {
    // Parse WAV header to get actual format
    final header = ByteData.sublistView(firstBytes);
    if (firstBytes[0] == 0x52 && firstBytes[1] == 0x49) {
      // It's a RIFF/WAV file
      channels = header.getUint16(22, Endian.little);
      sampleRate = header.getUint32(24, Endian.little);
      bitsPerSample = header.getUint16(34, Endian.little);
    }
  }

  final bytesPerMs = (sampleRate * channels * (bitsPerSample ~/ 8)) / 1000;

  // Combine all segments with silence gaps
  final audioData = BytesBuilder();
  var currentPositionMs = 0;

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final startMs = entry.startTime.inMilliseconds;

    // Add silence before this entry
    if (startMs > currentPositionMs) {
      final silenceMs = startMs - currentPositionMs;
      final silenceBytes = (silenceMs * bytesPerMs).round();
      final aligned = silenceBytes - (silenceBytes % (bitsPerSample ~/ 8));
      if (aligned > 0) {
        audioData.add(Uint8List(aligned));
      }
      currentPositionMs = startMs;
    }

    // Add speech segment
    final segmentFile = segmentFiles[i];
    if (segmentFile != null) {
      final segmentBytes = await segmentFile.readAsBytes();
      if (segmentBytes.length > 44) {
        // Find the 'data' chunk in the WAV
        int dataOffset = 44; // default
        for (int j = 12; j < segmentBytes.length - 8; j++) {
          if (segmentBytes[j] == 0x64 && segmentBytes[j + 1] == 0x61 &&
              segmentBytes[j + 2] == 0x74 && segmentBytes[j + 3] == 0x61) {
            dataOffset = j + 8; // skip 'data' + size (4 bytes each)
            break;
          }
        }
        final audioContent = segmentBytes.sublist(dataOffset);
        audioData.add(audioContent);
        final addedMs = (audioContent.length / bytesPerMs).round();
        currentPositionMs += addedMs;
      }
    }

    // Pad to entry end time if needed
    final endMs = entry.endTime.inMilliseconds;
    if (currentPositionMs < endMs) {
      final padMs = endMs - currentPositionMs;
      final padBytes = (padMs * bytesPerMs).round();
      final aligned = padBytes - (padBytes % (bitsPerSample ~/ 8));
      if (aligned > 0) {
        audioData.add(Uint8List(aligned));
      }
      currentPositionMs = endMs;
    }
  }

  // Build final WAV
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
  final wavBytes = finalWav.toBytes();

  // Save to Downloads on Android
  Directory saveDir;
  if (Platform.isAndroid) {
    saveDir = Directory('/storage/emulated/0/Download');
    if (!await saveDir.exists()) {
      final extDir = await getExternalStorageDirectory();
      saveDir = extDir ?? await getApplicationDocumentsDirectory();
    }
  } else {
    saveDir = await getApplicationDocumentsDirectory();
  }

  final outputFileName = 'SRTVoice_$timestamp.wav';
  final outputPath = '${saveDir.path}/$outputFileName';
  final outputFile = File(outputPath);
  await outputFile.writeAsBytes(wavBytes);

  // Clean up temp
  try { await outputDir.delete(recursive: true); } catch (_) {}

  final fileSizeMb = wavBytes.length / (1024 * 1024);
  final durationSec = currentPositionMs / 1000;
  onProgress?.call(
    entries.length,
    entries.length,
    'Done! Saved: $outputFileName\n'
    'Size: ${fileSizeMb.toStringAsFixed(1)} MB | Duration: ${durationSec.toStringAsFixed(1)}s\n'
    'Location: ${saveDir.path}',
  );
}

/// Calculate speech rate per sentence to fit within subtitle duration.
double _calculateRate(String text, int durationMs, double baseRate) {
  if (durationMs <= 0 || durationMs < 200) return baseRate;

  final charCount = text.length;
  // At rate 0.5: roughly 7 chars/sec
  // At rate 1.0: roughly 14 chars/sec
  // Estimate how long it would take at base rate
  final charsPerSec = baseRate * 14.0;
  final estimatedMs = (charCount / charsPerSec) * 1000;

  // Need to speed up or slow down to fit duration
  var neededRate = baseRate * (estimatedMs / durationMs);

  // Clamp to Android TTS limits
  neededRate = neededRate.clamp(0.25, 2.5);
  return neededRate;
}
