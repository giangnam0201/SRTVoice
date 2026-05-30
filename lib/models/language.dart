class Language {
  final String code;
  final String name;

  const Language({required this.code, required this.name});

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Language && runtimeType == other.runtimeType && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

const List<Language> supportedLanguages = [
  Language(code: 'en', name: 'English'),
  Language(code: 'es', name: 'Spanish'),
  Language(code: 'fr', name: 'French'),
  Language(code: 'de', name: 'German'),
  Language(code: 'it', name: 'Italian'),
  Language(code: 'pt', name: 'Portuguese'),
  Language(code: 'ru', name: 'Russian'),
  Language(code: 'ja', name: 'Japanese'),
  Language(code: 'ko', name: 'Korean'),
  Language(code: 'zh', name: 'Chinese'),
  Language(code: 'ar', name: 'Arabic'),
  Language(code: 'hi', name: 'Hindi'),
  Language(code: 'vi', name: 'Vietnamese'),
  Language(code: 'th', name: 'Thai'),
  Language(code: 'nl', name: 'Dutch'),
  Language(code: 'pl', name: 'Polish'),
  Language(code: 'sv', name: 'Swedish'),
  Language(code: 'da', name: 'Danish'),
  Language(code: 'fi', name: 'Finnish'),
  Language(code: 'no', name: 'Norwegian'),
  Language(code: 'tr', name: 'Turkish'),
  Language(code: 'id', name: 'Indonesian'),
  Language(code: 'ms', name: 'Malay'),
  Language(code: 'cs', name: 'Czech'),
  Language(code: 'hu', name: 'Hungarian'),
  Language(code: 'ro', name: 'Romanian'),
  Language(code: 'uk', name: 'Ukrainian'),
  Language(code: 'el', name: 'Greek'),
  Language(code: 'he', name: 'Hebrew'),
  Language(code: 'bg', name: 'Bulgarian'),
];
