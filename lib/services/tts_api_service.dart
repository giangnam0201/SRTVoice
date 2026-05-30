import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Free TTS API service that generates MP3 audio from text.
/// Uses Google Translate's TTS endpoint - free, no API key, unlimited.
class TtsApiService {
  /// Generate MP3 audio bytes from text using Google Translate TTS.
  /// [text] - the text to speak
  /// [language] - language code (e.g. 'en', 'vi', 'ja')
  /// [slow] - if true, speaks slower
  /// Returns MP3 bytes or null on failure.
  static Future<Uint8List?> generateMp3(
    String text,
    String language, {
    bool slow = false,
  }) async {
    // Google Translate TTS has a ~200 char limit per request
    // Split long text into chunks if needed
    if (text.length > 200) {
      final chunks = _splitText(text, 200);
      final allBytes = BytesBuilder();
      for (final chunk in chunks) {
        final bytes = await _fetchTts(chunk, language, slow);
        if (bytes != null) {
          allBytes.add(bytes);
        }
      }
      return allBytes.toBytes().isEmpty ? null : allBytes.toBytes();
    }

    return await _fetchTts(text, language, slow);
  }

  static Future<Uint8List?> _fetchTts(String text, String lang, bool slow) async {
    final speed = slow ? '0.24' : '0.5';
    
    // Try multiple TTS endpoints for reliability
    final urls = [
      'https://translate.google.com/translate_tts?ie=UTF-8&tl=$lang&client=tw-ob&q=${Uri.encodeComponent(text)}',
      'https://translate.google.com.vn/translate_tts?ie=UTF-8&tl=$lang&client=tw-ob&q=${Uri.encodeComponent(text)}',
    ];

    for (final url in urls) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://translate.google.com/',
          },
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } catch (e) {
        print('TTS API error for url: $e');
        continue;
      }
    }
    return null;
  }

  /// Split text into chunks at word boundaries.
  static List<String> _splitText(String text, int maxLen) {
    final chunks = <String>[];
    final words = text.split(' ');
    var current = '';

    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ('$current $word'.length <= maxLen) {
        current = '$current $word';
      } else {
        chunks.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }
}
