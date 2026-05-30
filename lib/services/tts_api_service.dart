import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Free TTS API service using https://tts-api.netlify.app/
/// Supports speed and pitch control, auto language detection.
/// Returns audio bytes (MP3/WAV) for each text input.
class TtsApiService {
  static const String _baseUrl = 'https://tts-api.netlify.app';

  /// Generate audio bytes from text.
  /// [text] - text to speak
  /// [language] - language code (e.g. 'en', 'vi', 'ja', 'auto')
  /// [speed] - speech speed (1.0 = normal, >1 = faster, <1 = slower)
  /// [pitch] - voice pitch (1.0 = normal)
  /// Returns audio bytes or null on failure.
  static Future<Uint8List?> generateAudio(
    String text,
    String language, {
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    if (text.trim().isEmpty) return null;

    // This API has a text length limit, split if needed
    if (text.length > 500) {
      final chunks = _splitText(text, 500);
      final allBytes = BytesBuilder();
      for (final chunk in chunks) {
        final bytes = await _fetch(chunk, language, speed, pitch);
        if (bytes != null) allBytes.add(bytes);
      }
      return allBytes.toBytes().isEmpty ? null : allBytes.toBytes();
    }

    return await _fetch(text, language, speed, pitch);
  }

  /// Generate MP3 with speed adjusted to fit a target duration.
  /// [text] - text to speak
  /// [language] - language code
  /// [targetDurationMs] - how long the audio should be (subtitle duration)
  /// [basePitch] - pitch setting
  static Future<Uint8List?> generateWithTiming(
    String text,
    String language, {
    required int targetDurationMs,
    double basePitch = 1.0,
  }) async {
    if (text.trim().isEmpty) return null;
    if (targetDurationMs <= 0) targetDurationMs = 3000;

    // Estimate: at speed 1.0, roughly 12-15 chars/sec for most languages
    final charCount = text.length;
    final estimatedMsAtSpeed1 = (charCount / 13.0) * 1000;

    // Calculate speed to fit target duration
    // If estimated > target, need to speed up (speed > 1)
    // If estimated < target, need to slow down (speed < 1)
    var speed = estimatedMsAtSpeed1 / targetDurationMs;
    speed = speed.clamp(0.5, 3.0); // API supports wide range

    return await generateAudio(text, language, speed: speed, pitch: basePitch);
  }

  static Future<Uint8List?> _fetch(String text, String lang, double speed, double pitch) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/?text=${Uri.encodeComponent(text)}&lang=$lang&speed=$speed&pitch=$pitch',
      );

      final response = await http.get(uri, headers: {
        'User-Agent': 'SRTVoice/1.0',
      }).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (e) {
      print('TTS API error: $e');
    }
    return null;
  }

  /// Split text into chunks at sentence/word boundaries.
  static List<String> _splitText(String text, int maxLen) {
    final chunks = <String>[];
    // Try splitting at sentence boundaries first
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));

    var current = '';
    for (final sentence in sentences) {
      if (current.isEmpty) {
        current = sentence;
      } else if ('$current $sentence'.length <= maxLen) {
        current = '$current $sentence';
      } else {
        if (current.isNotEmpty) chunks.add(current);
        current = sentence;
      }
    }
    if (current.isNotEmpty) chunks.add(current);

    // If any chunk is still too long, split by words
    final result = <String>[];
    for (final chunk in chunks) {
      if (chunk.length <= maxLen) {
        result.add(chunk);
      } else {
        final words = chunk.split(' ');
        var c = '';
        for (final w in words) {
          if (c.isEmpty) {
            c = w;
          } else if ('$c $w'.length <= maxLen) {
            c = '$c $w';
          } else {
            result.add(c);
            c = w;
          }
        }
        if (c.isNotEmpty) result.add(c);
      }
    }
    return result;
  }
}
