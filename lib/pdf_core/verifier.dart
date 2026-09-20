import 'dart:typed_data';
import '../pdf_core/lexer.dart';
import '../pdf_core/xref_parser.dart';

class PdfStructureVerificationResult {
  final bool isValid;
  final String report;
  PdfStructureVerificationResult(this.isValid, this.report);
}

class PdfOutputVerifier {
  PdfStructureVerificationResult verifyDocumentBytes(Uint8List outputBytes) {
    if (outputBytes.isEmpty) {
      return PdfStructureVerificationResult(false, 'File payload is empty.');
    }
    if (outputBytes.length < 20) {
      return PdfStructureVerificationResult(false, 'File too short.');
    }

    final fileHeader = String.fromCharCodes(outputBytes.sublist(0, 5));
    if (!fileHeader.startsWith('%PDF-')) {
      return PdfStructureVerificationResult(false, 'Missing %PDF magic prefix.');
    }

    final eofWindow = String.fromCharCodes(
        outputBytes.sublist(outputBytes.length - 15));
    if (!eofWindow.contains('%%EOF')) {
      return PdfStructureVerificationResult(false, 'Missing %%EOF marker.');
    }

    try {
      final parser = PdfXrefParser(outputBytes);
      final table = parser.parseGlobalOffsets();

      if (table.offsets.isEmpty && table.compressedLocations.isEmpty) {
        return PdfStructureVerificationResult(false, 'No xref entries found.');
      }
      if (!table.trailerDict.containsKey('/Size')) {
        return PdfStructureVerificationResult(false, 'Trailer lacks /Size.');
      }

      final lexer = PdfLexer(outputBytes);
      for (final objId in table.offsets.keys) {
        final offset = table.offsets[objId]!;
        if (offset >= outputBytes.length) {
          return PdfStructureVerificationResult(
              false, 'Object $objId offset out of bounds ($offset).');
        }
        lexer.seek(offset);
        final token = lexer.nextToken();
        if (token.type != PdfTokenType.number ||
            (token.value as num).toInt() != objId) {
          return PdfStructureVerificationResult(false,
              'Xref mismatch: object $objId at $offset reads as ${token.value}.');
        }
      }

      return PdfStructureVerificationResult(true,
          'Validation passed: ${table.offsets.length} object pointers verified.');
    } catch (e) {
      return PdfStructureVerificationResult(false, 'Parse error: $e');
    }
  }
}