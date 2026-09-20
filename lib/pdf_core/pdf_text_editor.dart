import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart' show ZLibEncoder;
import 'package:flutter/foundation.dart' show kDebugMode;

import '../pdf_core/object_parser.dart';
import '../pdf_core/pdf_value_serializer.dart';
import '../pdf_core/content_stream/cmap_parser.dart';
import '../pdf_core/content_stream/content_stream_analyzer.dart';
import '../pdf_core/content_stream/content_stream_editor.dart';
import '../pdf_core/content_stream/font_info.dart';
import 'document.dart';
import 'incremental_writer.dart';
import 'verifier.dart';

/// Font table + Form XObject table built from a resource dictionary.
class PageResources {
  final Map<String, FontInfo> fonts;
  final Map<String, FormXObject> forms;
  const PageResources(this.fonts, this.forms);

  static const empty =
      PageResources(<String, FontInfo>{}, <String, FormXObject>{});
}

class PdfTextEditor {
  final Uint8List fileBytes;
  final PdfDocumentEngine engine;

  PdfTextEditor(this.fileBytes, {String password = ''})
      : engine = PdfDocumentEngine(fileBytes, password: password);

  bool get isEncrypted => engine.decryptor != null;

  List<TextRun> extractPageRuns(int pageIndex, {bool raw = false}) {
    final pages = _walkPageRefs();
    if (pageIndex < 0 || pageIndex >= pages.length) return [];
    final page = pages[pageIndex].dict;
    final resources = _buildResources(page);
    final contentBytes = _readContentBytes(page);
    if (contentBytes == null) return [];

    final analyzer = ContentStreamAnalyzer(
      contentBytes,
      resources.fonts,
      forms: resources.forms,
    );
    return raw ? analyzer.analyze() : analyzer.analyzeLines();
  }

  Uint8List editRun({
    required int pageIndex,
    required TextRun run,
    required String newText,
    bool preserveWidth = true,
  }) {
    final pages = _walkPageRefs();
    if (pageIndex < 0 || pageIndex >= pages.length) {
      throw ArgumentError('Page index out of range');
    }
    final pageRef = pages[pageIndex].ref;
    final pageDict = pages[pageIndex].dict;

    final resources = _buildResources(pageDict);
    final contentBytes = _readContentBytes(pageDict);
    if (contentBytes == null) throw StateError('Page has no content');

    final newContent = ContentStreamEditor(contentBytes, resources.fonts)
        .replaceRun(run, newText, preserveWidth: preserveWidth);

    final newStreamId = engine.highestObjectId + 1;
    final highestId = newStreamId;

    final newPageDict = Map<String, dynamic>.from(pageDict);
    newPageDict['/Contents'] = PdfIndirectReference(newStreamId, 0);

    final payloads = <IncrementalUpdatePayload>[
      _contentStreamPayload(newStreamId, newContent),
      IncrementalUpdatePayload.fromString(
        pageRef.objectId,
        pageRef.generation,
        PdfValueSerializer.serialize(newPageDict),
      ),
    ];

    dynamic rootRef = engine.globalXrefTable.trailerDict['/Root'];
    if (rootRef is! PdfIndirectReference) {
      throw StateError('Source PDF has no /Root in its trailer');
    }

    return PdfIncrementalWriter.appendUpdates(
      fileBytes,
      payloads,
      _findLastStartXref(),
      highestId,
      rootRef: rootRef,
    );
  }

  Uint8List editRunVerified({
    required int pageIndex,
    required TextRun run,
    required String newText,
    bool preserveWidth = true,
  }) {
    final result = editRun(
      pageIndex: pageIndex,
      run: run,
      newText: newText,
      preserveWidth: preserveWidth,
    );
    if (kDebugMode) {
      final check = PdfOutputVerifier().verifyDocumentBytes(result);
      if (!check.isValid) {
        throw StateError(
            'In-place text edit produced an invalid PDF: ${check.report}');
      }
    }
    return result;
  }

  /// Build the font and form tables for [dict]. Works on a page dict or a
  /// Form XObject dict — both carry a `/Resources` map, and Form XObjects
  /// may recursively contain other forms.
  ///
  /// A depth guard prevents pathological self-referential forms from
  /// blowing the stack.
  PageResources _buildResources(Map<String, dynamic> dict, {int depth = 0}) {
    if (depth > 8) return PageResources.empty;

    dynamic resources = dict['/Resources'];
    if (resources is PdfIndirectReference) {
      resources = engine.resolveIndirectReference(resources);
    }
    if (resources is! Map<String, dynamic>) return PageResources.empty;

    final fonts = <String, FontInfo>{};
    final forms = <String, FormXObject>{};

    // ── Fonts ────────────────────────────────────────────────────────
    dynamic fontsDict = resources['/Font'];
    if (fontsDict is PdfIndirectReference) {
      fontsDict = engine.resolveIndirectReference(fontsDict);
    }
    if (fontsDict is Map) {
      fontsDict.forEach((key, value) {
        dynamic fontObj = value;
        if (fontObj is PdfIndirectReference) {
          fontObj = engine.resolveIndirectReference(fontObj);
        }
        if (fontObj is! Map<String, dynamic>) return;

        final info = FontInfo.fromFontDict(
            fontObj, (ref) => engine.resolveIndirectReference(ref));

        ToUnicodeCMap? cmap;
        final tu = fontObj['/ToUnicode'];
        if (tu is PdfIndirectReference) {
          final s = engine.resolveStream(tu);
          if (s != null) cmap = ToUnicodeCMap.parse(s.data);
        }

        fonts[key.toString()] = FontInfo(
          widths: info.widths,
          defaultWidth: info.defaultWidth,
          cmap: cmap,
          codeBytes: info.codeBytes,
          isSimpleWinAnsi: info.isSimpleWinAnsi,
        );
      });
    }

    // ── Form XObjects ───────────────────────────────────────────────
    dynamic xobjects = resources['/XObject'];
    if (xobjects is PdfIndirectReference) {
      xobjects = engine.resolveIndirectReference(xobjects);
    }
    if (xobjects is Map) {
      xobjects.forEach((key, value) {
        if (value is! PdfIndirectReference) return;
        final formDict = engine.resolveIndirectReference(value);
        if (formDict is! Map<String, dynamic>) return;
        if (formDict['/Subtype']?.toString() != '/Form') return;

        final stream = engine.resolveStream(value);
        if (stream == null) return;

        // Recurse: a form carries its own /Resources, which may itself
        // contain fonts and nested forms.
        final sub = _buildResources(formDict, depth: depth + 1);

        // /Matrix — six numbers, default identity if absent or malformed.
        final matrix = <double>[1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
        final m = formDict['/Matrix'];
        if (m is List && m.length >= 6) {
          for (int i = 0; i < 6; i++) {
            final v = m[i];
            matrix[i] = v is num ? v.toDouble() : matrix[i];
          }
        }

        forms['/' + key.toString()] = FormXObject(
          contentBytes: stream.data,
          fonts: sub.fonts,
          forms: sub.forms,
          matrix: matrix,
        );
      });
    }

    return PageResources(fonts, forms);
  }

  Uint8List? _readContentBytes(Map<String, dynamic> pageDict) {
    final chunks = <Uint8List>[];
    final contents = pageDict['/Contents'];

    if (contents is PdfIndirectReference) {
      final s = engine.resolveStream(contents);
      if (s == null) return null;
      chunks.add(s.data);
    } else if (contents is List) {
      for (final entry in contents) {
        if (entry is PdfIndirectReference) {
          final s = engine.resolveStream(entry);
          if (s != null) chunks.add(s.data);
        }
      }
    } else {
      return null;
    }

    if (chunks.isEmpty) return null;
    if (chunks.length == 1) return chunks.first;

    final total = chunks.fold<int>(0, (a, b) => a + b.length + 1);
    final out = Uint8List(total);
    int p = 0;
    for (final c in chunks) {
      out.setRange(p, p + c.length, c);
      p += c.length;
      out[p++] = 10;
    }
    return out;
  }

  IncrementalUpdatePayload _contentStreamPayload(int objectId, Uint8List raw) {
    final compressed = Uint8List.fromList(ZLibEncoder().encode(raw));
    final head = latin1.encode(
        '<< /Length ${compressed.length} /Filter /FlateDecode >>\nstream\n');
    final tail = latin1.encode('\nendstream');
    final body = BytesBuilder(copy: false)
      ..add(head)
      ..add(compressed)
      ..add(tail);
    return IncrementalUpdatePayload(objectId, 0, body.takeBytes());
  }

  List<({PdfIndirectReference ref, Map<String, dynamic> dict})>
      _walkPageRefs() {
    final result =
        <({PdfIndirectReference ref, Map<String, dynamic> dict})>[];
    dynamic rootRef = engine.globalXrefTable.trailerDict['/Root'];
    if (rootRef is! PdfIndirectReference) return result;
    final cat = engine.resolveIndirectReference(rootRef);
    if (cat is! Map<String, dynamic>) return result;
    final pagesRoot = cat['/Pages'];
    if (pagesRoot is! PdfIndirectReference) return result;

    void walk(PdfIndirectReference ref) {
      final node = engine.resolveIndirectReference(ref);
      if (node is! Map<String, dynamic>) return;
      final type = node['/Type']?.toString() ?? '';
      if (type == '/Page') {
        result.add((ref: ref, dict: node));
      } else if (type == '/Pages') {
        final kids = node['/Kids'];
        if (kids is List) {
          for (final kid in kids) {
            if (kid is PdfIndirectReference) walk(kid);
          }
        }
      }
    }

    walk(pagesRoot);
    return result;
  }

  int _findLastStartXref() {
    for (int i = fileBytes.length - 9; i >= 0; i--) {
      if (fileBytes[i] == 115 &&
          fileBytes[i + 1] == 116 &&
          fileBytes[i + 2] == 97 &&
          fileBytes[i + 3] == 114) {
        final s = String.fromCharCodes(fileBytes.sublist(i, i + 9));
        if (s == 'startxref') {
          int j = i + 9;
          while (j < fileBytes.length &&
              (fileBytes[j] == 32 ||
                  fileBytes[j] == 10 ||
                  fileBytes[j] == 13)) {
            j++;
          }
          final start = j;
          while (j < fileBytes.length &&
              fileBytes[j] >= 48 &&
              fileBytes[j] <= 57) {
            j++;
          }
          return int.parse(String.fromCharCodes(fileBytes.sublist(start, j)));
        }
      }
    }
    return 0;
  }
}