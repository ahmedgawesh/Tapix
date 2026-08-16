import 'dart:convert';
import 'dart:typed_data';

/// Converts an RGBA label image into a TSPL BITMAP print command.
Uint8List buildTsplBitmapCommand({
  required Uint8List rgbaPixels,
  required int pixelWidth,
  required int pixelHeight,
  required double widthMm,
  required double heightMm,
}) {
  if (pixelWidth <= 0 || pixelHeight <= 0) {
    throw ArgumentError('Label bitmap dimensions must be positive');
  }
  if (rgbaPixels.length < pixelWidth * pixelHeight * 4) {
    throw ArgumentError('RGBA buffer is smaller than the label dimensions');
  }

  final widthBytes = (pixelWidth + 7) ~/ 8;
  final bitmap = Uint8List(widthBytes * pixelHeight);

  for (var y = 0; y < pixelHeight; y++) {
    for (var x = 0; x < pixelWidth; x++) {
      final pixelOffset = (y * pixelWidth + x) * 4;
      final red = rgbaPixels[pixelOffset];
      final green = rgbaPixels[pixelOffset + 1];
      final blue = rgbaPixels[pixelOffset + 2];
      final alpha = rgbaPixels[pixelOffset + 3];
      final luminance = (red * 299 + green * 587 + blue * 114) ~/ 1000;
      final whiteComposited = (luminance * alpha + 255 * (255 - alpha)) ~/ 255;
      if (whiteComposited < 160) {
        final byteOffset = y * widthBytes + (x ~/ 8);
        bitmap[byteOffset] |= 0x80 >> (x % 8);
      }
    }
  }

  final command = BytesBuilder(copy: false)
    ..add(
      ascii.encode(
        'SIZE ${widthMm.toStringAsFixed(1)} mm,'
        '${heightMm.toStringAsFixed(1)} mm\r\n'
        'GAP 2 mm,0 mm\r\n'
        'DIRECTION 1\r\n'
        'REFERENCE 0,0\r\n'
        'CLS\r\n'
        'BITMAP 0,0,$widthBytes,$pixelHeight,0,',
      ),
    )
    ..add(bitmap)
    ..add(ascii.encode('\r\nPRINT 1,1\r\n'));
  return command.takeBytes();
}
