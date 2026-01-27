// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'export_file_saver.dart';

class _ExportFileSaverWeb implements ExportFileSaver {
  @override
  Future<bool> saveBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final blob = html.Blob(<dynamic>[bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();

    html.Url.revokeObjectUrl(url);
    return true;
  }
}

ExportFileSaver createExportFileSaver() => _ExportFileSaverWeb();
