import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> exportSrt(String srtContent) async {
  Directory saveDir;
  if (Platform.isAndroid) {
    saveDir = Directory('/storage/emulated/0/Download');
    if (!await saveDir.exists()) {
      saveDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    }
  } else {
    saveDir = await getApplicationDocumentsDirectory();
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final fileName = 'translated_$timestamp.srt';
  final file = File('${saveDir.path}/$fileName');
  await file.writeAsString(srtContent);

  return 'Exported: $fileName\nSaved to: ${saveDir.path}';
}
