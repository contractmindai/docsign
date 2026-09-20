import 'dart:typed_data';

enum PdfTokenType {
  keyword, number, name, string, openDict, closeDict,
  openArray, closeArray, eof,
}

class PdfRawString {
  final List<int> bytes;
  const PdfRawString(this.bytes);
  String get text => String.fromCharCodes(bytes);
  @override
  String toString() => text;
}

class PdfToken {
  final PdfTokenType type;
  final dynamic value;
  final int offset;
  PdfToken(this.type, this.value, this.offset);
  @override
  String toString() => 'Token(${type.name}: $value @$offset)';
}

class PdfLexer {
  final Uint8List _bytes;
  int _offset = 0;
  PdfLexer(this._bytes);
  int get offset => _offset;
  void seek(int target) => _offset = target;

  bool _isWhitespace(int c) =>
      c == 32 || c == 9 || c == 13 || c == 10 || c == 12 || c == 0;

  bool _isDelimiter(int c) =>
      c == 40 || c == 41 || c == 60 || c == 62 ||
      c == 91 || c == 93 || c == 123 || c == 125 ||
      c == 47 || c == 37;

  void _skipWhitespaceAndComments() {
    while (_offset < _bytes.length) {
      final c = _bytes[_offset];
      if (_isWhitespace(c)) {
        _offset++;
      } else if (c == 37) {
        while (_offset < _bytes.length &&
            _bytes[_offset] != 10 && _bytes[_offset] != 13) {
          _offset++;
        }
      } else {
        break;
      }
    }
  }

  PdfToken nextToken() {
    _skipWhitespaceAndComments();
    if (_offset >= _bytes.length) return PdfToken(PdfTokenType.eof, null, _offset);

    final start = _offset;
    final c = _bytes[_offset];

    if (c == 91) { _offset++; return PdfToken(PdfTokenType.openArray, '[', start); }
    if (c == 93) { _offset++; return PdfToken(PdfTokenType.closeArray, ']', start); }

    if (c == 60) {
      if (_offset + 1 < _bytes.length && _bytes[_offset + 1] == 60) {
        _offset += 2;
        return PdfToken(PdfTokenType.openDict, '<<', start);
      }
      return _readHexString();
    }
    if (c == 62) {
      if (_offset + 1 < _bytes.length && _bytes[_offset + 1] == 62) {
        _offset += 2;
        return PdfToken(PdfTokenType.closeDict, '>>', start);
      }
    }
    if (c == 40) return _readLiteralString();
    if (c == 47) return _readName();
    return _readRegularToken();
  }

  PdfToken _readName() {
    final start = _offset++;
    while (_offset < _bytes.length &&
        !_isWhitespace(_bytes[_offset]) && !_isDelimiter(_bytes[_offset])) {
      _offset++;
    }
    final name = String.fromCharCodes(_bytes.sublist(start + 1, _offset));
    return PdfToken(PdfTokenType.name, name, start);
  }

  PdfToken _readLiteralString() {
    final start = _offset++;
    int depth = 1;
    final stringBytes = <int>[];
    while (_offset < _bytes.length && depth > 0) {
      final c = _bytes[_offset];
      if (c == 40) { depth++; stringBytes.add(c); _offset++; }
      else if (c == 41) { depth--; if (depth > 0) stringBytes.add(c); _offset++; }
      else if (c == 92) {
        if (_offset + 1 < _bytes.length) { _offset++; stringBytes.add(_bytes[_offset]); }
        _offset++;
      } else { stringBytes.add(c); _offset++; }
    }
    return PdfToken(PdfTokenType.string, PdfRawString(stringBytes), start);
  }

  PdfToken _readHexString() {
    final start = _offset++;
    final buffer = StringBuffer();
    while (_offset < _bytes.length && _bytes[_offset] != 62) {
      final c = _bytes[_offset];
      if (!_isWhitespace(c)) buffer.writeCharCode(c);
      _offset++;
    }
    if (_offset < _bytes.length) _offset++;
    return PdfToken(PdfTokenType.string, '<${buffer.toString()}>', start);
  }

  PdfToken _readRegularToken() {
    final start = _offset;
    while (_offset < _bytes.length &&
        !_isWhitespace(_bytes[_offset]) && !_isDelimiter(_bytes[_offset])) {
      _offset++;
    }
    final text = String.fromCharCodes(_bytes.sublist(start, _offset));
    final numberValue = num.tryParse(text);
    if (numberValue != null) {
      return PdfToken(PdfTokenType.number, numberValue, start);
    }
    return PdfToken(PdfTokenType.keyword, text, start);
  }
}