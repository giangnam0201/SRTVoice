import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/subtitle_entry.dart';

class TranslationService {
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
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final translatedText = data['responseData']?['translatedText'];
        // Check if it's actually translated (not an error message)
        if (translatedText != null &&
            translatedText.toString().isNotEmpty &&
            !translatedText.toString().contains('MYMEMORY WARNING') &&
            translatedText.toString() != text) {
          return translatedText.toString();
        }
      } else if (response.statusCode == 429) {
        // Rate limited - wait and retry once
        await Future.delayed(const Duration(seconds: 2));
        final retry = await http.get(uri).timeout(const Duration(seconds: 15));
        if (retry.statusCode == 200) {
          final data = json.decode(retry.body);
          final translatedText = data['responseData']?['translatedText'];
          if (translatedText != null &&
              translatedText.toString().isNotEmpty &&
              !translatedText.toString().contains('MYMEMORY WARNING')) {
            return translatedText.toString();
          }
        }
      }
    } catch (e) {
      print('Translation error: $e');
    }
    return text;
  }

  /// Translate all subtitle entries using parallel batches.
  /// Uses batch size of 3 to avoid MyMemory rate limiting.
  static Future<List<SubtitleEntry>> translateSubtitles(
    List<SubtitleEntry> entries,
    String sourceLanguage,
    String targetLanguage, {
    Function(int current, int total)? onProgress,
  }) async {
    const batchSize = 3; // MyMemory rate limits aggressively, keep it small
    int completed = 0;
    int translated = 0;

    for (int batchStart = 0; batchStart < entries.length; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize).clamp(0, entries.length);

      final futures = <Future<void>>[];
      for (int i = batchStart; i < batchEnd; i++) {
        futures.add(() async {
          final result = await translate(
            entries[i].text,
            sourceLanguage,
            targetLanguage,
          );
          if (result != entries[i].text) {
            entries[i].translatedText = result;
            translated++;
          }
        }());
      }

      await Future.wait(futures);
      completed = batchEnd;
      onProgress?.call(completed, entries.length);

      // Small delay between batches to avoid rate limiting
      if (batchEnd < entries.length) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    return entries;
  }
}
