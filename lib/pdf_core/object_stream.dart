import 'dart:typed_data';
import 'lexer.dart';
import 'object_parser.dart';

class PdfObjectStreamDecoder {
  Map<int, dynamic> decodeCompressedObjects(
      Map<String, dynamic> streamDict, Uint8List decompressedData) {
    final result = <int, dynamic>{};
    final count = _intVal(streamDict['/N']);
    final firstOffset = _intVal(streamDict['/First']);
    if (count == null || firstOffset == null || count == 0) return result;

    final lexer = PdfLexer(decompressedData);
    final objectIds = <int>[];
    final relativeOffsets = <int>[];

    for (int i = 0; i < count; i++) {
      final idTok = lexer.nextToken();
      final offsetTok = lexer.nextToken();
      if (idTok.type == PdfTokenType.number && offsetTok.type == PdfTokenType.number) {
        objectIds.add((idTok.value as num).toInt());
        relativeOffsets.add((offsetTok.value as num).toInt());
      }
    }

    for (int i = 0; i < objectIds.length; i++) {
      final pos = firstOffset + relativeOffsets[i];
      if (pos >= decompressedData.length) continue;
      lexer.seek(pos);
      final parser = PdfObjectParser(lexer, {});
      try {
        result[objectIds[i]] = parser.parseObject();
      } catch (_) {}
    }
    return result;
  }

  int? _intVal(dynamic v) => v is num ? v.toInt() : null;
}