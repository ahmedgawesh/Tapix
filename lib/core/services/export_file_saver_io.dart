import 'dart:io';
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
    final path = await FilePicker.platform.saveFile(
      dialogTitle: filename,
      fileName: filename,
      bytes: bytes,
    );

    if (path == null || path.isEmpty) {
      return false;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return true;
    }

    await File(path).writeAsBytes(bytes, flush: true);
    return true;
  }
}

ExportFileSaver createExportFileSaver() => _ExportFileSaverIo();
