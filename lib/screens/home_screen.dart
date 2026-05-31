import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/subtitle_entry.dart';
import '../models/language.dart';
import '../services/srt_parser.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
import '../services/audio_export_service.dart';
import '../services/srt_export_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TtsService _ttsService = TtsService();
  List<SubtitleEntry> _subtitles = [];
  List<String> _availableLanguages = [];
  List<Map<String, String>> _allVoices = [];
  List<Map<String, String>> _filteredVoices = [];

  Language _sourceLanguage = supportedLanguages[0];
  Language _targetLanguage = supportedLanguages[0];
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
    // Set default language
    await _ttsService.setLanguage(_targetLanguage.code);
    final languages = await _ttsService.getLanguages();
    final voices = await _ttsService.getVoices();
    if (mounted) {
      setState(() {
        _availableLanguages = languages;
        _allVoices = voices;
        _filterVoices();
      });
    }
  }

  void _filterVoices() {
    _filteredVoices = _ttsService.filterVoicesByLanguage(_allVoices, _targetLanguage.code);
    if (_selectedVoice != null && !_filteredVoices.contains(_selectedVoice)) {
      _selectedVoice = _filteredVoices.isNotEmpty ? _filteredVoices.first : null;
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
      _showError('Load a subtitle file first');
      return;
    }
    if (_sourceLanguage.code == _targetLanguage.code) {
      _showError('Source and target languages are the same');
      return;
    }
    setState(() { _isTranslating = true; _progress = 0; _statusMessage = 'Translating...'; });
    try {
      await TranslationService.translateSubtitles(
        _subtitles, _sourceLanguage.code, _targetLanguage.code,
        onProgress: (current, total) {
          if (mounted) setState(() { _progress = current / total; _statusMessage = 'Translating $current/$total...'; });
        },
      );
      if (mounted) setState(() { _statusMessage = 'Translation complete!'; _progress = 0; });
    } catch (e) {
      _showError('Translation error: $e');
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  Future<void> _exportTranslatedSrt() async {
    if (_subtitles.isEmpty) return;
    final srtContent = SrtParser.toSrt(_subtitles);
    final result = await SrtExportHelper.export(srtContent);
    if (mounted) setState(() => _statusMessage = result);
  }

  Future<void> _generateAudio() async {
    if (_subtitles.isEmpty) { _showError('Load a subtitle file first'); return; }

    // Set language for the TTS API
    await _ttsService.setLanguage(_targetLanguage.code);
    await _ttsService.setPitch(_pitch);

    setState(() { _isGenerating = true; _isSpeaking = true; _progress = 0; _statusMessage = 'Generating...'; _currentSpeakingIndex = -1; });

    try {
      final exportService = AudioExportService(ttsService: _ttsService);
      await exportService.generateAndExport(
        _subtitles,
        speechRate: _speechRate,
        onProgress: (current, total, status) {
          if (mounted) setState(() { _currentSpeakingIndex = current - 1; _progress = current / total; _statusMessage = status; });
        },
      );
      if (mounted) setState(() { _currentSpeakingIndex = -1; _progress = 0; });
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() { _isGenerating = false; _isSpeaking = false; });
    }
  }

  Future<void> _previewSpeak() async {
    if (_subtitles.isEmpty) { _showError('Load a subtitle file first'); return; }
    await _ttsService.setLanguage(_targetLanguage.code);
    if (_selectedVoice != null) await _ttsService.setVoice(_selectedVoice!);
    await _ttsService.setPitch(_pitch);

    setState(() { _isSpeaking = true; _progress = 0; _statusMessage = 'Preview: speaking with timing...'; _currentSpeakingIndex = -1; });

    try {
      final startTime = DateTime.now();
      for (int i = 0; i < _subtitles.length; i++) {
        if (!_isSpeaking) break;
        final entry = _subtitles[i];

        // Wait until correct start time
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        final waitMs = entry.startTime.inMilliseconds - elapsed;
        if (waitMs > 0) await Future.delayed(Duration(milliseconds: waitMs));
        if (!_isSpeaking) break;

        // Adjust rate per sentence
        final entryDurationMs = entry.duration.inMilliseconds;
        final charCount = entry.displayText.length;
        final charsPerSec = _speechRate * 14.0;
        final estimatedMs = (charCount / charsPerSec) * 1000;
        var rate = _speechRate * (estimatedMs / (entryDurationMs > 200 ? entryDurationMs : 1000));
        rate = rate.clamp(0.25, 2.5);
        await _ttsService.setSpeechRate(rate);

        if (mounted) setState(() { _currentSpeakingIndex = i; _progress = (i + 1) / _subtitles.length; _statusMessage = 'Preview ${i + 1}/${_subtitles.length} (rate: ${rate.toStringAsFixed(2)})'; });

        await _ttsService.speak(entry.displayText);
      }
      if (mounted) setState(() { _statusMessage = 'Preview complete!'; _currentSpeakingIndex = -1; _progress = 0; });
    } catch (e) {
      _showError('Preview error: $e');
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  void _stopSpeaking() {
    _ttsService.stop();
    setState(() { _isSpeaking = false; _isGenerating = false; _currentSpeakingIndex = -1; _statusMessage = 'Stopped'; _progress = 0; });
  }

  void _showError(String msg) {
    if (mounted) {
      setState(() => _statusMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  @override
  void dispose() { _ttsService.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SRT Voice - Subtitle to Audio'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildFileSection(),
          const SizedBox(height: 16),
          _buildTranslationSection(),
          const SizedBox(height: 16),
          _buildVoiceSettingsSection(),
          const SizedBox(height: 16),
          _buildControlsSection(),
          const SizedBox(height: 16),
          if (_statusMessage.isNotEmpty) _buildStatusSection(),
          const SizedBox(height: 16),
          if (_subtitles.isNotEmpty) _buildSubtitlePreview(),
        ]),
      ),
    );
  }

  Widget _buildFileSection() {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('1. Load .SRT File', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text(_fileName ?? 'No file selected', overflow: TextOverflow.ellipsis, style: TextStyle(color: _fileName != null ? null : Colors.grey))),
        const SizedBox(width: 12),
        ElevatedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.file_upload), label: const Text('Pick .SRT')),
      ]),
      if (_subtitles.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
        child: Text('${_subtitles.length} entries | Duration: ${SrtParser.formatTimestamp(_subtitles.last.endTime)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500))),
    ])));
  }

  Widget _buildTranslationSection() {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('2. Translation (Optional)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text('What language is your SRT file? What language do you want?', style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: DropdownButtonFormField<Language>(value: _sourceLanguage, isExpanded: true,
          decoration: const InputDecoration(labelText: 'SRT Language', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          items: supportedLanguages.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(),
          onChanged: (v) { if (v != null) setState(() => _sourceLanguage = v); })),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
        Expanded(child: DropdownButtonFormField<Language>(value: _targetLanguage, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Target Language', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          items: supportedLanguages.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(),
          onChanged: (v) { if (v != null) setState(() => _targetLanguage = v); })),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: (_isTranslating || _subtitles.isEmpty) ? null : _translateSubtitles,
          icon: _isTranslating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.translate),
          label: Text(_isTranslating ? 'Translating...' : 'Translate'))),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: (_subtitles.isEmpty || !_subtitles.any((e) => e.translatedText != null)) ? null : _exportTranslatedSrt,
          icon: const Icon(Icons.save_alt),
          label: const Text('Export SRT'),
        ),
      ]),
    ])));
  }

  Widget _buildVoiceSettingsSection() {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('3. Choose Voice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text('Select the language for the generated voice audio.', style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 12),
      // Voice language for TTS API - uses supportedLanguages which works everywhere
      DropdownButtonFormField<Language>(
        value: _targetLanguage,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Voice Language (for MP3 generation)',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: supportedLanguages.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() => _targetLanguage = v);
            _ttsService.setLanguage(v.code);
          }
        },
      ),
      const SizedBox(height: 12),
      // Device voice selector for Preview (only shown if device voices available)
      if (!kIsWeb && _filteredVoices.isNotEmpty) ...[
        DropdownButtonFormField<Map<String, String>>(
          value: _filteredVoices.contains(_selectedVoice) ? _selectedVoice : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Device Voice for Preview (${_filteredVoices.length} available)',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: _filteredVoices.map((voice) => DropdownMenuItem(
            value: voice,
            child: Text(_ttsService.getVoiceDisplayName(voice), overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) {
            if (v != null) { setState(() => _selectedVoice = v); _ttsService.setVoice(v); }
          },
        ),
        const SizedBox(height: 12),
      ],
      // Speed slider
      Row(children: [
        const SizedBox(width: 80, child: Text('Base Speed:')),
        Expanded(child: Slider(value: _speechRate, min: 0.25, max: 1.0, divisions: 15, label: '${(_speechRate * 100).round()}%',
          onChanged: (v) => setState(() => _speechRate = v))),
        SizedBox(width: 45, child: Text('${(_speechRate * 100).round()}%')),
      ]),
      const Text('Note: Speed is automatically adjusted per sentence to match subtitle timing.', style: TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 8),
      Row(children: [
        const SizedBox(width: 80, child: Text('Pitch:')),
        Expanded(child: Slider(value: _pitch, min: 0.5, max: 2.0, divisions: 15, label: _pitch.toStringAsFixed(1),
          onChanged: (v) => setState(() => _pitch = v))),
        SizedBox(width: 45, child: Text(_pitch.toStringAsFixed(1))),
      ]),
    ])));
  }

  Widget _buildControlsSection() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('4. Generate Audio File', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          kIsWeb
            ? 'Downloads MP3 file with each subtitle spoken at correct timing.\nUses free TTS API - no account needed.'
            : 'Generates an MP3 file with each subtitle spoken at the EXACT timing.\nUses free Google Translate TTS API - no account needed.\nVoice speed matches subtitle duration.',
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: (_isGenerating || _isSpeaking || _subtitles.isEmpty) ? null : _generateAudio,
            icon: Icon(kIsWeb ? Icons.download : Icons.download),
            label: Text(kIsWeb ? 'Download MP3' : 'Generate MP3'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
          )),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            onPressed: (_isGenerating || _isSpeaking || _subtitles.isEmpty) ? null : _previewSpeak,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Preview'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
        if (_isSpeaking || _isGenerating) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _stopSpeaking, icon: const Icon(Icons.stop), label: const Text('Stop'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)))),
        ],
      ])),
    );
  }

  Widget _buildStatusSection() {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(_statusMessage.toLowerCase().contains('error') ? Icons.error : _statusMessage.toLowerCase().contains('done') || _statusMessage.toLowerCase().contains('complete') ? Icons.check_circle : Icons.info,
          color: _statusMessage.toLowerCase().contains('error') ? Colors.red : _statusMessage.toLowerCase().contains('done') || _statusMessage.toLowerCase().contains('complete') ? Colors.green : Colors.blue),
        const SizedBox(width: 8),
        Expanded(child: Text(_statusMessage, style: TextStyle(fontWeight: FontWeight.w500, color: _statusMessage.toLowerCase().contains('error') ? Colors.red : null))),
      ]),
      if (_progress > 0 && _progress < 1.0) ...[
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _progress),
        Text('${(_progress * 100).toStringAsFixed(0)}%'),
      ],
    ])));
  }

  Widget _buildSubtitlePreview() {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Subtitle Preview (${_subtitles.length} entries)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      SizedBox(height: 300, child: ListView.builder(
        itemCount: _subtitles.length,
        itemBuilder: (context, index) {
          final entry = _subtitles[index];
          final isCurrent = index == _currentSpeakingIndex;
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(color: isCurrent ? Theme.of(context).colorScheme.primaryContainer : null, borderRadius: BorderRadius.circular(8)),
            child: ListTile(dense: true,
              leading: CircleAvatar(radius: 14, backgroundColor: isCurrent ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text('${entry.index}', style: TextStyle(fontSize: 11, color: isCurrent ? Colors.white : null))),
              title: Text(entry.displayText, style: TextStyle(fontSize: 13, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
              subtitle: Text('${SrtParser.formatTimestamp(entry.startTime)} --> ${SrtParser.formatTimestamp(entry.endTime)} (${(entry.duration.inMilliseconds / 1000).toStringAsFixed(1)}s)', style: const TextStyle(fontSize: 11)),
            ),
          );
        },
      )),
    ])));
  }
}
