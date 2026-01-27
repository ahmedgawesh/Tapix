import 'dart:typed_data';

import 'export_file_saver_io.dart'
    if (dart.library.html) 'export_file_saver_web.dart' as impl;

abstract class ExportFileSaver {
  Future<bool> saveBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  });
}

ExportFileSaver createExportFileSaver() => impl.createExportFileSaver();
