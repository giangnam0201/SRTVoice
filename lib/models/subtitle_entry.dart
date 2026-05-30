class SubtitleEntry {
  final int index;
  final Duration startTime;
  final Duration endTime;
  final String text;
  String? translatedText;

  SubtitleEntry({
    required this.index,
    required this.startTime,
    required this.endTime,
    required this.text,
    this.translatedText,
  });

  Duration get duration => endTime - startTime;

  String get displayText => translatedText ?? text;

  @override
  String toString() {
    return 'SubtitleEntry(index: $index, start: $startTime, end: $endTime, text: $text)';
  }
}
