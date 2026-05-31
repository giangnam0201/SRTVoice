import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'tts_api_service.dart';
import 'audio_export_service.dart';

/// Native implementation using the free TTS API.
/// Downloads audio for each subtitle in PARALLEL batches for speed,
/// then concatenates all segments into one MP3 file.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  final language = ttsService.currentLanguage ?? 'en';

  onProgress?.call(0, entries.length, 'Downloading audio (parallel)...');

  // Download audio in PARALLEL BATCHES of 5 for speed
  const batchSize = 5;
  final segments = <int, Uint8List>{};
  int completed = 0;

  for (int batchStart = 0; batchStart < entries.length; batchStart += batchSize) {
    final batchEnd = (batchStart + batchSize).clamp(0, entries.length);

    // Launch all downloads in this batch in parallel
    final futures = <Future<void>>[];
    for (int i = batchStart; i < batchEnd; i++) {
      futures.add(() async {
        final entry = entries[i];
        final text = entry.displayText.trim();
        if (text.isEmpty) return;

        final targetMs = entry.duration.inMilliseconds;
        final audioBytes = await TtsApiService.generateWithTiming(
          text,
          language,
          targetDurationMs: targetMs,
        );

        if (audioBytes != null && audioBytes.isNotEmpty) {
          segments[i] = audioBytes;
        }
      }());
    }

    // Wait for entire batch
    await Future.wait(futures);

    completed = batchEnd;
    onProgress?.call(completed, entries.length,
        'Downloaded $completed/${entries.length} (${segments.length} OK)');
  }

  if (segments.isEmpty) {
    onProgress?.call(entries.length, entries.length,
        'ERROR: Could not download any audio. Check internet connection.');
    return;
  }

  onProgress?.call(entries.length, entries.length,
      'Combining ${segments.length} segments...');

  // Concatenate segments in ORDER
  final output = BytesBuilder();
  for (int i = 0; i < entries.length; i++) {
    final seg = segments[i];
    if (seg != null) output.add(seg);
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
