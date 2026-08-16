import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/barcode/services/tspl_bitmap_encoder.dart';

void main() {
  test('encodes black pixels into the expected TSPL bitmap bits', () {
    final pixels = Uint8List(8 * 4);
    for (var x = 0; x < 8; x++) {
      final offset = x * 4;
      final isBlack = x == 0 || x == 7;
      pixels[offset] = isBlack ? 0 : 255;
      pixels[offset + 1] = isBlack ? 0 : 255;
      pixels[offset + 2] = isBlack ? 0 : 255;
      pixels[offset + 3] = 255;
    }

    final command = buildTsplBitmapCommand(
      rgbaPixels: pixels,
      pixelWidth: 8,
      pixelHeight: 1,
      widthMm: 58,
      heightMm: 40,
    );
    final header = ascii.encode('BITMAP 0,0,1,1,0,');
    final headerStart = _indexOf(command, header);

    expect(headerStart, isNonNegative);
    expect(command[headerStart + header.length], 0x81);
    expect(
      ascii.decode(command.sublist(command.length - 13)),
      '\r\nPRINT 1,1\r\n',
    );
  });

  test('transparent black pixels are composited as white', () {
    final command = buildTsplBitmapCommand(
      rgbaPixels: Uint8List.fromList([0, 0, 0, 0]),
      pixelWidth: 1,
      pixelHeight: 1,
      widthMm: 20,
      heightMm: 10,
    );
    final header = ascii.encode('BITMAP 0,0,1,1,0,');
    final headerStart = _indexOf(command, header);

    expect(command[headerStart + header.length], 0x00);
  });
}

int _indexOf(Uint8List source, List<int> pattern) {
  for (var i = 0; i <= source.length - pattern.length; i++) {
    var matches = true;
    for (var j = 0; j < pattern.length; j++) {
      if (source[i + j] != pattern[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return -1;
}
