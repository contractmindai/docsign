import 'dart:typed_data';

enum ContentStreamTokenType { operator, number, string, array, name }

class ContentStreamToken {
  final ContentStreamTokenType type;
  final dynamic value;
  ContentStreamToken(this.type, this.value);
  @override
  String toString() => 'CSToken(${type.name}: $value)';
}

class ContentStreamLexer {
  final Uint8List _bytes;
  int _offset = 0;
  ContentStreamLexer(this._bytes);
  int get offset => _offset;
  void seek(int newOffset) => _offset = newOffset.clamp(0, _bytes.length);

  bool _isWhitespace(int c) =>
      c == 32 || c == 9 || c == 13 || c == 10 || c == 12 || c == 0;

  bool _isDelimiter(int c) =>
      c == 40 || c == 41 || c == 60 || c == 62 ||
      c == 91 || c == 93 || c == 47;

  void _skipWhitespace() {
    while (_offset < _bytes.length && _isWhitespace(_bytes[_offset])) {
      _offset++;
    }
  }

  ContentStreamToken? nextToken() {
    _skipWhitespace();
    if (_offset >= _bytes.length) return null;
    final c = _bytes[_offset];
    if (c == 40) return _readLiteralString();
    if (c == 60) return _readHexString();
    if (c == 91) return _readArray();
    if (c == 47) return _readName();
    return _readRegularToken();
  }

  ContentStreamToken _readLiteralString() {
    _offset++;
    final collected = <int>[];
    int depth = 1;
    while (_offset < _bytes.length && depth > 0) {
      final c = _bytes[_offset];
      if (c == 40) { depth++; collected.add(c); _offset++; }
      else if (c == 41) { depth--; if (depth > 0) collected.add(c); _offset++; }
      else if (c == 92) {
        if (_offset + 1 < _bytes.length) {
          _offset++;
          collected.add(_bytes[_offset]);
        }
        _offset++;
      } else { collected.add(c); _offset++; }
    }
    return ContentStreamToken(ContentStreamTokenType.string, collected);
  }

  ContentStreamToken _readHexString() {
    _offset++;
    final buffer = StringBuffer();
    while (_offset < _bytes.length && _bytes[_offset] != 62) {
      final c = _bytes[_offset];
      if (!_isWhitespace(c)) buffer.writeCharCode(c);
      _offset++;
    }
    if (_offset < _bytes.length) _offset++;
    return ContentStreamToken(ContentStreamTokenType.string, buffer.toString());
  }

  ContentStreamToken _readArray() {
    _offset++;
    final elements = <dynamic>[];
    while (_offset < _bytes.length) {
      _skipWhitespace();
      if (_offset >= _bytes.length) break;
      if (_bytes[_offset] == 93) { _offset++; break; }
      final internalToken = nextToken();
      if (internalToken != null) elements.add(internalToken.value);
    }
    return ContentStreamToken(ContentStreamTokenType.array, elements);
  }

  ContentStreamToken _readName() {
    _offset++;
    final start = _offset;
    while (_offset < _bytes.length &&
        !_isWhitespace(_bytes[_offset]) && !_isDelimiter(_bytes[_offset])) {
      _offset++;
    }
    final name = String.fromCharCodes(_bytes.sublist(start, _offset));
    return ContentStreamToken(ContentStreamTokenType.name, name);
  }

  ContentStreamToken _readRegularToken() {
    final start = _offset;
    while (_offset < _bytes.length &&
        !_isWhitespace(_bytes[_offset]) && !_isDelimiter(_bytes[_offset])) {
      _offset++;
    }
    final text = String.fromCharCodes(_bytes.sublist(start, _offset));
    final number = num.tryParse(text);
    if (number != null) {
      return ContentStreamToken(ContentStreamTokenType.number, number);
    }
    return ContentStreamToken(ContentStreamTokenType.operator, text);
  }
}