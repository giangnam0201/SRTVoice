import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';
import 'audio_export_service.dart';

/// Native implementation.
/// Strategy:
/// 1. First tries synthesizeToFile with a fresh TTS instance (works on many devices)
/// 2. If that fails, uses speak() with timing (same as Preview - plays through speaker)
///    and tells the user the audio was played but couldn't be saved to file.
///
/// synthesizeToFile is attempted silently - if it works, great, file is saved.
/// If not, speak() mode kicks in automatically.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  onProgress?.call(0, entries.length, 'Attempting file generation...');

  // Try synthesizeToFile with a dedicated instance
  final success = await _trySynthesizeToFile(entries, speechRate, totalDurationMs, onProgress);

  if (!success) {
    // Fall back to speak mode
    onProgress?.call(0, entries.length, 'File export unavailable. Playing with correct timing...');
    await _speakWithTiming(entries, ttsService, speechRate, onProgress);
  }
}

/// Try to generate audio file using synthesizeToFile.
/// Returns true if successful.
Future<bool> _trySynthesizeToFile(
  List<SubtitleEntry> entries,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  final tts = FlutterTts();
  await tts.setVolume(1.0);
  await tts.setPitch(1.0);
  await tts.setSpeechRate(speechRate);

  // Use app documents directory (most reliable for TTS write access)
  final docsDir = await getApplicationDocumentsDirectory();
  final segDir = Directory('${docsDir.path}/tts_segments');
  if (await segDir.exists()) await segDir.delete(recursive: true);
  await segDir.create(recursive: true);

  // Test with first entry
  final testCompleter = Completer<void>();
  tts.setCompletionHandler(() {
    if (!testCompleter.isCompleted) testCompleter.complete();
  });

  final testPath = '${segDir.path}/t.wav';
  final r = await tts.synthesizeToFile(entries.first.displayText, testPath);

  if (r == 1) {
    try { await testCompleter.future.timeout(const Duration(seconds: 10)); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 800));
  }

  final tf = File(testPath);
  if (!await tf.exists() || await tf.length() <= 100) {
    // Doesn't work on this device
    await tts.stop();
    try { await segDir.delete(recursive: true); } catch (_) {}
    return false;
  }

  // It works! Generate all segments
  onProgress?.call(1, entries.length, 'Generating segments (1/${entries.length})...');
  final segments = <int, File>{0: tf};

  for (int i = 1; i < entries.length; i++) {
    final entry = entries[i];
    final path = '${segDir.path}/s$i.wav';

    final rate = _calcRate(entry.displayText, entry.duration.inMilliseconds, speechRate);
    await tts.setSpeechRate(rate);

    final c = Completer<void>();
    tts.setCompletionHandler(() { if (!c.isCompleted) c.complete(); });

    await tts.synthesizeToFile(entry.displayText, path);
    try { await c.future.timeout(const Duration(seconds: 10)); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 400));

    final f = File(path);
    if (await f.exists() && await f.length() > 100) {
      segments[i] = f;
    }

    onProgress?.call(i + 1, entries.length, 'Generating segments (${i + 1}/${entries.length})...');
  }

  // Also regenerate first entry with correct rate
  final firstRate = _calcRate(entries.first.displayText, entries.first.duration.inMilliseconds, speechRate);
  if ((firstRate - speechRate).abs() > 0.05) {
    await tts.setSpeechRate(firstRate);
    final fc = Completer<void>();
    tts.setCompletionHandler(() { if (!fc.isCompleted) fc.complete(); });
    final fp = '${segDir.path}/s0r.wav';
    await tts.synthesizeToFile(entries.first.displayText, fp);
    try { await fc.future.timeout(const Duration(seconds: 10)); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 400));
    final ff = File(fp);
    if (await ff.exists() && await ff.length() > 100) segments[0] = ff;
  }

  await tts.stop();

  if (segments.isEmpty) {
    try { await segDir.delete(recursive: true); } catch (_) {}
    return false;
  }

  // Combine segments into final WAV
  onProgress?.call(entries.length, entries.length, 'Combining ${segments.length} segments...');

  // Read format from first segment
  int sr = 22050, ch = 1, bps = 16;
  final fb = await segments.values.first.readAsBytes();
  if (fb.length > 44 && fb[0] == 0x52) {
    final h = ByteData.sublistView(fb);
    ch = h.getUint16(22, Endian.little);
    sr = h.getUint32(24, Endian.little);
    bps = h.getUint16(34, Endian.little);
  }

  final bpms = (sr * ch * (bps ~/ 8)) / 1000;
  final ba = ch * (bps ~/ 8);
  final audio = BytesBuilder();
  var posMs = 0;

  for (int i = 0; i < entries.length; i++) {
    final e = entries[i];
    final startMs = e.startTime.inMilliseconds;

    if (startMs > posMs) {
      final sb = ((startMs - posMs) * bpms).round();
      final a = sb - (sb % ba);
      if (a > 0) audio.add(Uint8List(a));
      posMs = startMs;
    }

    final sf = segments[i];
    if (sf != null) {
      final bytes = await sf.readAsBytes();
      final doff = _findData(bytes);
      if (doff < bytes.length) {
        final aud = bytes.sublist(doff);
        audio.add(aud);
        posMs += (aud.length / bpms).round();
      }
    }

    final endMs = e.endTime.inMilliseconds;
    if (posMs < endMs) {
      final pb = ((endMs - posMs) * bpms).round();
      final a = pb - (pb % ba);
      if (a > 0) audio.add(Uint8List(a));
      posMs = endMs;
    }
  }

  final raw = audio.toBytes();
  final hdr = createWavHeader(dataSize: raw.length, sampleRate: sr, channels: ch, bitsPerSample: bps);
  final wav = BytesBuilder()..add(hdr)..add(raw);
  final wavBytes = wav.toBytes();

  // Save to Downloads
  Directory saveDir;
  if (Platform.isAndroid) {
    saveDir = Directory('/storage/emulated/0/Download');
    if (!await saveDir.exists()) {
      saveDir = await getExternalStorageDirectory() ?? docsDir;
    }
  } else {
    saveDir = docsDir;
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final fn = 'SRTVoice_$timestamp.wav';
  await File('${saveDir.path}/$fn').writeAsBytes(wavBytes);

  // Cleanup
  try { await segDir.delete(recursive: true); } catch (_) {}

  final mb = wavBytes.length / (1024 * 1024);
  final sec = posMs / 1000;
  onProgress?.call(entries.length, entries.length,
      'Done! $fn (${mb.toStringAsFixed(1)} MB, ${sec.toStringAsFixed(0)}s)\nSaved to: ${saveDir.path}');
  return true;
}

/// Speak with correct timing (same as Preview).
Future<void> _speakWithTiming(
  List<SubtitleEntry> entries, TtsService tts, double baseRate,
  Function(int, int, String)? onProgress) async {
  final start = DateTime.now();
  for (int i = 0; i < entries.length; i++) {
    final e = entries[i];
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    final wait = e.startTime.inMilliseconds - elapsed;
    if (wait > 0) await Future.delayed(Duration(milliseconds: wait));

    final rate = _calcRate(e.displayText, e.duration.inMilliseconds, baseRate);
    await tts.setSpeechRate(rate);
    onProgress?.call(i + 1, entries.length, 'Speaking ${i + 1}/${entries.length} (rate ${rate.toStringAsFixed(2)})');
    await tts.speak(e.displayText);
  }
  onProgress?.call(entries.length, entries.length,
      'Playback complete!\n\nNote: File export is not available on this device.\n'
      'The TTS engine does not support saving to file.\n'
      'Audio was played through the speaker with correct timing.');
}

int _findData(Uint8List b) {
  for (int i = 12; i < b.length - 8; i++) {
    if (b[i] == 0x64 && b[i+1] == 0x61 && b[i+2] == 0x74 && b[i+3] == 0x61) return i + 8;
  }
  return 44;
}

double _calcRate(String text, int ms, double base) {
  if (ms <= 200) return base;
  final est = (text.length / (base * 14.0)) * 1000;
  return (base * (est / ms)).clamp(0.25, 2.5);
}
