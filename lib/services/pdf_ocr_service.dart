import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Raw pixel data + dimensions for one rendered PDF page. Produced by
/// `PdfPageWidget` after each render; consumed by `PdfOcrService`.
class OcrPageSource {
  final Uint8List pixels; // RGBA8888
  final int width;
  final int height;
  const OcrPageSource({
    required this.pixels,
    required this.width,
    required this.height,
  });
}

/// One text line discovered by OCR rather than by content-stream analysis.
/// Coordinates are in PDF points with a bottom-up origin, matching the
/// convention used by `TextRun` in the content-stream analyzer — so the
/// overlay's existing coordinate math works unchanged.
class OcrTextRun {
  final String text;
  final double x, y, width, height;
  final double confidence;
  const OcrTextRun({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });
}

class PdfOcrService {
  /// Runs ML Kit text recognition on the rendered page image and returns
  /// the recognized lines as [OcrTextRun]s.
  ///
  /// Returns an empty list on web (ML Kit has no web support), or if the
  /// source is null, or if recognition throws.
  ///
  /// MUST be called on the main isolate. `processImage` uses platform
  /// channels and will throw if invoked from a background isolate.
  static Future<List<OcrTextRun>> recognizePage({
    required OcrPageSource source,
    required double pageWidthPt,
    required double pageHeightPt,
  }) async {
    if (kIsWeb) return const [];
    if (source.width <= 0 || source.height <= 0) return const [];

    TextRecognizer? recognizer;
    try {
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);

      final input = InputImage.fromBitmap(
        bitmap: source.pixels,
        width: source.width,
        height: source.height,
      );
      final result = await recognizer.processImage(input);

      final sx = pageWidthPt / source.width;
      final sy = pageHeightPt / source.height;
      final runs = <OcrTextRun>[];

      for (final block in result.blocks) {
        for (final line in block.lines) {
          final bb = line.boundingBox;
          if (bb.width <= 0 || bb.height <= 0) continue;
          final text = line.text.trim();
          if (text.isEmpty) continue;

          // ML Kit bbox: top-left origin, y-down, pixel coordinates.
          // TextRun convention: PDF points, bottom-up origin.
          // The bottom edge in PDF space is pageHeightPt minus the pixel
          // bbox's bottom edge, scaled.
          final x = bb.left * sx;
          final w = bb.width * sx;
          final h = bb.height * sy;
          final yBottom = pageHeightPt - (bb.top + bb.height) * sy;

          runs.add(OcrTextRun(
            text: text,
            x: x,
            y: yBottom,
            width: w,
            height: h,
            confidence: line.confidence ?? 0.0,
          ));
        }
      }
      return runs;
    } catch (_) {
      return const [];
    } finally {
      try {
        await recognizer?.close();
      } catch (_) {}
    }
  }
}