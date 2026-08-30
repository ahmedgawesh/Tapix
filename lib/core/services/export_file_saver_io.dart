import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'export_file_saver.dart';

class _ExportFileSaverIo implements ExportFileSaver {
  @override
  Future<bool> saveBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: filename,
      fileName: filename,
      bytes: bytes,
      mimeType: mimeType,
    );
    return uri != null;
  }
}

ExportFileSaver createExportFileSaver() => _ExportFileSaverIo();
