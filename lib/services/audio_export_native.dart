import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'tts_api_service.dart';
import 'audio_export_service.dart';

/// Native implementation using FREE Google Translate TTS API.
/// Downloads MP3 for each subtitle, then combines them into one MP3 file
/// with silence gaps matching the subtitle timing.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  // Determine language from TTS service or default to English
  final language = ttsService.currentLanguage ?? 'en';

  onProgress?.call(0, entries.length, 'Downloading audio from TTS API...');

  // Download MP3 for each subtitle entry
  final segments = <int, Uint8List>{};

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final text = entry.displayText;

    if (text.trim().isEmpty) continue;

    final mp3Bytes = await TtsApiService.generateMp3(text, language);

    if (mp3Bytes != null && mp3Bytes.isNotEmpty) {
      segments[i] = mp3Bytes;
    }

    onProgress?.call(i + 1, entries.length,
        'Downloaded ${i + 1}/${entries.length} segments (${segments.length} OK)');

    // Small delay to avoid rate limiting
    await Future.delayed(const Duration(milliseconds: 100));
  }

  if (segments.isEmpty) {
    onProgress?.call(entries.length, entries.length,
        'ERROR: Could not download any audio. Check internet connection.');
    return;
  }

  onProgress?.call(entries.length, entries.length,
      'Combining ${segments.length} segments into MP3...');

  // Combine MP3 segments with silence gaps for correct timing.
  // MP3 silence: we generate silent MP3 frames.
  // Since we're concatenating MP3s, we just add silent MP3 data between segments.
  final output = BytesBuilder();
  var currentPositionMs = 0;

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final startMs = entry.startTime.inMilliseconds;

    // Add silence before this entry if needed
    if (startMs > currentPositionMs) {
      final silenceMs = startMs - currentPositionMs;
      final silenceBytes = _generateMp3Silence(silenceMs);
      output.add(silenceBytes);
      currentPositionMs = startMs;
    }

    // Add the speech MP3 segment
    final segmentData = segments[i];
    if (segmentData != null) {
      output.add(segmentData);
      // Estimate duration of this MP3 segment
      // MP3 at ~32kbps: roughly 4000 bytes/sec, so duration = bytes/4000 * 1000 ms
      // But Google TTS is usually 32kbps mono
      final estimatedMs = (segmentData.length / 4000 * 1000).round();
      currentPositionMs += estimatedMs;
    }

    // If we're past the entry end time, that's fine (audio longer than subtitle slot)
    // If we're before end time, add silence to pad
    final endMs = entry.endTime.inMilliseconds;
    if (currentPositionMs < endMs) {
      final padMs = endMs - currentPositionMs;
      if (padMs > 50) {
        output.add(_generateMp3Silence(padMs));
        currentPositionMs = endMs;
      }
    }
  }

  // Save the combined MP3 to Downloads
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

/// Generate silent MP3 data for the given duration.
/// Uses a minimal valid MP3 frame (MPEG1 Layer3 128kbps 44100Hz stereo)
/// that produces silence.
Uint8List _generateMp3Silence(int durationMs) {
  // A single MP3 frame at 128kbps/44100Hz is 417 bytes and lasts ~26ms
  // For silence, we use frames with all audio samples = 0
  // Minimal silent MP3 frame (MPEG1, Layer 3, 128kbps, 44100Hz, stereo):
  // Frame header: FF FB 90 00, then padding zeros
  const frameSize = 417; // bytes per frame at 128kbps 44100Hz
  const frameDurationMs = 26; // ms per frame

  final numFrames = (durationMs / frameDurationMs).ceil();
  final silentFrame = Uint8List(frameSize);
  // MP3 frame header for MPEG1, Layer3, 128kbps, 44100Hz, Stereo
  silentFrame[0] = 0xFF;
  silentFrame[1] = 0xFB;
  silentFrame[2] = 0x90;
  silentFrame[3] = 0x00;
  // Rest is zeros = silence

  final output = BytesBuilder();
  for (int i = 0; i < numFrames; i++) {
    output.add(silentFrame);
  }
  return output.toBytes();
}
