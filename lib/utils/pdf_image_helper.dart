import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Convert pdfrx 1.3.5 PdfImage to PNG bytes.
/// PdfImage.pixels is BGRA uint8 data; we convert via dart:ui.
Future<Uint8List?> pdfImageToPng(PdfImage img) async {
  try {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      img.pixels,
      img.width,
      img.height,
      ui.PixelFormat.bgra8888,
      (result) => completer.complete(result),
    );
    final uiImg   = await completer.future;
    final bd      = await uiImg.toByteData(format: ui.ImageByteFormat.png);
    uiImg.dispose();
    return bd?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
