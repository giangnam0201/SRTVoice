import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/subtitle_entry.dart';
import '../models/language.dart';
import '../services/srt_parser.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TtsService _ttsService = TtsService();
  List<SubtitleEntry> _subtitles = [];
  List<String> _availableLanguages = [];
  List<Map<String, String>> _availableVoices = [];

  Language _sourceLanguage = supportedLanguages[0]; // English
  Language _targetLanguage = supportedLanguages[0]; // English
  String? _selectedVoiceLanguage;
  Map<String, String>? _selectedVoice;

  bool _isTranslating = false;
  bool _isGenerating = false;
  bool _isSpeaking = false;
  String _statusMessage = '';
  double _progress = 0.0;
  String? _fileName;
  double _speechRate = 0.5;
  double _pitch = 1.0;
  int _currentSpeakingIndex = -1;

  @override
  void initState() {
    super.initState();
    _initializeTts();
  }

  Future<void> _initializeTts() async {
    await _ttsService.initialize();
    final languages = await _ttsService.getLanguages();
    final voices = await _ttsService.getVoices();
    if (mounted) {
      setState(() {
        _availableLanguages = languages;
        _availableVoices = voices;
        if (languages.isNotEmpty) {
          _selectedVoiceLanguage = languages.firstWhere(
            (l) => l.startsWith('en'),
            orElse: () => languages.first,
          );
        }
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String? content;

        if (file.bytes != null) {
          content = utf8.decode(file.bytes!);
        }

        if (content == null || content.isEmpty) {
          _showError('Could not read file');
          return;
        }

        final subtitles = SrtParser.parse(content);

        if (mounted) {
          setState(() {
            _subtitles = subtitles;
            _fileName = file.name;
            _statusMessage = 'Loaded ${subtitles.length} subtitle entries';
          });
        }
      }
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  Future<void> _translateSubtitles() async {
    if (_subtitles.isEmpty) {
      _showError('Please load a subtitle file first');
      return;
    }

    if (_sourceLanguage.code == _targetLanguage.code) {
      _showError('Source and target languages are the same');
      return;
    }

    setState(() {
      _isTranslating = true;
      _progress = 0.0;
      _statusMessage = 'Translating...';
    });

    try {
      await TranslationService.translateSubtitles(
        _subtitles,
        _sourceLanguage.code,
        _targetLanguage.code,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progress = current / total;
              _statusMessage = 'Translating $current/$total...';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _statusMessage = 'Translation complete!';
        });
      }
    } catch (e) {
      _showError('Translation error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
      }
    }
  }

  Future<void> _generateAndSpeak() async {
    if (_subtitles.isEmpty) {
      _showError('Please load a subtitle file first');
      return;
    }

    if (_selectedVoiceLanguage != null) {
      await _ttsService.setLanguage(_selectedVoiceLanguage!);
    }
    if (_selectedVoice != null) {
      await _ttsService.setVoice(_selectedVoice!);
    }
    await _ttsService.setSpeechRate(_speechRate);
    await _ttsService.setPitch(_pitch);

    setState(() {
      _isGenerating = true;
      _isSpeaking = true;
      _statusMessage = 'Speaking subtitles with timing...';
      _currentSpeakingIndex = -1;
    });

    try {
      for (int i = 0; i < _subtitles.length; i++) {
        if (!_isSpeaking) break;

        final entry = _subtitles[i];

        // Calculate wait time to match subtitle timing
        if (i == 0) {
          final waitTime = entry.startTime;
          if (waitTime > Duration.zero) {
            await Future.delayed(waitTime);
          }
        } else {
          final gap = entry.startTime - _subtitles[i - 1].endTime;
          if (gap > Duration.zero) {
            await Future.delayed(gap);
          }
        }

        if (!_isSpeaking) break;

        if (mounted) {
          setState(() {
            _currentSpeakingIndex = i;
            _statusMessage = 'Speaking entry ${i + 1}/${_subtitles.length}';
            _progress = (i + 1) / _subtitles.length;
          });
        }

        await _ttsService.speak(entry.displayText);
      }

      if (mounted) {
        setState(() {
          _statusMessage = 'Playback complete!';
          _currentSpeakingIndex = -1;
        });
      }
    } catch (e) {
      _showError('Error during speech: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _isSpeaking = false;
        });
      }
    }
  }

  void _stopSpeaking() {
    _ttsService.stop();
    setState(() {
      _isSpeaking = false;
      _isGenerating = false;
      _currentSpeakingIndex = -1;
      _statusMessage = 'Stopped';
    });
  }

  void _showError(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SRT Voice'),
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFileSection(),
            const SizedBox(height: 16),
            _buildTranslationSection(),
            const SizedBox(height: 16),
            _buildVoiceSettingsSection(),
            const SizedBox(height: 16),
            _buildControlsSection(),
            const SizedBox(height: 16),
            _buildStatusSection(),
            const SizedBox(height: 16),
            if (_subtitles.isNotEmpty) _buildSubtitlePreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subtitle File',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fileName ?? 'No file selected',
                    style: TextStyle(
                      color: _fileName != null ? null : Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Pick .SRT File'),
                ),
              ],
            ),
            if (_subtitles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '${_subtitles.length} entries loaded',
                  style: const TextStyle(color: Colors.green),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Translation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Using MyMemory Translation API (free)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Language>(
                    value: _sourceLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Source Language',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: supportedLanguages
                        .map((lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(lang.name),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sourceLanguage = value);
                      }
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: DropdownButtonFormField<Language>(
                    value: _targetLanguage,
                    decoration: const InputDecoration(
                      labelText: 'Target Language',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: supportedLanguages
                        .map((lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(lang.name),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _targetLanguage = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isTranslating ? null : _translateSubtitles,
                icon: _isTranslating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.translate),
                label: Text(_isTranslating ? 'Translating...' : 'Translate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voice Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_availableLanguages.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedVoiceLanguage,
                decoration: const InputDecoration(
                  labelText: 'Voice Language',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: _availableLanguages
                    .map((lang) => DropdownMenuItem(
                          value: lang,
                          child: Text(lang),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVoiceLanguage = value);
                    _ttsService.setLanguage(value);
                  }
                },
              ),
            const SizedBox(height: 12),
            if (_availableVoices.isNotEmpty)
              DropdownButtonFormField<Map<String, String>>(
                value: _selectedVoice,
                decoration: const InputDecoration(
                  labelText: 'Voice',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                isExpanded: true,
                items: _availableVoices
                    .map((voice) => DropdownMenuItem(
                          value: voice,
                          child: Text(
                            voice['name'] ?? voice.toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVoice = value);
                    _ttsService.setVoice(value);
                  }
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 60, child: Text('Speed:')),
                Expanded(
                  child: Slider(
                    value: _speechRate,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    label: _speechRate.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() => _speechRate = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(_speechRate.toStringAsFixed(1)),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 60, child: Text('Pitch:')),
                Expanded(
                  child: Slider(
                    value: _pitch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _pitch.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() => _pitch = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(_pitch.toStringAsFixed(1)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Generate Audio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Speaks each subtitle entry at the exact timing specified in the SRT file '
              'using the device\'s text-to-speech engine.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isGenerating || _subtitles.isEmpty)
                        ? null
                        : _generateAndSpeak,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Generate & Play'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (_isSpeaking) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _stopSpeaking,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_statusMessage.isNotEmpty)
              Text(
                _statusMessage,
                style: TextStyle(
                  color: _statusMessage.toLowerCase().contains('error')
                      ? Colors.red
                      : Colors.green,
                ),
              ),
            if (_progress > 0 && _progress < 1.0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Text('${(_progress * 100).toStringAsFixed(0)}%'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitlePreview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subtitle Preview (${_subtitles.length} entries)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: _subtitles.length,
                itemBuilder: (context, index) {
                  final entry = _subtitles[index];
                  final isCurrentlySpeaking = index == _currentSpeakingIndex;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: isCurrentlySpeaking
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: isCurrentlySpeaking
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Text(
                          '${entry.index}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isCurrentlySpeaking ? Colors.white : null,
                          ),
                        ),
                      ),
                      title: Text(
                        entry.displayText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrentlySpeaking
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${SrtParser.formatTimestamp(entry.startTime)} --> ${SrtParser.formatTimestamp(entry.endTime)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
