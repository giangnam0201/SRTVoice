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
/// then concatenates all segments directly into one audio file.
/// No fake silence frames - just real audio back to back.
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
  final segments = <Uint8List>[];

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final text = entry.displayText.trim();

    if (text.isEmpty) continue;

    final targetMs = entry.duration.inMilliseconds;

    // Generate audio with speed adjusted to fit the subtitle duration
    final audioBytes = await TtsApiService.generateWithTiming(
      text,
      language,
      targetDurationMs: targetMs,
    );

    if (audioBytes != null && audioBytes.isNotEmpty) {
      segments.add(audioBytes);
    } else {
      // If API fails for this entry, skip it
      onProgress?.call(i + 1, entries.length,
          'Warning: Failed to get audio for entry ${i + 1}, skipping...');
    }

    onProgress?.call(i + 1, entries.length,
        'Downloaded ${i + 1}/${entries.length} (${segments.length} OK)');

    // Small delay between requests
    await Future.delayed(const Duration(milliseconds: 100));
  }

  if (segments.isEmpty) {
    onProgress?.call(entries.length, entries.length,
        'ERROR: Could not download any audio. Check internet connection.');
    return;
  }

  onProgress?.call(entries.length, entries.length,
      'Combining ${segments.length} audio segments...');

  // Simply concatenate all audio segments.
  // The TTS API already adjusted the speed of each segment to match subtitle duration.
  // No fake silence needed - just real audio back to back.
  final output = BytesBuilder();
  for (final segment in segments) {
    output.add(segment);
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

  onProgress?.call(entries.length, entries.length,
      'Done! $fileName (${sizeMb.toStringAsFixed(1)} MB)\n'
      'Saved to: ${saveDir.path}');
}
