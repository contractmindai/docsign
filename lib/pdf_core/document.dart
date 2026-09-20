import 'dart:typed_data';
import '../pdf_core/lexer.dart';
import '../pdf_core/xref_parser.dart';
import '../pdf_core/object_parser.dart';
import '../pdf_core/object_stream.dart';
import '../pdf_core/filters.dart';
import '../pdf_core/pdf_decryptor.dart';

class PdfDocumentEngine {
  final Uint8List fileBytes;
  late XrefTable globalXrefTable;
  final Map<int, dynamic> resolvedObjectsCache = {};
  final Map<int, Map<int, dynamic>> _objStreamCache = {};
  PdfDecryptor? decryptor;

  PdfDocumentEngine(this.fileBytes, {String password = ''}) {
    final parser = PdfXrefParser(fileBytes);
    globalXrefTable = parser.parseGlobalOffsets();
    _maybeInitDecryptor(password);
  }

  void _maybeInitDecryptor(String password) {
    final encRef = globalXrefTable.trailerDict['/Encrypt'];
    if (encRef == null) return;

    Uint8List? fileId;
    final idArr = globalXrefTable.trailerDict['/ID'];
    if (idArr is List && idArr.isNotEmpty) {
      fileId = pdfStringToBytes(idArr[0]);
    }

    Map<String, dynamic>? encDict;
    if (encRef is PdfIndirectReference) {
      encDict = _resolveDictRaw(encRef);
    }
    if (encDict == null) return;

    decryptor = PdfDecryptor.fromEncryptDict(
      encDict, fileId,
      (ref) => resolveIndirectReference(ref),
      password,
    );
  }

  Map<String, dynamic>? _resolveDictRaw(PdfIndirectReference ref) {
    final offset = globalXrefTable.offsets[ref.objectId];
    if (offset == null) return null;
    try {
      final lexer = PdfLexer(fileBytes)..seek(offset);
      lexer.nextToken(); lexer.nextToken(); lexer.nextToken();
      final parser = PdfObjectParser(lexer, globalXrefTable.offsets);
      final obj = parser.parseObject();
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {}
    return null;
  }

  dynamic resolveObjectId(int objectId) =>
      resolveIndirectReference(PdfIndirectReference(objectId, 0));

  Map<String, dynamic>? get catalog {
    dynamic rootRef = globalXrefTable.trailerDict['/Root'];
    if (rootRef is PdfIndirectReference) {
      return resolveIndirectReference(rootRef) as Map<String, dynamic>?;
    }
    if (rootRef is List && rootRef.length >= 2) {
      return resolveObjectId((rootRef[0] as num).toInt()) as Map<String, dynamic>?;
    }
    return null;
  }

  int get highestObjectId {
    final maxRegular = globalXrefTable.offsets.isEmpty
        ? 0
        : globalXrefTable.offsets.keys.reduce((a, b) => a > b ? a : b);
    final maxCompressed = globalXrefTable.compressedLocations.isEmpty
        ? 0
        : globalXrefTable.compressedLocations.keys.reduce((a, b) => a > b ? a : b);
    return maxRegular > maxCompressed ? maxRegular : maxCompressed;
  }

  bool get hasUsableXref =>
      globalXrefTable.offsets.isNotEmpty ||
      globalXrefTable.compressedLocations.isNotEmpty;

  ({Map<String, dynamic> dict, Uint8List data})? resolveStream(
      PdfIndirectReference ref) {
    final offset = globalXrefTable.offsets[ref.objectId];
    if (offset == null) return null;
    try {
      final lexer = PdfLexer(fileBytes)..seek(offset);
      lexer.nextToken(); lexer.nextToken(); lexer.nextToken();
      final parser = PdfObjectParser(lexer, globalXrefTable.offsets);
      final dict = parser.parseObject();
      if (dict is! Map<String, dynamic>) return null;

      final kw = lexer.nextToken();
      if (kw.type != PdfTokenType.keyword || kw.value != 'stream') return null;

      int pos = lexer.offset;
      if (pos < fileBytes.length && fileBytes[pos] == 13) pos++;
      if (pos < fileBytes.length && fileBytes[pos] == 10) pos++;

      final length = _resolveLengthValue(dict['/Length']);
      if (length <= 0 || pos + length > fileBytes.length) return null;

      var raw = fileBytes.sublist(pos, pos + length);
      if (decryptor != null) {
        raw = decryptor!.decrypt(ref.objectId, ref.generation, raw);
      }

      final filters = _filtersFrom(dict['/Filter']);
      final data = filters.isEmpty
          ? raw
          : PdfFilterDecoder.decodeStream(raw, filters);

      return (dict: dict, data: data);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> walkPageTree() {
    final pagesManifest = <Map<String, dynamic>>[];
    dynamic rootRef = globalXrefTable.trailerDict['/Root'];
    if (rootRef is! PdfIndirectReference) return pagesManifest;
    final cat = resolveIndirectReference(rootRef) as Map<String, dynamic>?;
    if (cat == null || !cat.containsKey('/Pages')) return pagesManifest;
    dynamic pagesRootRef = cat['/Pages'];
    if (pagesRootRef is PdfIndirectReference) {
      _extractPageNodes(pagesRootRef, pagesManifest);
    }
    return pagesManifest;
  }

  dynamic resolveIndirectReference(PdfIndirectReference ref) {
    if (resolvedObjectsCache.containsKey(ref.objectId)) {
      return resolvedObjectsCache[ref.objectId];
    }
    final offset = globalXrefTable.offsets[ref.objectId];
    if (offset != null) return _resolveFromOffset(ref.objectId, ref.generation, offset);
    final loc = globalXrefTable.compressedLocations[ref.objectId];
    if (loc != null) return _resolveFromObjStream(ref.objectId, loc[0], loc[1]);
    return null;
  }

  dynamic _resolveFromOffset(int objectId, int generation, int offset) {
    try {
      final lexer = PdfLexer(fileBytes)..seek(offset);
      lexer.nextToken(); lexer.nextToken(); lexer.nextToken();
      final parser = PdfObjectParser(lexer, globalXrefTable.offsets);
      dynamic parsedObj = parser.parseObject();
      if (decryptor != null) {
        parsedObj = _decryptStrings(parsedObj, objectId, generation);
      }
      resolvedObjectsCache[objectId] = parsedObj;
      return parsedObj;
    } catch (_) {
      return null;
    }
  }

  dynamic _resolveFromObjStream(int objectId, int streamObjId, int indexInStream) {
    if (!_objStreamCache.containsKey(streamObjId)) {
      final decoded = _decodeObjStream(streamObjId);
      if (decoded == null) return null;
      _objStreamCache[streamObjId] = decoded;
      decoded.forEach((id, obj) {
        resolvedObjectsCache.putIfAbsent(id, () => obj);
      });
    }
    final obj = _objStreamCache[streamObjId]?[objectId];
    if (obj != null) resolvedObjectsCache[objectId] = obj;
    return obj;
  }

  Map<int, dynamic>? _decodeObjStream(int streamObjId) {
    try {
      final offset = globalXrefTable.offsets[streamObjId];
      if (offset == null) return null;
      final lexer = PdfLexer(fileBytes)..seek(offset);
      lexer.nextToken(); lexer.nextToken(); lexer.nextToken();
      final parser = PdfObjectParser(lexer, globalXrefTable.offsets);
      final dict = parser.parseObject();
      if (dict is! Map<String, dynamic>) return null;

      final streamKw = lexer.nextToken();
      if (streamKw.type != PdfTokenType.keyword || streamKw.value != 'stream') {
        return null;
      }
      int pos = lexer.offset;
      if (pos < fileBytes.length && fileBytes[pos] == 13) pos++;
      if (pos < fileBytes.length && fileBytes[pos] == 10) pos++;

      final length = _resolveLengthValue(dict['/Length']);
      if (length <= 0 || pos + length > fileBytes.length) return null;

      var rawStream = fileBytes.sublist(pos, pos + length);
      if (decryptor != null) {
        rawStream = decryptor!.decrypt(streamObjId, 0, rawStream);
      }

      final filters = _filtersFrom(dict['/Filter']);
      final streamData = filters.isEmpty
          ? rawStream
          : PdfFilterDecoder.decodeStream(rawStream, filters);

      return PdfObjectStreamDecoder().decodeCompressedObjects(dict, streamData);
    } catch (_) {
      return null;
    }
  }

  int _resolveLengthValue(dynamic v) {
    if (v is num) return v.toInt();
    if (v is PdfIndirectReference) {
      final r = resolveIndirectReference(v);
      if (r is num) return r.toInt();
    }
    return 0;
  }

  List<String> _filtersFrom(dynamic v) {
    if (v == null) return [];
    if (v is String) return [v];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  dynamic _decryptStrings(dynamic obj, int objId, int gen) {
    if (obj is PdfRawString) {
      final dec = decryptor!.decrypt(objId, gen, Uint8List.fromList(obj.bytes));
      return _bytesToString(dec);
    }
    if (obj is List) {
      return obj.map((e) => _decryptStrings(e, objId, gen)).toList();
    }
    if (obj is Map) {
      final out = <String, dynamic>{};
      obj.forEach((k, v) => out[k.toString()] = _decryptStrings(v, objId, gen));
      return out;
    }
    return obj;
  }

  dynamic _bytesToString(Uint8List bytes) {
    for (final b in bytes) {
      if (b < 32 || b > 126) return PdfRawString(bytes.toList());
    }
    return String.fromCharCodes(bytes);
  }

  void _extractPageNodes(
      PdfIndirectReference nodeRef, List<Map<String, dynamic>> accumulator) {
    final nodeDict =
        resolveIndirectReference(nodeRef) as Map<String, dynamic>?;
    if (nodeDict == null) return;
    final nodeType = nodeDict['/Type']?.toString() ?? '';
    if (nodeType == '/Page') {
      accumulator.add(nodeDict);
    } else if (nodeType == '/Pages' && nodeDict.containsKey('/Kids')) {
      final kidsList = nodeDict['/Kids'];
      if (kidsList is List<dynamic>) {
        for (final kid in kidsList) {
          if (kid is PdfIndirectReference) _extractPageNodes(kid, accumulator);
        }
      }
    }
  }
}