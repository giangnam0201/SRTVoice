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
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
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
    return text;
  }

  /// Translate all subtitle entries using PARALLEL batches for speed.
  /// Processes 5 entries at a time concurrently.
  static Future<List<SubtitleEntry>> translateSubtitles(
    List<SubtitleEntry> entries,
    String sourceLanguage,
    String targetLanguage, {
    Function(int current, int total)? onProgress,
  }) async {
    const batchSize = 5; // 5 parallel requests at a time
    int completed = 0;

    for (int batchStart = 0; batchStart < entries.length; batchStart += batchSize) {
      final batchEnd = (batchStart + batchSize).clamp(0, entries.length);

      // Launch all translations in this batch in parallel
      final futures = <Future<void>>[];
      for (int i = batchStart; i < batchEnd; i++) {
        futures.add(() async {
          final translated = await translate(
            entries[i].text,
            sourceLanguage,
            targetLanguage,
          );
          entries[i].translatedText = translated;
        }());
      }

      // Wait for the entire batch to finish
      await Future.wait(futures);

      completed = batchEnd;
      onProgress?.call(completed, entries.length);
    }

    return entries;
  }
}
