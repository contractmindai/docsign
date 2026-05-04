import 'dart:typed_data';
import '../models/annotation.dart';

// ✅ DISABLED — false positive rate too high on scanned documents and
// image-based PDFs (detected every horizontal line, scan line, table border).
// Will be re-enabled with ML-based detection in a future version.
class SignatureFieldDetector {
  static Future<List<DetectedField>> detect({
    required Uint8List pageImageBytes,
    required int pageIndex,
  }) async => const [];
}
