import 'dart:typed_data';
import 'lexer.dart';
import 'filters.dart';
import 'object_parser.dart';

class XrefTable {
  final Map<int, int> offsets = {};
  final Map<int, List<int>> compressedLocations = {};
  final Map<String, dynamic> trailerDict = {};
}

class PdfXrefParser {
  final Uint8List _bytes;
  final PdfLexer _lexer;
  PdfXrefParser(this._bytes) : _lexer = PdfLexer(_bytes);

  int findLastStartXref() {
    int startScan = _bytes.length - 4096;
    if (startScan < 0) startScan = 0;
    for (int i = _bytes.length - 9; i >= startScan; i--) {
      if (_bytes[i] == 115 && _bytes[i + 1] == 116 &&
          _bytes[i + 2] == 97 && _bytes[i + 3] == 114) {
        final window = String.fromCharCodes(_bytes.sublist(i, i + 9));
        if (window == 'startxref') {
          _lexer.seek(i + 9);
          final token = _lexer.nextToken();
          if (token.type == PdfTokenType.number) {
            return (token.value as num).toInt();
          }
        }
      }
    }
    throw FormatException('Malformed PDF: Cannot find startxref token.');
  }

  XrefTable parseGlobalOffsets() {
    final globalTable = XrefTable();
    int? currentXrefOffset = findLastStartXref();

    while (currentXrefOffset != null && currentXrefOffset > 0) {
      _lexer.seek(currentXrefOffset);
      final token = _lexer.nextToken();

      if (token.type == PdfTokenType.keyword && token.value == 'xref') {
        _parseClassicXrefSection(globalTable);
        final trailerToken = _lexer.nextToken();
        if (trailerToken.type == PdfTokenType.keyword &&
            trailerToken.value == 'trailer') {
          final localTrailer = _parseTrailerDictionary();
          localTrailer.forEach((key, val) {
            globalTable.trailerDict.putIfAbsent(key, () => val);
          });
          currentXrefOffset = localTrailer.containsKey('/Prev')
              ? (localTrailer['/Prev'] as num).toInt()
              : null;
        } else {
          currentXrefOffset = null;
        }
      } else if (token.type == PdfTokenType.number) {
        final handled = _parseXrefStream(currentXrefOffset!, globalTable);
        if (!handled) { currentXrefOffset = null; break; }
        currentXrefOffset = globalTable.trailerDict.containsKey('/Prev')
            ? (globalTable.trailerDict['/Prev'] as num).toInt()
            : null;
      } else {
        currentXrefOffset = null;
      }
    }
    return globalTable;
  }

  bool _parseXrefStream(int offset, XrefTable table) {
    try {
      _lexer.seek(offset);
      _lexer.nextToken(); // obj id
      _lexer.nextToken(); // generation
      final objKw = _lexer.nextToken();
      if (objKw.type != PdfTokenType.keyword || objKw.value != 'obj') return false;

      final dictOpen = _lexer.nextToken();
      if (dictOpen.type != PdfTokenType.openDict) return false;

      final streamDict = <String, dynamic>{};
      while (true) {
        final k = _lexer.nextToken();
        if (k.type == PdfTokenType.closeDict || k.type == PdfTokenType.eof) break;
        final v = _lexer.nextToken();
        if (k.type == PdfTokenType.name) {
          streamDict['/${k.value}'] = _parseTrailerValue(v);
        }
      }

      streamDict.forEach((key, val) {
        table.trailerDict.putIfAbsent(key, () => val);
      });

      final streamKw = _lexer.nextToken();
      if (streamKw.type != PdfTokenType.keyword || streamKw.value != 'stream') {
        return false;
      }

      int pos = _lexer.offset;
      if (pos < _bytes.length && _bytes[pos] == 13) pos++;
      if (pos < _bytes.length && _bytes[pos] == 10) pos++;

      final streamLength = _resolveLength(streamDict['/Length']);
      if (streamLength <= 0 || pos + streamLength > _bytes.length) return false;

      final rawStream = _bytes.sublist(pos, pos + streamLength);
      final filters = _resolveFilters(streamDict['/Filter']);
      final data = filters.isEmpty
          ? rawStream
          : PdfFilterDecoder.decodeStream(rawStream, filters);

      final wArr = _resolveIntArray(streamDict['/W']);
      if (wArr.length < 3) return false;
      final w0 = wArr[0], w1 = wArr[1], w2 = wArr[2];
      final entrySize = w0 + w1 + w2;
      if (entrySize == 0) return false;

      var index = _resolveIntArray(streamDict['/Index']);
      if (index.isEmpty) {
        final size = _resolveLength(streamDict['/Size']);
        index = [0, size];
      }

      int dataPos = 0;
      for (int pair = 0; pair < index.length - 1; pair += 2) {
        final firstId = index[pair];
        final count = index[pair + 1];
        for (int i = 0; i < count; i++) {
          if (dataPos + entrySize > data.length) break;
          final type = _readInt(data, dataPos, w0);
          final field1 = _readInt(data, dataPos + w0, w1);
          final field2 = _readInt(data, dataPos + w0 + w1, w2);
          dataPos += entrySize;
          final objId = firstId + i;
          if (type == 1) {
            table.offsets.putIfAbsent(objId, () => field1);
          } else if (type == 2) {
            table.compressedLocations.putIfAbsent(objId, () => [field1, field2]);
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _parseClassicXrefSection(XrefTable table) {
    while (true) {
      final savepoint = _lexer.offset;
      final first = _lexer.nextToken();
      if (first.type == PdfTokenType.keyword && first.value == 'trailer') {
        _lexer.seek(savepoint);
        break;
      }
      final second = _lexer.nextToken();
      if (first.type == PdfTokenType.number && second.type == PdfTokenType.number) {
        final startId = (first.value as num).toInt();
        final count = (second.value as num).toInt();
        for (int i = 0; i < count; i++) {
          final offsetTok = _lexer.nextToken();
          final genTok = _lexer.nextToken();
          final statusTok = _lexer.nextToken();
          final objId = startId + i;
          final offset = (offsetTok.value as num).toInt();
          final status = statusTok.value.toString();
          if (status == 'n') {
            table.offsets.putIfAbsent(objId, () => offset);
          }
        }
      } else {
        break;
      }
    }
  }

  Map<String, dynamic> _parseTrailerDictionary() {
    final open = _lexer.nextToken();
    if (open.type != PdfTokenType.openDict) {
      throw FormatException('Expected dictionary opening token inside file trailer.');
    }
    final dict = <String, dynamic>{};
    while (true) {
      final keyTok = _lexer.nextToken();
      if (keyTok.type == PdfTokenType.closeDict || keyTok.type == PdfTokenType.eof) break;
      final valTok = _lexer.nextToken();
      if (keyTok.type == PdfTokenType.name) {
        dict['/${keyTok.value}'] = _parseTrailerValue(valTok);
      }
    }
    return dict;
  }

  dynamic _parseTrailerValue(PdfToken first) {
    if (first.type == PdfTokenType.openArray) {
      final items = <dynamic>[];
      while (true) {
        final t = _lexer.nextToken();
        if (t.type == PdfTokenType.closeArray || t.type == PdfTokenType.eof) break;
        items.add(_parseTrailerValue(t));
      }
      return items;
    }
    if (first.type == PdfTokenType.number) {
      final savePoint = _lexer.offset;
      final second = _lexer.nextToken();
      if (second.type == PdfTokenType.number) {
        final third = _lexer.nextToken();
        if (third.type == PdfTokenType.keyword && third.value == 'R') {
          return PdfIndirectReference(
              (first.value as num).toInt(), (second.value as num).toInt());
        }
      }
      _lexer.seek(savePoint);
      return first.value;
    }
    if (first.type == PdfTokenType.openDict) {
      final d = <String, dynamic>{};
      while (true) {
        final k = _lexer.nextToken();
        if (k.type == PdfTokenType.closeDict || k.type == PdfTokenType.eof) break;
        final v = _lexer.nextToken();
        if (k.type == PdfTokenType.name) {
          d['/${k.value}'] = _parseTrailerValue(v);
        }
      }
      return d;
    }
    return _tokenValue(first);
  }

  int _readInt(Uint8List data, int pos, int width) {
    if (width == 0) return 1;
    int val = 0;
    for (int i = 0; i < width; i++) {
      val = (val << 8) | data[pos + i];
    }
    return val;
  }

  int _resolveLength(dynamic v) => v is num ? v.toInt() : 0;

  List<String> _resolveFilters(dynamic v) {
    if (v == null) return [];
    if (v is String) return [v.startsWith('/') ? v : '/$v'];
    if (v is List) {
      return v.map((e) => e.toString().startsWith('/')
          ? e.toString() : '/${e}').toList();
    }
    return [];
  }

  List<int> _resolveIntArray(dynamic v) {
    if (v is List) {
      return v.where((e) => e is num).map((e) => (e as num).toInt()).toList();
    }
    return [];
  }

  dynamic _tokenValue(PdfToken t) {
    switch (t.type) {
      case PdfTokenType.number: return t.value;
      case PdfTokenType.name: return '/${t.value}';
      default: return t.value;
    }
  }
}