import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'tts_api_service.dart';
import 'audio_export_service.dart';

/// Web implementation: Downloads audio from TTS API and triggers browser download.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  final language = ttsService.currentLanguage ?? 'en';

  onProgress?.call(0, entries.length, 'Downloading audio from TTS API...');

  // Download all segments
  final segments = <Uint8List>[];
  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final text = entry.displayText.trim();
    if (text.isEmpty) continue;

    final audioBytes = await TtsApiService.generateWithTiming(
      text,
      language,
      targetDurationMs: entry.duration.inMilliseconds,
    );

    if (audioBytes != null && audioBytes.isNotEmpty) segments.add(audioBytes);

    onProgress?.call(i + 1, entries.length, 'Downloaded ${i + 1}/${entries.length}');
    await Future.delayed(const Duration(milliseconds: 100));
  }

  if (segments.isEmpty) {
    onProgress?.call(entries.length, entries.length, 'ERROR: Could not download audio.');
    return;
  }

  // Concatenate all segments directly
  final output = BytesBuilder();
  for (final seg in segments) {
    output.add(seg);
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
