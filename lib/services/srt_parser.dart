import '../models/subtitle_entry.dart';

class SrtParser {
  /// Parse an SRT file content into a list of SubtitleEntry objects.
  static List<SubtitleEntry> parse(String content) {
    final List<SubtitleEntry> entries = [];

    // Normalize line endings
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Split by double newline to get blocks
    final blocks = content.split(RegExp(r'\n\n+'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;

      // First line is the index
      final index = int.tryParse(lines[0].trim());
      if (index == null) continue;

      // Second line is the timestamp
      final timeLine = lines[1].trim();
      final timeParts = timeLine.split(' --> ');
      if (timeParts.length != 2) continue;

      final startTime = _parseTimestamp(timeParts[0].trim());
      final endTime = _parseTimestamp(timeParts[1].trim());

      if (startTime == null || endTime == null) continue;

      // Remaining lines are the subtitle text
      final text = lines.sublist(2).join('\n').trim();
      if (text.isEmpty) continue;

      entries.add(SubtitleEntry(
        index: index,
        startTime: startTime,
        endTime: endTime,
        text: text,
      ));
    }

    return entries;
  }

  /// Parse a timestamp string (HH:MM:SS,mmm) into a Duration.
  static Duration? _parseTimestamp(String timestamp) {
    // Format: HH:MM:SS,mmm or HH:MM:SS.mmm
    final regex = RegExp(r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})');
    final match = regex.firstMatch(timestamp);

    if (match == null) return null;

    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final milliseconds = int.parse(match.group(4)!);

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// Format a Duration back to SRT timestamp format.
  static String formatTimestamp(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final milliseconds = (duration.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds,$milliseconds';
  }
}
