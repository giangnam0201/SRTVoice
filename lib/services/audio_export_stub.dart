import '../models/subtitle_entry.dart';
import 'tts_service.dart';

/// Stub implementation - should never be called.
Future<void> generatePlatformAudio(
  List<SubtitleEntry> entries,
  TtsService ttsService,
  double speechRate,
  int totalDurationMs,
  Function(int current, int total, String status)? onProgress,
) async {
  throw UnsupportedError('Platform not supported');
}
