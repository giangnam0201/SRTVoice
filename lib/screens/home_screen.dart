import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/subtitle_entry.dart';
import '../models/language.dart';
import '../services/srt_parser.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
import '../services/audio_export_service.dart';

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
            _statusMessage = 'Loaded ${subtitles.length} subtitle entries from ${file.name}';
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
          _statusMessage = 'Translation complete! All ${_subtitles.length} entries translated.';
          _progress = 0.0;
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

  Future<void> _generateMp3() async {
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
      _progress = 0.0;
      _statusMessage = 'Generating audio with correct timing...';
      _currentSpeakingIndex = -1;
    });

    try {
      // Use AudioExportService to generate a WAV with correct timing
      final exportService = AudioExportService(ttsService: _ttsService);
      
      await exportService.generateAndExport(
        _subtitles,
        speechRate: _speechRate,
        onProgress: (current, total, status) {
          if (mounted) {
            setState(() {
              _currentSpeakingIndex = current - 1;
              _progress = current / total;
              _statusMessage = status;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _statusMessage = 'MP3 generation complete! File saved/downloaded.';
          _currentSpeakingIndex = -1;
          _progress = 0.0;
        });
      }
    } catch (e) {
      _showError('Error generating audio: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _isSpeaking = false;
        });
      }
    }
  }

  Future<void> _previewSpeak() async {
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
      _isSpeaking = true;
      _statusMessage = 'Preview: Speaking with subtitle timing...';
      _currentSpeakingIndex = -1;
    });

    try {
      for (int i = 0; i < _subtitles.length; i++) {
        if (!_isSpeaking) break;

        final entry = _subtitles[i];

        // Wait until start time
        if (i == 0) {
          if (entry.startTime > Duration.zero) {
            await Future.delayed(entry.startTime);
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
            _statusMessage = 'Speaking ${i + 1}/${_subtitles.length}: "${entry.displayText}"';
            _progress = (i + 1) / _subtitles.length;
          });
        }

        await _ttsService.speak(entry.displayText);
      }

      if (mounted) {
        setState(() {
          _statusMessage = 'Preview complete!';
          _currentSpeakingIndex = -1;
          _progress = 0.0;
        });
      }
    } catch (e) {
      _showError('Error during preview: $e');
    } finally {
      if (mounted) {
        setState(() {
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
      _progress = 0.0;
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
        title: const Text('SRT Voice - Subtitle to MP3'),
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
            Row(
              children: [
                const Icon(Icons.subtitles, size: 24),
                const SizedBox(width: 8),
                const Text(
                  '1. Load Subtitle File (.SRT)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _fileName ?? 'No file selected',
                      style: TextStyle(
                        color: _fileName != null ? null : Colors.grey,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Pick .SRT'),
                ),
              ],
            ),
            if (_subtitles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '${_subtitles.length} entries loaded | Total duration: ${SrtParser.formatTimestamp(_subtitles.last.endTime)}',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
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
            Row(
              children: [
                const Icon(Icons.translate, size: 24),
                const SizedBox(width: 8),
                const Text(
                  '2. Translation (Optional)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Select what language your SRT file is in, and what language you want it translated to.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Language>(
                    value: _sourceLanguage,
                    decoration: const InputDecoration(
                      labelText: 'SRT File Language',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    isExpanded: true,
                    items: supportedLanguages
                        .map((lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(lang.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _sourceLanguage = value);
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
                      labelText: 'Translate To',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    isExpanded: true,
                    items: supportedLanguages
                        .map((lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(lang.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _targetLanguage = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isTranslating || _subtitles.isEmpty) ? null : _translateSubtitles,
                icon: _isTranslating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.translate),
                label: Text(_isTranslating ? 'Translating...' : 'Translate Subtitles'),
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
            Row(
              children: [
                const Icon(Icons.record_voice_over, size: 24),
                const SizedBox(width: 8),
                const Text(
                  '3. Choose Voice',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Select a voice language and specific voice from the list below.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_availableLanguages.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedVoiceLanguage,
                decoration: const InputDecoration(
                  labelText: 'Voice Language',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                isExpanded: true,
                items: _availableLanguages
                    .map((lang) => DropdownMenuItem(value: lang, child: Text(lang)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVoiceLanguage = value);
                    _ttsService.setLanguage(value);
                  }
                },
              )
            else
              const Text('Loading voices...', style: TextStyle(color: Colors.orange)),
            const SizedBox(height: 12),
            if (_availableVoices.isNotEmpty)
              DropdownButtonFormField<Map<String, String>>(
                value: _selectedVoice,
                decoration: const InputDecoration(
                  labelText: 'Select Voice',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                isExpanded: true,
                items: _availableVoices.map((voice) {
                  final name = voice['name'] ?? voice['locale'] ?? voice.toString();
                  final locale = voice['locale'] ?? '';
                  return DropdownMenuItem(
                    value: voice,
                    child: Text('$name ($locale)', overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVoice = value);
                    _ttsService.setVoice(value);
                  }
                },
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 80, child: Text('Speed:', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(
                  child: Slider(
                    value: _speechRate,
                    min: 0.1,
                    max: 1.0,
                    divisions: 18,
                    label: '${(_speechRate * 100).round()}%',
                    onChanged: (value) => setState(() => _speechRate = value),
                  ),
                ),
                SizedBox(width: 45, child: Text('${(_speechRate * 100).round()}%')),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 80, child: Text('Pitch:', style: TextStyle(fontWeight: FontWeight.w500))),
                Expanded(
                  child: Slider(
                    value: _pitch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _pitch.toStringAsFixed(1),
                    onChanged: (value) => setState(() => _pitch = value),
                  ),
                ),
                SizedBox(width: 45, child: Text(_pitch.toStringAsFixed(1))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsSection() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.audiotrack, size: 24),
                const SizedBox(width: 8),
                const Text(
                  '4. Generate MP3',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Generates an MP3/WAV file where each subtitle is spoken at the EXACT timing from the SRT file. '
              'The voice speed is adjusted to fit each subtitle\'s duration perfectly.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_isGenerating || _isSpeaking || _subtitles.isEmpty)
                        ? null
                        : _generateMp3,
                    icon: const Icon(Icons.download),
                    label: const Text('Generate & Download MP3'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isGenerating || _isSpeaking || _subtitles.isEmpty)
                        ? null
                        : _previewSpeak,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Preview'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            if (_isSpeaking || _isGenerating) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _stopSpeaking,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    if (_statusMessage.isEmpty && _progress == 0) return const SizedBox.shrink();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _statusMessage.toLowerCase().contains('error')
                      ? Icons.error
                      : _statusMessage.toLowerCase().contains('complete')
                          ? Icons.check_circle
                          : Icons.info,
                  color: _statusMessage.toLowerCase().contains('error')
                      ? Colors.red
                      : _statusMessage.toLowerCase().contains('complete')
                          ? Colors.green
                          : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: _statusMessage.toLowerCase().contains('error')
                          ? Colors.red
                          : null,
                    ),
                  ),
                ),
              ],
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
                          fontWeight: isCurrentlySpeaking ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${SrtParser.formatTimestamp(entry.startTime)} --> ${SrtParser.formatTimestamp(entry.endTime)} (${entry.duration.inMilliseconds}ms)',
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
