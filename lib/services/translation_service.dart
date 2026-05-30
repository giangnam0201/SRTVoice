import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/subtitle_entry.dart';

class TranslationService {
  /// Translate text using the MyMemory Translation API (free).
  /// [sourceLanguage] and [targetLanguage] should be language codes like 'en', 'es', etc.
  static Future<String> translate(
    String text,
    String sourceLanguage,
    String targetLanguage,
  ) async {
    if (sourceLanguage == targetLanguage) return text;
    if (text.trim().isEmpty) return text;

    final langPair = '$sourceLanguage|$targetLanguage';
    final uri = Uri.parse(
      'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=${Uri.encodeComponent(langPair)}',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final translatedText = data['responseData']?['translatedText'];
        if (translatedText != null && translatedText.toString().isNotEmpty) {
          return translatedText.toString();
        }
      }
    } catch (e) {
      print('Translation error: $e');
    }

    // Return original text if translation fails
    return text;
  }

  /// Translate all subtitle entries.
  static Future<List<SubtitleEntry>> translateSubtitles(
    List<SubtitleEntry> entries,
    String sourceLanguage,
    String targetLanguage, {
    Function(int current, int total)? onProgress,
  }) async {
    for (int i = 0; i < entries.length; i++) {
      final translated = await translate(
        entries[i].text,
        sourceLanguage,
        targetLanguage,
      );
      entries[i].translatedText = translated;

      if (onProgress != null) {
        onProgress(i + 1, entries.length);
      }

      // Small delay to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return entries;
  }
}
