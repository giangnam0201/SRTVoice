# SRT Voice

Convert subtitle files (.srt) to speech audio with correct timing, translation support, and multi-platform deployment.

## Features

- **Load .SRT Files**: Pick any subtitle file and parse all entries with timestamps
- **Translation**: Translate subtitles between 30+ languages using the free MyMemory Translation API
- **Text-to-Speech**: Generate speech from subtitles using the device's TTS engine
- **Correct Timing**: Speech is generated with exact timing matching the subtitle timestamps
- **Voice Selection**: Choose from available voices and languages on your device
- **Adjustable Settings**: Control speech rate and pitch
- **Multi-Platform**: Works on Web, Android (APK), and Windows

## How It Works

1. Pick a .srt subtitle file
2. (Optional) Translate the subtitles to another language
3. Select voice language and voice type
4. Adjust speed and pitch settings
5. Click "Generate & Play" to hear the subtitles spoken with correct timing

## Supported Platforms

- **Web**: Works in any modern browser with Web Speech API support
- **Android**: Native TTS engine support
- **Windows**: Native TTS engine support

## Building

```bash
# Get dependencies
flutter pub get

# Build for web
flutter build web --release

# Build for Android
flutter build apk --release

# Build for Windows
flutter build windows --release
```

## Translation

Uses the free MyMemory Translation API to translate between 30+ languages including:
English, Spanish, French, German, Italian, Portuguese, Russian, Japanese, Korean, Chinese, Arabic, Hindi, Vietnamese, Thai, Dutch, Polish, Swedish, Danish, Finnish, Norwegian, Turkish, Indonesian, Malay, Czech, Hungarian, Romanian, Ukrainian, Greek, Hebrew, Bulgarian.

## License

MIT License
