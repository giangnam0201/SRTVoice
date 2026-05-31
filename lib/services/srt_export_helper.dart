import 'srt_export_stub.dart'
    if (dart.library.js_interop) 'srt_export_web.dart'
    if (dart.library.io) 'srt_export_native.dart';

class SrtExportHelper {
  static Future<String> export(String srtContent) async {
    return await exportSrt(srtContent);
  }
}
