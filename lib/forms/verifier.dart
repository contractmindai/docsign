import 'dart:typed_data';
import '../pdf_core/lexer.dart';
import '../pdf_core/xref_parser.dart';

class PdfStructureVerificationResult {
  final bool isValid;
  final String report;

  PdfStructureVerificationResult(this.isValid, this.report);
}

class PdfOutputVerifier {
  /// Re-parses a generated document to catch trailing offsets corruption mistakes early.
  PdfStructureVerificationResult verifyDocumentBytes(Uint8List outputBytes) {
    if (outputBytes.isEmpty) {
      return PdfStructureVerificationResult(false, 'File payload is empty.');
    }
    if (outputBytes.length < 20) {
      return PdfStructureVerificationResult(false, 'File is too short to be a valid PDF (${outputBytes.length} bytes).');
    }

    // 1. Verify standard PDF signature markers exist at document boundaries
    String fileHeaderHeader = String.fromCharCodes(outputBytes.sublist(0, 5));
    if (!fileHeaderHeader.startsWith('%PDF-')) {
      return PdfStructureVerificationResult(false, 'Missing structural %PDF magic prefix flag identifier.');
    }

    // 2. Check document terminator strings are present
    String EOFWindow = String.fromCharCodes(outputBytes.sublist(outputBytes.length - 15));
    if (!EOFWindow.contains('%%EOF')) {
      return PdfStructureVerificationResult(false, 'Document lacks structural closure boundary marker strings (%%EOF).');
    }

    try {
      // 3. Initialize complete bottom-up structural analysis using your custom parser modules
      final PdfXrefParser verifierParser = PdfXrefParser(outputBytes);
      final XrefTable structuralLookups = verifierParser.parseGlobalOffsets();

      if (structuralLookups.offsets.isEmpty) {
        return PdfStructureVerificationResult(false, 'The cross-reference scanner found zero object pointer entries.');
      }

      if (!structuralLookups.trailerDict.containsKey('/Size')) {
        return PdfStructureVerificationResult(false, 'The analyzed trailer lacks a valid structural object total limit registry count entry (/Size).');
      }

      // 4. Trace index pointer tables to verify every object is accessible at its declared byte boundary
      final PdfLexer structuralLexer = PdfLexer(outputBytes);
      
      for (int objId in structuralLookups.offsets.keys) {
        int targetedOffset = structuralLookups.offsets[objId]!;
        
        if (targetedOffset >= outputBytes.length) {
          return PdfStructureVerificationResult(false, 'Object entry vector map table contains an out-of-bounds pointer offset location pointing to position $targetedOffset.');
        }

        structuralLexer.seek(targetedOffset);
        PdfToken objectCheckToken = structuralLexer.nextToken();

        // Every targeted address index location must match its exact Object ID entry header string sequence
        if (objectCheckToken.type != PdfTokenType.number || (objectCheckToken.value as num).toInt() != objId) {
          return PdfStructureVerificationResult(
            false,
            'Structural table mismatch: Xref claims entry tracking point ID $objId starts at offset context position $targetedOffset, but parser hit incorrect token sequence (${objectCheckToken.value}).'
          );
        }
      }

      // If every boundary matches its lookup mapping, the update saved successfully
      int foundCount = structuralLookups.offsets.length;
      return PdfStructureVerificationResult(
        true,
        'Validation passed successfully: Parsed $foundCount object lookup pointers with consistent structural lineage mappings.'
      );

    } catch (parsingException) {
      return PdfStructureVerificationResult(
        false,
        'Internal data structural parse validation cycle failure exception: ${parsingException.toString()}'
      );
    }
  }
}
