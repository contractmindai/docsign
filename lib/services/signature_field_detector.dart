import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/annotation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SignatureFieldDetector
//
// Detects potential signature/date lines by scanning the rendered page image
// for long horizontal dark line segments — the classic "sign here ___" line.
//
// Uses the `image` package for pixel-level analysis; no text extraction needed.
// Resolution-independent: works on any render size.
// ─────────────────────────────────────────────────────────────────────────────

class SignatureFieldDetector {
  // Minimum line width as a fraction of page width to qualify
  static const _kMinLineFrac = 0.18;
  // Darkness threshold (0=black, 255=white)
  static const _kDarkThreshold = 80;
  // Skip the top 20% of page (header area) and bottom 3%
  static const _kTopSkip    = 0.20;
  static const _kBottomSkip = 0.03;
  // Minimum vertical gap between detected lines (avoid duplicate detections)
  static const _kMinRowGap = 0.015;

  static Future<List<DetectedField>> detect({
    required Uint8List pageImageBytes,
    required int pageIndex,
  }) async {
    final decoded = img.decodeImage(pageImageBytes);
    if (decoded == null) return [];

    final w = decoded.width;
    final h = decoded.height;
    final minLinePixels = (w * _kMinLineFrac).round();
    final topY    = (h * _kTopSkip).round();
    final bottomY = (h * (1.0 - _kBottomSkip)).round();

    final results = <DetectedField>[];
    double lastNormY = -1.0;

    for (int y = topY; y < bottomY; y++) {
      int consecutive = 0;
      int lineStart   = 0;

      for (int x = 0; x < w; x++) {
        final pixel = decoded.getPixel(x, y);
        // Luminance: weighted average of R, G, B
        final lum = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).round();
        if (lum < _kDarkThreshold) {
          if (consecutive == 0) lineStart = x;
          consecutive++;
        } else {
          if (consecutive >= minLinePixels) {
            final normY = y / h;
            // Enforce minimum gap between detections
            if (normY - lastNormY > _kMinRowGap) {
              final normX = lineStart / w;
              final normW = consecutive / w;
              // Heuristic label: narrow lines near bottom-right = "Date"
              final label = (normX > 0.55 && normW < 0.3) ? 'Date' : 'Signature';
              results.add(DetectedField(
                pageIndex: pageIndex,
                normX: normX,
                normY: normY - 0.045, // position hint above the line
                normWidth: normW.clamp(0.15, 0.60),
                label: label,
              ));
              lastNormY = normY;
            }
          }
          consecutive = 0;
        }
      }
      // Check at end of row
      if (consecutive >= minLinePixels) {
        final normY = y / h;
        if (normY - lastNormY > _kMinRowGap) {
          final normX = lineStart / w;
          final normW = consecutive / w;
          final label = (normX > 0.55 && normW < 0.3) ? 'Date' : 'Signature';
          results.add(DetectedField(
            pageIndex: pageIndex,
            normX: normX,
            normY: normY - 0.045,
            normWidth: normW.clamp(0.15, 0.60),
            label: label,
          ));
          lastNormY = normY;
        }
      }
    }

    // Cap at 6 detected fields per page
    return results.take(6).toList();
  }
}
