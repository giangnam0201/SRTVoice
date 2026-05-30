import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'tts_api_service.dart';
import 'audio_export_service.dart';

/// Native implementation using the free TTS API (tts-api.netlify.app).
/// Downloads audio for each subtitle with speed adjusted to match timing,
/// then combines into one MP3 file with silence gaps.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  final language = ttsService.currentLanguage ?? 'en';

  onProgress?.call(0, entries.length, 'Downloading audio from TTS API...');

  // Download audio for each subtitle with speed matching its duration
  final segments = <int, Uint8List>{};

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final text = entry.displayText.trim();
    if (text.isEmpty) continue;

    final targetMs = entry.duration.inMilliseconds;

    // Use generateWithTiming - adjusts speed per sentence to fit duration
    final audioBytes = await TtsApiService.generateWithTiming(
      text,
      language,
      targetDurationMs: targetMs,
    );

    if (audioBytes != null && audioBytes.isNotEmpty) {
      segments[i] = audioBytes;
    }

    onProgress?.call(i + 1, entries.length,
        'Downloaded ${i + 1}/${entries.length} (${segments.length} OK)');

    // Small delay between requests to be nice to the API
    await Future.delayed(const Duration(milliseconds: 50));
  }

  if (segments.isEmpty) {
    onProgress?.call(entries.length, entries.length,
        'ERROR: Could not download any audio. Check internet connection.');
    return;
  }

  onProgress?.call(entries.length, entries.length,
      'Combining ${segments.length} segments into MP3...');

  // Combine segments with silence gaps
  final output = BytesBuilder();
  var currentPositionMs = 0;

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final startMs = entry.startTime.inMilliseconds;

    // Add silence before this entry
    if (startMs > currentPositionMs) {
      final silenceMs = startMs - currentPositionMs;
      output.add(_generateMp3Silence(silenceMs));
      currentPositionMs = startMs;
    }

    // Add the speech segment
    final segData = segments[i];
    if (segData != null) {
      output.add(segData);
      // Estimate duration: the API adjusts speed to fit, so assume it matches target
      currentPositionMs += entry.duration.inMilliseconds;
    }

    // Pad to end time if needed
    final endMs = entry.endTime.inMilliseconds;
    if (currentPositionMs < endMs) {
      final padMs = endMs - currentPositionMs;
      if (padMs > 50) {
        output.add(_generateMp3Silence(padMs));
        currentPositionMs = endMs;
      }
    }
  }

  // Save MP3 file
  final mp3Bytes = output.toBytes();

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
  final fileName = 'SRTVoice_$timestamp.mp3';
  final filePath = '${saveDir.path}/$fileName';
  await File(filePath).writeAsBytes(mp3Bytes);

  final sizeMb = mp3Bytes.length / (1024 * 1024);
  final durationSec = currentPositionMs / 1000;

  onProgress?.call(entries.length, entries.length,
      'Done! $fileName\n'
      'Size: ${sizeMb.toStringAsFixed(1)} MB | Duration: ${durationSec.toStringAsFixed(0)}s\n'
      'Saved to: ${saveDir.path}');
}

/// Generate silent MP3 frames for the given duration.
Uint8List _generateMp3Silence(int durationMs) {
  // MP3 frame at 128kbps 44100Hz: 417 bytes, ~26ms
  const frameSize = 417;
  const frameDurationMs = 26;
  final numFrames = (durationMs / frameDurationMs).ceil();

  final silentFrame = Uint8List(frameSize);
  silentFrame[0] = 0xFF;
  silentFrame[1] = 0xFB;
  silentFrame[2] = 0x90;
  silentFrame[3] = 0x00;

  final out = BytesBuilder();
  for (int i = 0; i < numFrames; i++) {
    out.add(silentFrame);
  }
  return out.toBytes();
}
