import 'lexer.dart';

class PdfIndirectReference {
  final int objectId;
  final int generation;
  const PdfIndirectReference(this.objectId, this.generation);
  @override
  String toString() => 'Ref($objectId $generation R)';
}

class PdfObjectParser {
  final PdfLexer _lexer;
  final Map<int, int> _xrefTable;
  PdfObjectParser(this._lexer, this._xrefTable);

  dynamic parseObject() {
    final token = _lexer.nextToken();
    return _parseValue(token);
  }

  dynamic _parseValue(PdfToken token) {
    switch (token.type) {
      case PdfTokenType.number:
        final savePoint = _lexer.offset;
        final next = _lexer.nextToken();
        if (next.type == PdfTokenType.number) {
          final targetRef = _lexer.nextToken();
          if (targetRef.type == PdfTokenType.keyword && targetRef.value == 'R') {
            return PdfIndirectReference(
                (token.value as num).toInt(), (next.value as num).toInt());
          }
        }
        _lexer.seek(savePoint);
        return token.value;

      case PdfTokenType.name:
        return '/${token.value}';

      case PdfTokenType.string:
      case PdfTokenType.keyword:
        return token.value;

      case PdfTokenType.openArray:
        final array = <dynamic>[];
        while (true) {
          final t = _lexer.nextToken();
          if (t.type == PdfTokenType.closeArray || t.type == PdfTokenType.eof) break;
          array.add(_parseValue(t));
        }
        return array;

      case PdfTokenType.openDict:
        final dictionary = <String, dynamic>{};
        while (true) {
          final keyToken = _lexer.nextToken();
          if (keyToken.type == PdfTokenType.closeDict ||
              keyToken.type == PdfTokenType.eof) break;
          final valueToken = _lexer.nextToken();
          if (keyToken.type == PdfTokenType.name) {
            dictionary['/${keyToken.value}'] = _parseValue(valueToken);
          }
        }
        return dictionary;

      default:
        return null;
    }
  }
}