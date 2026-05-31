import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'tts_api_service.dart';
import 'audio_export_service.dart';

/// Web implementation: Downloads audio in PARALLEL and triggers browser download.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  final language = ttsService.currentLanguage ?? 'en';

  onProgress?.call(0, entries.length, 'Downloading audio (parallel)...');

  // Download in parallel batches of 10
  const batchSize = 10;
  final segments = <int, Uint8List>{};
  int completed = 0;

  for (int batchStart = 0; batchStart < entries.length; batchStart += batchSize) {
    final batchEnd = (batchStart + batchSize).clamp(0, entries.length);

    final futures = <Future<void>>[];
    for (int i = batchStart; i < batchEnd; i++) {
      futures.add(() async {
        final entry = entries[i];
        final text = entry.displayText.trim();
        if (text.isEmpty) return;

        final audioBytes = await TtsApiService.generateWithTiming(
          text,
          language,
          targetDurationMs: entry.duration.inMilliseconds,
        );
        if (audioBytes != null && audioBytes.isNotEmpty) segments[i] = audioBytes;
      }());
    }

    await Future.wait(futures);
    completed = batchEnd;
    onProgress?.call(completed, entries.length, 'Downloaded $completed/${entries.length}');
  }

  if (segments.isEmpty) {
    onProgress?.call(entries.length, entries.length, 'ERROR: Could not download audio.');
    return;
  }

  // Concatenate in order
  final output = BytesBuilder();
  for (int i = 0; i < entries.length; i++) {
    final seg = segments[i];
    if (seg != null) output.add(seg);
  }

  // Trigger browser download
  final bytes = output.toBytes();
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'audio/mpeg'),
  );

  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = 'SRTVoice_output.mp3';
  anchor.style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  web.document.body!.removeChild(anchor);
  web.URL.revokeObjectURL(url);

  final sizeMb = bytes.length / (1024 * 1024);
  onProgress?.call(entries.length, entries.length,
      'Done! MP3 downloaded (${sizeMb.toStringAsFixed(1)} MB)');
}
