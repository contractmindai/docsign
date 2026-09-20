import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:archive/archive.dart' show ZLibEncoder;

import '../pdf_core/document.dart';
import '../pdf_core/filters.dart';
import '../pdf_core/incremental_writer.dart';
import '../pdf_core/lexer.dart';
import '../pdf_core/object_parser.dart';
import '../pdf_core/xref_parser.dart';
import '../pdf_core/content_stream/text_extractor.dart';

// ── Public types ──────────────────────────────────────────────────────────────

enum PdfDocumentKind { acroForm, xfaStatic, xfaDynamic, flat, unknown }

class PdfTextEdit {
  final String targetText;
  final String replacementText;
  final int? occurrenceIndex;
  const PdfTextEdit({
    required this.targetText,
    required this.replacementText,
    this.occurrenceIndex,
  });
}

class TextSearchResult {
  final String text;
  final Rectangle<double> bounds;
  final String fontRef;
  final double fontSize;
  const TextSearchResult({
    required this.text,
    required this.bounds,
    required this.fontRef,
    required this.fontSize,
  });
}

class PdfContentEditResult {
  final PdfContentEditor? editor;
  final String? failureReason;
  final PdfDocumentKind kind;
  const PdfContentEditResult.ok(this.editor, this.kind)
      : failureReason = null;
  const PdfContentEditResult.unsupported(this.failureReason, this.kind)
      : editor = null;
  bool get isSupported => editor != null;
}

// ── Main class ────────────────────────────────────────────────────────────────

class PdfContentEditor {
  final Uint8List _originalBytes;
  final PdfDocumentEngine _engine;
  final PdfDocumentKind kind;
  final List<IncrementalUpdatePayload> _pendingUpdates = [];
  int _nextObjectId;

  PdfContentEditor._(
      this._originalBytes, this._engine, this.kind, this._nextObjectId);

  static PdfContentEditResult open(Uint8List bytes) {
    final PdfDocumentEngine engine;
    try {
      engine = PdfDocumentEngine(bytes);
    } catch (e) {
      return PdfContentEditResult.unsupported(
          'Cannot parse PDF: $e', PdfDocumentKind.unknown);
    }
    if (!engine.hasUsableXref) {
      return PdfContentEditResult.unsupported(
          'Cannot read cross-reference table — may be encrypted.',
          PdfDocumentKind.unknown);
    }
    final catalog = engine.catalog;
    if (catalog == null) {
      return PdfContentEditResult.unsupported(
          'Cannot locate document catalog.', PdfDocumentKind.unknown);
    }
    for (final id in engine.globalXrefTable.offsets.keys) {
      try { engine.resolveObjectId(id); } catch (_) {}
    }
    for (final id in engine.globalXrefTable.compressedLocations.keys) {
      try { engine.resolveObjectId(id); } catch (_) {}
    }
    final kind = _detectKind(catalog, engine);
    if (kind == PdfDocumentKind.xfaDynamic) {
      return PdfContentEditResult.unsupported(
          'Dynamic XFA forms require Adobe LiveCycle and cannot be edited here.',
          kind);
    }
    return PdfContentEditResult.ok(
      PdfContentEditor._(bytes, engine, kind, engine.highestObjectId + 1),
      kind,
    );
  }

  List<TextSearchResult> findText(String searchText, {int pageIndex = 0}) {
    final content = _decompressedPageContent(pageIndex);
    if (content == null) return [];
    return PdfTextExtractor()
        .extractChunks(content)
        .where((c) => c.text.contains(searchText))
        .map((c) => TextSearchResult(
              text: c.text,
              bounds: c.bounds,
              fontRef: c.fontReference,
              fontSize: c.fontSize,
            ))
        .toList();
  }

  List<TextSearchResult> extractAllText({int pageIndex = 0}) {
    final content = _decompressedPageContent(pageIndex);
    if (content == null) return [];
    return PdfTextExtractor()
        .extractChunks(content)
        .map((c) => TextSearchResult(
              text: c.text,
              bounds: c.bounds,
              fontRef: c.fontReference,
              fontSize: c.fontSize,
            ))
        .toList();
  }

  int get pageCount => _engine.walkPageTree().length;

  // ── Text editing ─────────────────────────────────────────────────────────

  int editText(PdfTextEdit edit, {int pageIndex = 0}) {
    final content = _decompressedPageContent(pageIndex);
    if (content == null) return 0;
    final chunks = PdfTextExtractor().extractChunks(content);
    final matches = chunks.where((c) => c.text.contains(edit.targetText)).toList();
    if (matches.isEmpty) return 0;
    final overlayOps = <String>[];
    int count = 0;
    for (int i = 0; i < matches.length; i++) {
      if (edit.occurrenceIndex != null && edit.occurrenceIndex != i) continue;
      final chunk = matches[i];
      final bounds = chunk.bounds;
      final double targetRatio = edit.targetText.length / chunk.text.length;
      final double targetWidth = bounds.width * targetRatio;
      final double padding = chunk.fontSize * 0.1;
      final coverRect = Rectangle<double>(
        bounds.left - padding,
        bounds.bottom - padding,
        targetWidth + padding * 2,
        bounds.height + padding * 2,
      );
      final String font = chunk.fontReference.isNotEmpty
          ? chunk.fontReference
          : '/Helv';
      final double fs = chunk.fontSize > 0 ? chunk.fontSize : 10.0;
      overlayOps.add(_whiteBox(coverRect));
      overlayOps.add(_textOp(edit.replacementText, bounds.left,
          bounds.bottom + fs * 0.15, font, fs));
      count++;
    }
    if (overlayOps.isNotEmpty) {
      _appendOverlay(pageIndex, overlayOps, _fontRefsFrom(matches));
    }
    return count;
  }

  Map<String, int> editAll(List<PdfTextEdit> edits, {int pageIndex = 0}) {
    final content = _decompressedPageContent(pageIndex);
    if (content == null) {
      return {for (final e in edits) e.targetText: 0};
    }
    final chunks = PdfTextExtractor().extractChunks(content);
    final overlayOps = <String>[];
    final results = <String, int>{};
    final usedFontRefs = <String>{};
    for (final edit in edits) {
      final matches = chunks.where((c) => c.text.contains(edit.targetText)).toList();
      results[edit.targetText] = 0;
      for (int i = 0; i < matches.length; i++) {
        if (edit.occurrenceIndex != null && edit.occurrenceIndex != i) continue;
        final chunk = matches[i];
        final bounds = chunk.bounds;
        final double fs = chunk.fontSize > 0 ? chunk.fontSize : 10.0;
        final String font =
            chunk.fontReference.isNotEmpty ? chunk.fontReference : '/Helv';
        final double padding = fs * 0.1;
        final coverRect = Rectangle<double>(
          bounds.left - padding,
          bounds.bottom - padding,
          bounds.width + padding * 2,
          bounds.height + padding * 2,
        );
        overlayOps.add(_whiteBox(coverRect));
        overlayOps.add(_textOp(edit.replacementText, bounds.left,
            bounds.bottom + fs * 0.15, font, fs));
        usedFontRefs.add(font);
        results[edit.targetText] = (results[edit.targetText] ?? 0) + 1;
      }
    }
    if (overlayOps.isNotEmpty) {
      _appendOverlay(pageIndex, overlayOps, usedFontRefs);
    }
    return results;
  }

  void placeText({
    required int pageIndex,
    required String text,
    required double x,
    required double y,
    double fontSize = 10.0,
    String fontRef = '/Helv',
    Rectangle<double>? coverRect,
  }) {
    final ops = <String>[];
    if (coverRect != null) ops.add(_whiteBox(coverRect));
    ops.add(_textOp(text, x, y, fontRef, fontSize));
    _appendOverlay(pageIndex, ops, {fontRef});
  }

  // ── Overlay image ─────────────────────────────────────────────────────────

  bool overlayImage({
    required int pageIndex,
    required Uint8List pngBytes,
    required Rectangle<double> rect,
  }) {
    final image = img.decodePng(pngBytes);
    if (image == null) return false;

    final fieldWidth = rect.width;
    final fieldHeight = rect.height;

    // Convert to RGB
    final rgbData = Uint8List(image.width * image.height * 3);
    int idx = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        rgbData[idx++] = pixel.r.toInt();
        rgbData[idx++] = pixel.g.toInt();
        rgbData[idx++] = pixel.b.toInt();
      }
    }
    final compressed = ZLibEncoder().encode(rgbData);

    // Image XObject (resource name: /ImgXXX)
    final int imageXObjId = _nextObjectId++;
    final List<int> imageStream = [
      ..._a('<< /Type /XObject /Subtype /Image /Width ${image.width} /Height ${image.height} '),
      ..._a('/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${compressed.length} >>\n'),
      ..._a('stream\n'),
      ...compressed,
      ..._a('\nendstream'),
    ];
    _pendingUpdates.add(IncrementalUpdatePayload(imageXObjId, 0, _bytesToStr(imageStream)));

    // Form XObject (resource name: /FmXXX)
    final int formXObjId = _nextObjectId++;
    final String formContent =
        'q\n'
        '1 1 1 rg\n'
        '0 0 ${fieldWidth} ${fieldHeight} re f\n'
        'q ${fieldWidth} 0 0 ${fieldHeight} 0 0 cm /Img$imageXObjId Do Q\n'
        'Q';
    final List<int> formStream = [
      ..._a('<< /Type /XObject /Subtype /Form /BBox [0 0 ${fieldWidth} ${fieldHeight}] '),
      ..._a('/Resources << /XObject << /Img$imageXObjId $imageXObjId 0 R >> >> '),
      ..._a('/Length ${formContent.length} >>\nstream\n'),
      ..._a(formContent),
      ..._a('\nendstream'),
    ];
    _pendingUpdates.add(IncrementalUpdatePayload(formXObjId, 0, _bytesToStr(formStream)));

    // Content stream overlay
    final String content =
        'q\n'
        '1 1 1 rg\n'
        '${rect.left} ${rect.bottom} ${fieldWidth} ${fieldHeight} re f\n'
        'q\n'
        '1 0 0 1 ${rect.left} ${rect.bottom} cm\n'
        '/Fm$formXObjId Do\n'
        'Q\n'
        'Q';
    final List<int> contentBytes = utf8.encode(content);
    final int contentId = _nextObjectId++;
    final List<int> contentStream = [
      ..._a('<< /Length ${contentBytes.length} >>\nstream\n'),
      ...contentBytes,
      ..._a('\nendstream'),
    ];
    _pendingUpdates.add(IncrementalUpdatePayload(contentId, 0, _bytesToStr(contentStream)));

    // Update page dict
    final pageDict = _pageDict(pageIndex);
    if (pageDict == null) return false;
    final pageObjId = _pageObjectId(pageIndex);
    if (pageObjId < 0) return false;

    final updated = Map<String, dynamic>.from(pageDict);

    // /Contents -> array
    final existingContents = pageDict['/Contents'];
    if (existingContents is PdfIndirectReference) {
      updated['/Contents'] = _PdfRaw(
          '[$contentId 0 R ${existingContents.objectId} ${existingContents.generation} R]');
    } else if (existingContents is List) {
      final refs = existingContents.map((e) {
        if (e is PdfIndirectReference) return '${e.objectId} ${e.generation} R';
        return e.toString();
      }).join(' ');
      updated['/Contents'] = _PdfRaw('[$refs $contentId 0 R]');
    } else {
      updated['/Contents'] = _PdfRaw('[$contentId 0 R]');
    }

    // /Resources /XObject – add the form XObject with its resource name
    final existingResources = _resolveValue(pageDict['/Resources']) as Map<String, dynamic>? ?? {};
    final newResources = Map<String, dynamic>.from(existingResources);
    final existingXObj = newResources['/XObject'] as Map<String, dynamic>? ?? {};
    final newXObj = Map<String, dynamic>.from(existingXObj);
    newXObj['/Fm$formXObjId'] = _PdfRaw('$formXObjId 0 R');
    newResources['/XObject'] = _PdfRaw(_serializeDict(newXObj));
    updated['/Resources'] = _PdfRaw(_serializeDict(newResources));

    _pendingUpdates.add(IncrementalUpdatePayload(pageObjId, 0, _serializeDict(updated)));
    return true;
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  bool get hasPendingChanges => _pendingUpdates.isNotEmpty;

  Uint8List save() {
    if (_pendingUpdates.isEmpty) return _originalBytes;

    final xrefOffset = PdfXrefParser(_originalBytes).findLastStartXref();

    // The incremental trailer must re-declare /Root. Without it, some
    // readers (Acrobat Windows in particular) refuse to open the appended
    // file because they won't follow /Prev to reach the original trailer.
    final rootRef = _engine.globalXrefTable.trailerDict['/Root'];
    if (rootRef is! PdfIndirectReference) {
      throw StateError('Source PDF has no /Root in its trailer');
    }

    return PdfIncrementalWriter.appendUpdates(
      _originalBytes,
      _pendingUpdates,
      xrefOffset,
      _nextObjectId - 1,
      rootRef: rootRef,
    );
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  void _appendOverlay(int pageIndex, List<String> ops, Set<String> fontRefs) {
    final pageDict = _pageDict(pageIndex);
    if (pageDict == null) return;
    final pageDictObjId = _pageObjectId(pageIndex);
    if (pageDictObjId < 0) return;

    final String body = 'q\r\n${ops.join('\r\n')}\r\nQ\r\n';
    final List<int> bodyBytes = utf8.encode(body);
    final String resourceDict = _buildResourceDict(fontRefs, pageDict);
    final int overlayObjId = _nextObjectId++;
    final String streamObj =
        '<< /Type /XObject /Subtype /Form\r\n'
        '   /BBox [${_pageBBox(pageDict)}]\r\n'
        '   /Resources $resourceDict\r\n'
        '   /Length ${bodyBytes.length} >>\r\n'
        'stream\r\n$body\r\nendstream';
    _pendingUpdates.add(IncrementalUpdatePayload(overlayObjId, 0, streamObj));

    final updated = Map<String, dynamic>.from(pageDict);
    updated['/Contents'] = _PdfRaw(_appendToContents(pageDict['/Contents'], overlayObjId));
    _pendingUpdates.add(IncrementalUpdatePayload(pageDictObjId, 0, _serializeDict(updated)));
  }

  String _buildResourceDict(Set<String> fontRefs, Map<String, dynamic> pageDict) {
    final buf = StringBuffer('<< /Font <<');
    buf.write(' /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    final pageResources = _resolveValue(pageDict['/Resources']);
    if (pageResources is Map<String, dynamic>) {
      final pageFonts = _resolveValue(pageResources['/Font']);
      if (pageFonts is Map<String, dynamic>) {
        for (final ref in fontRefs) {
          if (ref == '/Helv') continue;
          final fontKey = ref.startsWith('/') ? ref.substring(1) : ref;
          final fontVal = pageFonts[ref] ?? pageFonts['/$fontKey'];
          if (fontVal is PdfIndirectReference) {
            buf.write(' $ref ${fontVal.objectId} ${fontVal.generation} R');
          }
        }
      }
    }
    buf.write(' >> >>');
    return buf.toString();
  }

  String _pageBBox(Map<String, dynamic> pageDict) {
    final mb = _resolveValue(pageDict['/MediaBox']);
    if (mb is List && mb.length == 4) {
      return mb.map((v) => v.toString()).join(' ');
    }
    return '0 0 612 792';
  }

  Uint8List? _decompressedPageContent(int pageIndex) {
    final pageDict = _pageDict(pageIndex);
    if (pageDict == null) return null;
    final contents = pageDict['/Contents'];
    if (contents is PdfIndirectReference) {
      return _streamBytes(contents.objectId);
    }
    if (contents is List) {
      final combined = BytesBuilder();
      for (final ref in contents) {
        if (ref is PdfIndirectReference) {
          final part = _streamBytes(ref.objectId);
          if (part != null) {
            combined.add(part);
            combined.add([32]);
          }
        }
      }
      return combined.isEmpty ? null : combined.toBytes();
    }
    return null;
  }

  Uint8List? _streamBytes(int objId) {
    try {
      final int? offset = _engine.globalXrefTable.offsets[objId];
      if (offset == null) return null;
      final lexer = PdfLexer(_originalBytes);
      lexer.seek(offset);
      lexer.nextToken();
      lexer.nextToken();
      lexer.nextToken();
      final parser = PdfObjectParser(lexer, _engine.globalXrefTable.offsets);
      final dict = parser.parseObject();
      if (dict is! Map<String, dynamic>) return null;
      final kw = lexer.nextToken();
      if (kw.type != PdfTokenType.keyword || kw.value != 'stream') return null;
      int pos = lexer.offset;
      if (pos < _originalBytes.length && _originalBytes[pos] == 13) pos++;
      if (pos < _originalBytes.length && _originalBytes[pos] == 10) pos++;
      final int len = (dict['/Length'] as num?)?.toInt() ?? 0;
      if (len <= 0 || pos + len > _originalBytes.length) return null;
      final Uint8List raw = _originalBytes.sublist(pos, pos + len);
      final filters = _filtersOf(dict['/Filter']);
      return filters.isEmpty ? raw : PdfFilterDecoder.decodeStream(raw, filters);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _pageDict(int pageIndex) {
    final pages = _engine.walkPageTree();
    if (pageIndex < 0 || pageIndex >= pages.length) return null;
    return pages[pageIndex];
  }

  int _pageObjectId(int pageIndex) {
    final pageIds = <int>[];
    for (final id in _engine.globalXrefTable.offsets.keys) {
      final obj = _engine.resolvedObjectsCache[id];
      if (obj is Map<String, dynamic> && obj['/Type']?.toString() == '/Page') {
        pageIds.add(id);
      }
    }
    for (final id in _engine.globalXrefTable.compressedLocations.keys) {
      if (pageIds.contains(id)) continue;
      final obj = _engine.resolvedObjectsCache[id];
      if (obj is Map<String, dynamic> && obj['/Type']?.toString() == '/Page') {
        pageIds.add(id);
      }
    }
    pageIds.sort();
    if (pageIndex < 0 || pageIndex >= pageIds.length) return -1;
    return pageIds[pageIndex];
  }

  dynamic _resolveValue(dynamic v) {
    if (v is PdfIndirectReference) {
      return _engine.resolveIndirectReference(v);
    }
    return v;
  }

  String _whiteBox(Rectangle<double> r) {
    final x = _f(r.left);
    final y = _f(r.bottom);
    final w = _f(r.width);
    final h = _f(r.height);
    return 'q 1 g 1 G $x $y $w $h re f Q';
  }

  String _textOp(String text, double x, double y, String font, double fs) {
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('(', '\\(')
        .replaceAll(')', '\\)');
    return 'BT $font ${_f(fs)} Tf 0 g ${_f(x)} ${_f(y)} Td ($escaped) Tj ET';
  }

  String _appendToContents(dynamic existing, int newId) {
    final newRef = '$newId 0 R';
    if (existing == null) return '[$newRef]';
    if (existing is PdfIndirectReference) {
      return '[${existing.objectId} ${existing.generation} R $newRef]';
    }
    if (existing is List) {
      final refs = existing.map((e) {
        if (e is PdfIndirectReference) return '${e.objectId} ${e.generation} R';
        return e.toString();
      }).join(' ');
      return '[$refs $newRef]';
    }
    return '[$newRef]';
  }

  String _serializeDict(Map<String, dynamic> dict) {
    final buf = StringBuffer('<<\r\n');
    dict.forEach((k, v) => buf.write('  $k ${_sv(v)}\r\n'));
    buf.write('>>');
    return buf.toString();
  }

  String _sv(dynamic v) {
    if (v is _PdfRaw) return v.raw;
    if (v is PdfIndirectReference) return '${v.objectId} ${v.generation} R';
    if (v is num) return _f(v.toDouble());
    if (v is bool) return v.toString();
    if (v is String) {
      if (v.startsWith('/') || v.startsWith('<') || v.startsWith('[') ||
          v.startsWith('(')) return v;
      return '($v)';
    }
    if (v is List) return '[${v.map(_sv).join(' ')}]';
    if (v is Map<String, dynamic>) return _serializeDict(v);
    return 'null';
  }

  String _f(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(3);

  List<String> _filtersOf(dynamic v) {
    if (v == null) return [];
    if (v is String) return [v];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  Set<String> _fontRefsFrom(List<ExtractedTextChunk> chunks) {
    final refs = <String>{};
    for (final c in chunks) {
      if (c.fontReference.isNotEmpty) refs.add(c.fontReference);
    }
    return refs;
  }

  static PdfDocumentKind _detectKind(
      Map<String, dynamic> catalog, PdfDocumentEngine engine) {
    final acroRef = catalog['/AcroForm'];
    Map<String, dynamic>? acro;
    if (acroRef is Map<String, dynamic>) acro = acroRef;
    if (acroRef is PdfIndirectReference) {
      final r = engine.resolveIndirectReference(acroRef);
      if (r is Map<String, dynamic>) acro = r;
    }
    if (acro == null) return PdfDocumentKind.flat;
    if (!acro.containsKey('/XFA')) return PdfDocumentKind.acroForm;
    final xfa = acro['/XFA'];
    if (xfa is List) {
      for (final item in xfa) {
        if (item.toString().toLowerCase().replaceAll('/', '') == 'config') {
          return PdfDocumentKind.xfaDynamic;
        }
      }
    }
    return PdfDocumentKind.xfaStatic;
  }

  static String _bytesToStr(List<int> bytes) => String.fromCharCodes(bytes);
  static List<int> _a(String s) => s.codeUnits;
}

class _PdfRaw {
  final String raw;
  const _PdfRaw(this.raw);
}