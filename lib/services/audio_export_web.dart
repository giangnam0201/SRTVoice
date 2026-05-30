import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'tts_api_service.dart';
import 'audio_export_service.dart';

/// Web implementation: Downloads MP3 from TTS API and triggers browser download.
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
  final segments = <int, Uint8List>{};
  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry.displayText.trim().isEmpty) continue;

    final mp3 = await TtsApiService.generateMp3(entry.displayText, language);
    if (mp3 != null && mp3.isNotEmpty) segments[i] = mp3;

    onProgress?.call(i + 1, entries.length, 'Downloaded ${i + 1}/${entries.length}');
    await Future.delayed(const Duration(milliseconds: 100));
  }

  if (segments.isEmpty) {
    onProgress?.call(entries.length, entries.length, 'ERROR: Could not download audio.');
    return;
  }

  // Combine into one MP3
  final output = BytesBuilder();
  var posMs = 0;

  for (int i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final startMs = entry.startTime.inMilliseconds;

    if (startMs > posMs) {
      output.add(_mp3Silence(startMs - posMs));
      posMs = startMs;
    }

    final seg = segments[i];
    if (seg != null) {
      output.add(seg);
      posMs += (seg.length / 4000 * 1000).round();
    }

    final endMs = entry.endTime.inMilliseconds;
    if (posMs < endMs) {
      output.add(_mp3Silence(endMs - posMs));
      posMs = endMs;
    }
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

Uint8List _mp3Silence(int ms) {
  const frameSize = 417;
  const frameDur = 26;
  final frames = (ms / frameDur).ceil();
  final frame = Uint8List(frameSize);
  frame[0] = 0xFF; frame[1] = 0xFB; frame[2] = 0x90; frame[3] = 0x00;
  final out = BytesBuilder();
  for (int i = 0; i < frames; i++) out.add(frame);
  return out.toBytes();
}
