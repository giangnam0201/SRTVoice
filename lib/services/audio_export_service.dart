import 'dart:async';
import 'dart:typed_data';
import '../models/subtitle_entry.dart';
import 'tts_service.dart';

import 'audio_export_stub.dart'
    if (dart.library.js_interop) 'audio_export_web.dart'
    if (dart.library.io) 'audio_export_native.dart';

/// Service to generate an audio file (WAV) from subtitle entries
/// with correct timing matching the SRT timestamps.
class AudioExportService {
  final TtsService ttsService;

  AudioExportService({required this.ttsService});

  /// Generate audio from subtitles and trigger download/save.
  /// The voice is sped up or slowed down to fit the subtitle duration.
  Future<void> generateAndExport(
    List<SubtitleEntry> entries, {
    double speechRate = 0.5,
    Function(int current, int total, String status)? onProgress,
  }) async {
    if (entries.isEmpty) return;

    final totalDurationMs = entries.last.endTime.inMilliseconds;

    onProgress?.call(0, entries.length, 'Preparing audio generation...');

    // Generate WAV using platform-specific implementation
    await generatePlatformAudio(
      entries,
      ttsService,
      speechRate,
      totalDurationMs,
      onProgress,
    );
  }
}

/// Generate a WAV file header
Uint8List createWavHeader({
  required int dataSize,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
}) {
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final fileSize = 36 + dataSize;

  final header = ByteData(44);
  // "RIFF"
  header.setUint8(0, 0x52); // R
  header.setUint8(1, 0x49); // I
  header.setUint8(2, 0x46); // F
  header.setUint8(3, 0x46); // F
  // File size - 8
  header.setUint32(4, fileSize, Endian.little);
  // "WAVE"
  header.setUint8(8, 0x57);  // W
  header.setUint8(9, 0x41);  // A
  header.setUint8(10, 0x56); // V
  header.setUint8(11, 0x45); // E
  // "fmt "
  header.setUint8(12, 0x66); // f
  header.setUint8(13, 0x6D); // m
  header.setUint8(14, 0x74); // t
  header.setUint8(15, 0x20); // space
  // Chunk size
  header.setUint32(16, 16, Endian.little);
  // Audio format (PCM = 1)
  header.setUint16(20, 1, Endian.little);
  // Channels
  header.setUint16(22, channels, Endian.little);
  // Sample rate
  header.setUint32(24, sampleRate, Endian.little);
  // Byte rate
  header.setUint32(28, byteRate, Endian.little);
  // Block align
  header.setUint16(32, blockAlign, Endian.little);
  // Bits per sample
  header.setUint16(34, bitsPerSample, Endian.little);
  // "data"
  header.setUint8(36, 0x64); // d
  header.setUint8(37, 0x61); // a
  header.setUint8(38, 0x74); // t
  header.setUint8(39, 0x61); // a
  // Data size
  header.setUint32(40, dataSize, Endian.little);

  return header.buffer.asUint8List();
}

/// Create silence (zeros) for the given duration
Uint8List createSilence(int durationMs, int sampleRate, int channels, int bitsPerSample) {
  final bytesPerSample = bitsPerSample ~/ 8;
  final numSamples = (sampleRate * durationMs / 1000).round();
  final dataSize = numSamples * channels * bytesPerSample;
  return Uint8List(dataSize); // All zeros = silence
}
