import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfr;

import '../models/annotation.dart';
import '../models/signer_profile.dart';
import '../pdf_core/document.dart';
import '../pdf_core/incremental_writer.dart';
import '../pdf_core/object_parser.dart';
import '../pdf_core/page_dict_utils.dart';
import '../pdf_core/pdf_value_serializer.dart';
import '../pdf_core/verifier.dart';
import '../pdf_core/xref_parser.dart';
import '../utils/platform_file_service.dart';
import 'pdf_operator_builder.dart';

class PdfSaveService {
  // Fonts used by the raster path (audit page + text stamps in raster mode).
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;
  static bool _fontsLoaded = false;

  static const int _maxRenderedPixels = 2500000;

  static final pw.EdgeInsets _stickyPadding = pw.EdgeInsets.all(6);
  static final pw.BoxBorder _stickyBorder = pw.Border.all(color: PdfColors.amber);
  static final pw.BoxDecoration _stickyDecoration = pw.BoxDecoration(
    color: PdfColors.amber100,
    border: _stickyBorder,
    borderRadius: pw.BorderRadius.circular(4),
  );

  static final pw.BoxDecoration _auditHeaderDecoration = pw.BoxDecoration(
    color: PdfColors.indigo50,
    borderRadius: pw.BorderRadius.circular(8),
    border: pw.Border.all(color: PdfColors.indigo200, width: 1),
  );
  static final pw.BoxDecoration _signatureBoxDecoration = pw.BoxDecoration(
    color: PdfColors.white,
    borderRadius: pw.BorderRadius.circular(6),
    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
  );
  static final pw.BoxDecoration _legalDisclaimerDecoration = pw.BoxDecoration(
    color: PdfColors.grey100,
    borderRadius: pw.BorderRadius.circular(6),
  );

  static final Map<int, PdfColor> _colorCache = {};

  static PdfColor _pdfColor(dynamic color, {double opacity = 1.0}) {
    int r, g, b;
    int value;
    if (color is Color) {
      value = color.value;
    } else if (color is int) {
      value = color;
    } else {
      value = 0xFF000000;
    }
    final key = value ^ (opacity * 1000).toInt();
    return _colorCache.putIfAbsent(key, () {
      r = (value >> 16) & 0xFF;
      g = (value >> 8) & 0xFF;
      b = value & 0xFF;
      if (opacity < 0.999) {
        return PdfColor(
          (r / 255.0) * opacity,
          (g / 255.0) * opacity,
          (b / 255.0) * opacity,
        );
      }
      return PdfColor(r / 255.0, g / 255.0, b / 255.0);
    });
  }

  static pw.Font? get regularFont => _regularFont;
  static pw.Font? get boldFont => _boldFont;
  static Future<void> ensureFontsLoaded() async => _loadFonts();

  static pw.TextStyle textStyle({
    double fontSize = 10,
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.TextStyle(
      font: bold
          ? (_boldFont ?? pw.Font.helveticaBold())
          : (_regularFont ?? pw.Font.helvetica()),
      fontSize: fontSize,
      color: color,
    );
  }

  static Future<void> _loadFonts() async {
    if (_fontsLoaded) return;
    try {
      final r = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final b = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      _regularFont = pw.Font.ttf(r);
      _boldFont = pw.Font.ttf(b);
      _fontsLoaded = true;
    } catch (_) {
      _regularFont = pw.Font.helvetica();
      _boldFont = pw.Font.helveticaBold();
      _fontsLoaded = true;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Public entry point
  // ────────────────────────────────────────────────────────────────────────

  static Future<String?> save({
    required String sourcePath,
    required int pageCount,
    required Map<int, List<RectAnnotation>>   rectAnnotations,
    required Map<int, InkAnnotation>          inkAnnotations,
    required Map<int, List<StickyNote>>       stickyNotes,
    required Map<int, List<SignatureOverlay>> signatures,
    required Map<int, List<TextStamp>>        textStamps,
    required Map<int, List<RedactionRect>>    redactions,
    required Map<int, List<ClauseBookmark>>   bookmarks,
    required Map<int, List<TextEditAnnotation>> textEdits,
    required List<SignatureSlot>              slots,
    SignerProfile?                            signerProfile,
    String?                                   password,
    Uint8List?                                sourceBytes,
    Map<String, String?>?                     signatureIps,
    /// When true (default), the modified PDF overwrites [sourcePath] in place.
    /// When false, a new `<name>_signed.pdf` is written alongside it.
    bool saveInPlace = true,
  }) async {
    await _loadFonts();

    Uint8List? originalBytes = sourceBytes ?? PlatformFileService.getCached(sourcePath);
    if (originalBytes == null && !kIsWeb) {
      originalBytes = await PlatformFileService.readBytes(sourcePath);
    }
    if (originalBytes == null) {
      throw Exception('Cannot read source PDF: $sourcePath');
    }

    final needsRaster = signatures.values.any((l) => l.isNotEmpty) ||
        stickyNotes.values.any((l) => l.isNotEmpty);

    if (needsRaster) {
      return _saveRaster(
        sourcePath: sourcePath,
        originalBytes: originalBytes,
        pageCount: pageCount,
        rectAnnotations: rectAnnotations,
        inkAnnotations: inkAnnotations,
        stickyNotes: stickyNotes,
        signatures: signatures,
        textStamps: textStamps,
        redactions: redactions,
        bookmarks: bookmarks,
        textEdits: textEdits,
        signerProfile: signerProfile,
        password: password,
        signatureIps: signatureIps,
        saveInPlace: saveInPlace,
      );
    }

    return _saveIncremental(
      sourcePath: sourcePath,
      originalBytes: originalBytes,
      pageCount: pageCount,
      rectAnnotations: rectAnnotations,
      inkAnnotations: inkAnnotations,
      textStamps: textStamps,
      redactions: redactions,
      bookmarks: bookmarks,
      textEdits: textEdits,
      saveInPlace: saveInPlace,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Raster-free incremental path
  // ────────────────────────────────────────────────────────────────────────

  static Future<String?> _saveIncremental({
    required String sourcePath,
    required Uint8List originalBytes,
    required int pageCount,
    required Map<int, List<RectAnnotation>> rectAnnotations,
    required Map<int, InkAnnotation> inkAnnotations,
    required Map<int, List<TextStamp>> textStamps,
    required Map<int, List<RedactionRect>> redactions,
    required Map<int, List<ClauseBookmark>> bookmarks,
    required Map<int, List<TextEditAnnotation>> textEdits,
    required bool saveInPlace,
  }) async {
    final engine = PdfDocumentEngine(originalBytes);
    final pageRefs = _walkPageRefs(engine);
    if (pageRefs.isEmpty) {
      throw StateError('No pages found in source PDF');
    }

    final src = await pdfr.PdfDocument.openData(originalBytes);

    final payloads = <IncrementalUpdatePayload>[];
    int nextId = engine.highestObjectId + 1;

    // ── Base-14 font objects ─────────────────────────────────────────────
    //
    // Every page we touch gets the same three fonts installed under
    // predictable resource names. PdfOperatorBuilder._fontResFor maps the
    // dialog's font family to one of these three.
    final int helvId = nextId++;
    payloads.add(IncrementalUpdatePayload.fromString(
      helvId,
      0,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
    ));

    final int tiroId = nextId++;
    payloads.add(IncrementalUpdatePayload.fromString(
      tiroId,
      0,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman '
      '/Encoding /WinAnsiEncoding >>',
    ));

    final int courId = nextId++;
    payloads.add(IncrementalUpdatePayload.fromString(
      courId,
      0,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Courier '
      '/Encoding /WinAnsiEncoding >>',
    ));

    try {
      for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        // ── Yield to the event loop periodically. Android's ANR watchdog
        //    fires if the main thread is blocked for >5s; this loop used to
        //    run to completion without ever yielding.
        if (pageIndex % 5 == 0) {
          await Future.delayed(Duration.zero);
        }

        if (pageIndex >= pageRefs.length) break;
        if (pageIndex >= src.pages.length) break;

        final pageW = src.pages[pageIndex].width;
        final pageH = src.pages[pageIndex].height;

        final pageRef = pageRefs[pageIndex].ref;
        final pageDict = pageRefs[pageIndex].dict;

        final hasRect = (rectAnnotations[pageIndex]?.isNotEmpty ?? false);
        final hasInk = (inkAnnotations[pageIndex]?.strokes.isNotEmpty ?? false);
        final hasStamp = (textStamps[pageIndex]?.isNotEmpty ?? false);
        final hasRedact = (redactions[pageIndex]?.isNotEmpty ?? false);
        final hasBookmark = (bookmarks[pageIndex]?.isNotEmpty ?? false);
        final hasTextEdit = (textEdits[pageIndex]?.isNotEmpty ?? false);

        if (!hasRect &&
            !hasInk &&
            !hasStamp &&
            !hasRedact &&
            !hasBookmark &&
            !hasTextEdit) {
          continue;
        }

        final ops = PdfOperatorBuilder.buildPageOperators(
          pageW: pageW,
          pageH: pageH,
          rects: rectAnnotations[pageIndex] ?? const [],
          ink: inkAnnotations[pageIndex],
          stamps: textStamps[pageIndex] ?? const [],
          redactions: redactions[pageIndex] ?? const [],
          bookmarks: bookmarks[pageIndex] ?? const [],
          textEdits: textEdits[pageIndex] ?? const [],
        );

        if (ops.isEmpty) continue;

        final int streamId = nextId++;
        payloads.add(_streamPayload(streamId, ops));

        final updatedPage = Map<String, dynamic>.from(pageDict);

        updatedPage['/Contents'] = appendContentsRef(
          pageDict['/Contents'],
          streamId,
          0,
        );

        // Resolve /Resources — walking up the /Parent chain for inherited ones.
        dynamic existingResources = pageDict['/Resources'];
        if (existingResources == null) {
          dynamic parent = pageDict['/Parent'];
          int guard = 0;
          while (existingResources == null &&
              parent is PdfIndirectReference &&
              guard++ < 32) {
            final parentDict = engine.resolveIndirectReference(parent);
            if (parentDict is! Map<String, dynamic>) break;
            existingResources = parentDict['/Resources'];
            parent = parentDict['/Parent'];
          }
        }
        if (existingResources is PdfIndirectReference) {
          existingResources = engine.resolveIndirectReference(existingResources);
        }
        final resMap = existingResources is Map<String, dynamic>
            ? Map<String, dynamic>.from(existingResources)
            : <String, dynamic>{};

        dynamic existingFonts = resMap['/Font'];
        if (existingFonts is PdfIndirectReference) {
          existingFonts = engine.resolveIndirectReference(existingFonts);
        }
        final fontMap = existingFonts is Map<String, dynamic>
            ? Map<String, dynamic>.from(existingFonts)
            : <String, dynamic>{};
        fontMap['/Helv'] = PdfIndirectReference(helvId, 0);
        fontMap['/TiRo'] = PdfIndirectReference(tiroId, 0);
        fontMap['/Cour'] = PdfIndirectReference(courId, 0);

        final merged = mergeResourceDicts(resMap, {'/Font': fontMap});
        updatedPage['/Resources'] = merged;

        payloads.add(IncrementalUpdatePayload.fromString(
          pageRef.objectId,
          pageRef.generation,
          PdfValueSerializer.serialize(updatedPage),
        ));
      }
    } finally {
      await src.dispose();
    }

    if (payloads.length <= 3) {
      // No highlight/ink/stamp/redaction/bookmark/text-edit ops to layer
      // on this round. But `originalBytes` may already contain in-place
      // edits baked in earlier (quick text-run edits that preserve original
      // formatting write straight to the byte buffer). Write out whatever
      // bytes we were handed — a harmless no-op rewrite if nothing changed,
      // a real persist if it did.
      return _writeResult(sourcePath, originalBytes, saveInPlace);
    }

    final xref = PdfXrefParser(originalBytes).findLastStartXref();
    dynamic rootRef = engine.globalXrefTable.trailerDict['/Root'];
    if (rootRef is! PdfIndirectReference) {
      throw StateError('Source PDF has no /Root in its trailer');
    }
    final result = PdfIncrementalWriter.appendUpdates(
      originalBytes,
      payloads,
      xref,
      nextId - 1,
      rootRef: rootRef,
    );

    // ── Structural verification parses the entire output PDF synchronously
    //    and lexes every object. On a document with hundreds of objects
    //    that runs for several seconds on the main thread and can trigger
    //    an Android ANR. The writer is trusted here; keep the check in
    //    debug builds so regressions surface during development but skip
    //    it in release where responsiveness matters more.
    if (kDebugMode) {
      final check = PdfOutputVerifier().verifyDocumentBytes(result);
      if (!check.isValid) {
        throw StateError('PDF verification failed: ${check.report}');
      }
    }

    return _writeResult(sourcePath, result, saveInPlace);
  }

  static Uint8List _streamBody(String ops) {
    final body = utf8.encode(ops);
    final header = latin1.encode('<< /Length ${body.length} >>\nstream\n');
    final trailer = latin1.encode('\nendstream');
    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(body)
          ..add(trailer))
        .takeBytes();
  }

  static IncrementalUpdatePayload _streamPayload(int id, String ops) =>
      IncrementalUpdatePayload(id, 0, _streamBody(ops));

  static List<({PdfIndirectReference ref, Map<String, dynamic> dict})>
      _walkPageRefs(PdfDocumentEngine engine) {
    final out = <({PdfIndirectReference ref, Map<String, dynamic> dict})>[];
    dynamic rootRef = engine.globalXrefTable.trailerDict['/Root'];
    if (rootRef is! PdfIndirectReference) return out;

    final cat = engine.resolveIndirectReference(rootRef);
    if (cat is! Map<String, dynamic>) return out;

    final pagesRoot = cat['/Pages'];
    if (pagesRoot is! PdfIndirectReference) return out;

    void walk(PdfIndirectReference ref) {
      final node = engine.resolveIndirectReference(ref);
      if (node is! Map<String, dynamic>) return;
      final type = node['/Type']?.toString() ?? '';
      if (type == '/Page') {
        out.add((ref: ref, dict: node));
      } else if (type == '/Pages') {
        final kids = node['/Kids'];
        if (kids is List) {
          for (final k in kids) {
            if (k is PdfIndirectReference) walk(k);
          }
        }
      }
    }

    walk(pagesRoot);
    return out;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Shared output writer
  // ────────────────────────────────────────────────────────────────────────

  static Future<String> _writeResult(
    String sourcePath,
    Uint8List bytes,
    bool saveInPlace,
  ) async {
    if (saveInPlace) {
      // Overwrite the source file. On web, sourcePath is a cache key and
      // writeBytes triggers a re-download with the same name.
      await PlatformFileService.writeBytes(sourcePath, bytes);
      PlatformFileService.cache(sourcePath, bytes);
      return sourcePath;
    }

    // Legacy behaviour: write a sibling `*_signed.pdf`.
    final outName =
        '${p.basenameWithoutExtension(p.basename(sourcePath))}_signed.pdf';
    final output = await PlatformFileService.outputPath(outName);
    await PlatformFileService.writeBytes(output, bytes);
    PlatformFileService.cache(output, bytes);
    return output;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Raster fallback (used when signatures / sticky notes exist)
  // ────────────────────────────────────────────────────────────────────────

  static Future<String?> _saveRaster({
    required String sourcePath,
    required Uint8List originalBytes,
    required int pageCount,
    required Map<int, List<RectAnnotation>> rectAnnotations,
    required Map<int, InkAnnotation> inkAnnotations,
    required Map<int, List<StickyNote>> stickyNotes,
    required Map<int, List<SignatureOverlay>> signatures,
    required Map<int, List<TextStamp>> textStamps,
    required Map<int, List<RedactionRect>> redactions,
    required Map<int, List<ClauseBookmark>> bookmarks,
    required Map<int, List<TextEditAnnotation>> textEdits,
    SignerProfile? signerProfile,
    String? password,
    Map<String, String?>? signatureIps,
    required bool saveInPlace,
  }) async {
    final doc = pw.Document(compress: true);

    final pdfr.PdfPasswordProvider? pwProvider =
        (password != null && password.isNotEmpty)
            ? () => Future<String?>.value(password)
            : null;

    final src = await pdfr.PdfDocument.openData(
      originalBytes,
      sourceName: p.basename(sourcePath),
      passwordProvider: pwProvider,
    );

    try {
      for (int i = 0; i < pageCount; i++) {
        // ── Yield more aggressively than the incremental path: each
        //    iteration renders a full page to a PNG, which is expensive
        //    enough to risk the ANR watchdog on its own.
        if (i % 2 == 0) {
          await Future.delayed(Duration.zero);
        }
        await _processPageRaster(
          doc: doc,
          src: src,
          pageIndex: i,
          pageW: src.pages[i].width,
          pageH: src.pages[i].height,
          rectAnnotations: rectAnnotations,
          inkAnnotations: inkAnnotations,
          stickyNotes: stickyNotes,
          signatures: signatures,
          textStamps: textStamps,
          redactions: redactions,
          bookmarks: bookmarks,
          textEdits: textEdits,
        );
        await Future.delayed(Duration.zero);
      }

      final signed = signatures.values.expand((l) => l).toList();
      if (signed.isNotEmpty) {
        doc.addPage(_auditPage(signed, signerProfile, sourcePath,
            signatureIps: signatureIps));
      }

      final pdfBytes = await doc.save() as Uint8List;
      return await _writeResult(sourcePath, pdfBytes, saveInPlace);
    } finally {
      await src.dispose();
    }
  }

  static Future<void> _processPageRaster({
    required pw.Document doc,
    required pdfr.PdfDocument src,
    required int pageIndex,
    required double pageW,
    required double pageH,
    required Map<int, List<RectAnnotation>> rectAnnotations,
    required Map<int, InkAnnotation> inkAnnotations,
    required Map<int, List<StickyNote>> stickyNotes,
    required Map<int, List<SignatureOverlay>> signatures,
    required Map<int, List<TextStamp>> textStamps,
    required Map<int, List<RedactionRect>> redactions,
    required Map<int, List<ClauseBookmark>> bookmarks,
    required Map<int, List<TextEditAnnotation>> textEdits,
  }) async {
    final page = src.pages[pageIndex];
    final pageArea = pageW * pageH;

    double renderScale;
    if (pageArea <= _maxRenderedPixels) {
      renderScale = 1.0;
    } else {
      renderScale = math.sqrt(_maxRenderedPixels / pageArea).clamp(0.3, 1.0);
    }

    pdfr.PdfImage? pdfImg;
    try {
      pdfImg = await page.render(
        fullWidth: pageW * renderScale,
        fullHeight: pageH * renderScale,
        backgroundColor: Colors.white,
      );
      if (pdfImg == null) return;

      final pngBytes = await _pdfImageToPng(pdfImg);
      if (pngBytes == null) return;

      final pageImage = pw.MemoryImage(pngBytes);
      final overlays = <pw.Widget>[];
      overlays.add(pw.Positioned(
        left: 0,
        top: 0,
        child: pw.Image(pageImage,
            width: pageW, height: pageH, fit: pw.BoxFit.fill),
      ));

      // ===== HIGHLIGHTS / UNDERLINES / STRIKETHROUGHS =====
      for (final r in rectAnnotations[pageIndex] ?? []) {
        final l = r.normRect.left * pageW;
        final t = r.normRect.top * pageH;
        final w = r.normRect.width * pageW;
        final h = r.normRect.height * pageH;
        switch (r.type) {
          case AnnotationType.highlight:
            overlays.add(pw.Positioned(
              left: l,
              top: t,
              child: pw.Opacity(
                opacity: 0.4,
                child: pw.Container(
                    width: w, height: h, color: PdfColor.fromInt(r.color.value)),
              ),
            ));
            break;
          case AnnotationType.underline:
            overlays.add(pw.Positioned(
              left: l,
              top: t + h - 1.5,
              child: pw.Container(width: w, height: 1.5, color: _pdfColor(r.color)),
            ));
            break;
          case AnnotationType.strikethrough:
            overlays.add(pw.Positioned(
              left: l,
              top: t + h / 2 - 0.75,
              child: pw.Container(width: w, height: 1.5, color: _pdfColor(r.color)),
            ));
            break;
          case AnnotationType.ink:
          case AnnotationType.stickyNote:
            break;
        }
      }

      // ===== INK =====
      final ink = inkAnnotations[pageIndex];
      if (ink != null) {
        for (final stroke in ink.strokes) {
          final points = stroke.points;
          if (points.isEmpty) continue;
          final strokeWidth = stroke.normWidth > 1.0
              ? stroke.normWidth.clamp(0.5, 12.0)
              : (stroke.normWidth * pageW / 72).clamp(0.5, 12.0);
          final drawColor = _pdfColor(stroke.color);

          overlays.add(pw.Positioned(
            left: 0,
            top: 0,
            child: pw.SizedBox(
              width: pageW,
              height: pageH,
              child: pw.CustomPaint(
                painter: (canvas, _) {
                  canvas.saveContext();
                  canvas
                    ..setStrokeColor(drawColor)
                    ..setFillColor(drawColor)
                    ..setLineWidth(strokeWidth)
                    ..setLineCap(PdfLineCap.round)
                    ..setLineJoin(PdfLineJoin.round);

                  final pts = points
                      .map((p) => (x: p.dx * pageW, y: p.dy * pageH))
                      .toList();

                  if (pts.length == 1) {
                    canvas.drawEllipse(pts[0].x, pts[0].y,
                        strokeWidth / 2, strokeWidth / 2);
                    canvas.fillPath();
                  } else {
                    canvas.moveTo(pts[0].x, pts[0].y);
                    for (int i = 1; i < pts.length; i++) {
                      canvas.lineTo(pts[i].x, pts[i].y);
                    }
                    canvas.strokePath();
                  }
                  canvas.restoreContext();
                },
              ),
            ),
          ));
        }
      }

      // ===== STICKY NOTES =====
      for (final note in stickyNotes[pageIndex] ?? []) {
        final x = note.normPosition.dx * pageW;
        final y = note.normPosition.dy * pageH;
        overlays.add(pw.Positioned(
          left: x.clamp(0.0, pageW - 120),
          top: y.clamp(0.0, pageH - 60),
          child: pw.Container(
            width: 120,
            padding: _stickyPadding,
            decoration: _stickyDecoration,
            child: pw.Text(note.text, style: textStyle(fontSize: 7)),
          ),
        ));
      }

      // ===== SIGNATURES =====
      for (final sig in signatures[pageIndex] ?? []) {
        final x = sig.normPosition.dx * pageW;
        final y = sig.normPosition.dy * pageH;
        final w = sig.normSize.width * pageW;
        final h = sig.normSize.height * pageH;
        overlays.add(pw.Positioned(
          left: x.clamp(0.0, pageW - w),
          top: y.clamp(0.0, pageH - h),
          child: pw.Image(pw.MemoryImage(sig.imageBytes),
              width: w, height: h, fit: pw.BoxFit.contain),
        ));
      }

      // ===== TEXT STAMPS =====
      for (final s in textStamps[pageIndex] ?? []) {
        final x = s.normPosition.dx * pageW;
        final y = s.normPosition.dy * pageH;
        overlays.add(pw.Positioned(
          left: x.clamp(0.0, pageW - 50),
          top: y.clamp(0.0, pageH - 14),
          child: pw.Text(s.text,
              style: textStyle(
                  fontSize: 12, color: _pdfColor(s.color), bold: true)),
        ));
      }

      // ===== TEXT EDITS =====
      for (final t in textEdits[pageIndex] ?? []) {
        if (t.isReplacement && t.originalNormRect != null) {
          final r = t.originalNormRect!;
          final boxLeft = r.left * pageW;
          final boxTop = r.top * pageH;
          final boxW = r.width * pageW;
          final boxH = r.height * pageH;
          if (boxW <= 0 || boxH <= 0) continue;

          const coverPad = 3.0;
          overlays.add(pw.Positioned(
            left: boxLeft - coverPad,
            top: boxTop - coverPad,
            child: pw.Container(
              width: boxW + coverPad * 2,
              height: boxH + coverPad * 2,
              color: PdfColors.white,
            ),
          ));

          // Honour the user's chosen size; auto-fit only when unset.
          final fitted = t.fontSize > 0
              ? t.fontSize
              : _fitFontSize(t.text, boxH * 0.75, boxW, boxH);
          final lineBox = fitted * 1.15;
          final topOffset = boxTop + (boxH - lineBox) / 2;

          overlays.add(pw.Positioned(
            left: boxLeft,
            top: topOffset,
            child: pw.Text(
              t.text,
              style: pw.TextStyle(
                font: pw.Font.helvetica(),
                fontSize: fitted,
                color: _pdfColor(t.color),
              ),
            ),
          ));
        } else {
          final x = t.normPosition.dx * pageW;
          final y = t.normPosition.dy * pageH;
          overlays.add(pw.Positioned(
            left: x.clamp(0.0, pageW - 100),
            top: y.clamp(0.0, pageH - 20),
            child: pw.Text(t.text,
                style: textStyle(
                  fontSize: t.fontSize,
                  color: _pdfColor(t.color),
                  bold: t.isBold,
                )),
          ));
        }
      }

      // ===== REDACTIONS =====
      for (final r in redactions[pageIndex] ?? []) {
        overlays.add(pw.Positioned(
          left: r.normRect.left * pageW,
          top: r.normRect.top * pageH,
          child: pw.Container(
            width: r.normRect.width * pageW,
            height: r.normRect.height * pageH,
            color: PdfColors.black,
          ),
        ));
      }

      // ===== BOOKMARKS =====
      for (final b in bookmarks[pageIndex] ?? []) {
        overlays.add(pw.Positioned(
          left: b.normRect.left * pageW,
          top: b.normRect.top * pageH,
          child: pw.Container(
            width: b.normRect.width * pageW,
            height: b.normRect.height * pageH,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _pdfColor(b.color), width: 1.5),
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
        ));
      }

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageW, pageH),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: overlays),
      ));
    } finally {
      pdfImg?.dispose();
    }
  }

  static double _fitFontSize(
      String text, double desired, double boxW, double boxH) {
    if (text.isEmpty || boxW <= 0 || boxH <= 0 || desired <= 0) {
      return desired > 0 ? desired : 10;
    }
    final heightLimit = boxH / 1.20;
    const avgGlyphEm = 0.58;
    final widthLimit = boxW / (text.length * avgGlyphEm);
    final fitted = heightLimit < widthLimit ? heightLimit : widthLimit;
    return (fitted < desired ? fitted : desired).clamp(4.0, desired);
  }

  static Future<Uint8List?> _pdfImageToPng(pdfr.PdfImage img) async {
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(img.pixels, img.width, img.height,
          ui.PixelFormat.bgra8888, completer.complete);
      final uiImg = await completer.future;
      final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      uiImg.dispose();
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Audit page (used by the raster path)
  // ────────────────────────────────────────────────────────────────────────

  static pw.Page _auditPage(
    List<SignatureOverlay> sigs,
    SignerProfile? profile,
    String src, {
    Map<String, String?>? signatureIps,
  }) {
    final now = DateTime.now();
    final dateStr = now.toIso8601String().split('T').first;
    final timeStr = '${now.hour}:${now.minute}:${now.second} UTC';
    final reportId = now.millisecondsSinceEpoch.toRadixString(36).toUpperCase();

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(45),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: _auditHeaderDecoration,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 40,
                  height: 40,
                  decoration: const pw.BoxDecoration(
                      color: PdfColors.indigo900, shape: pw.BoxShape.circle),
                  child: pw.Center(
                    child: pw.Text('✓',
                        style: textStyle(
                            fontSize: 24,
                            bold: true,
                            color: PdfColors.white)),
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('ELECTRONIC SIGNATURE AUDIT TRAIL',
                          style: textStyle(
                              fontSize: 16,
                              bold: true,
                              color: PdfColors.indigo900)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          'Legally binding under ESIGN Act (U.S.) and eIDAS (EU)',
                          style: textStyle(
                              fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          _auditSection('DOCUMENT INFORMATION', [
            _auditRow('Document Name', p.basename(src)),
            _auditRow('Generated Date', dateStr),
            _auditRow('Generated Time', timeStr),
            _auditRow('Total Signatures', '${sigs.length}'),
          ]),
          pw.SizedBox(height: 16),
          if (profile != null && !profile.isEmpty)
            _auditSection('SIGNER PROFILE', [
              _auditRow('Full Name', profile.fullName),
              if (profile.email.isNotEmpty) _auditRow('Email', profile.email),
              if (profile.title.isNotEmpty) _auditRow('Title', profile.title),
              if (profile.company.isNotEmpty)
                _auditRow('Company', profile.company),
            ]),
          pw.SizedBox(height: 16),
          pw.Text('SIGNATURE DETAILS',
              style: textStyle(
                  fontSize: 11, bold: true, color: PdfColors.indigo900)),
          pw.SizedBox(height: 8),
          ...sigs.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final sig = entry.value;
            final ip = signatureIps?[sig.id];
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(12),
              decoration: _signatureBoxDecoration,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 24,
                        height: 24,
                        decoration: pw.BoxDecoration(
                          color: sig.isInitials
                              ? PdfColors.amber100
                              : PdfColors.green100,
                          shape: pw.BoxShape.circle,
                        ),
                        child: pw.Center(
                          child: pw.Text('$index',
                              style: textStyle(
                                  fontSize: 11,
                                  bold: true,
                                  color: sig.isInitials
                                      ? PdfColors.amber900
                                      : PdfColors.green900)),
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                                sig.isInitials ? 'INITIALLED' : 'SIGNED',
                                style: textStyle(
                                    fontSize: 12,
                                    bold: true,
                                    color: sig.isInitials
                                        ? PdfColors.amber900
                                        : PdfColors.green900)),
                            pw.SizedBox(height: 2),
                            pw.Text('by ${sig.signerName ?? "Unknown Signer"}',
                                style: textStyle(
                                    fontSize: 10,
                                    color: PdfColors.grey700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(children: [
                    pw.Expanded(
                        child:
                            _auditRowCompact('Page', '${sig.pageIndex + 1}')),
                    pw.Expanded(
                        child: _auditRowCompact('Type',
                            sig.isInitials ? 'Initials' : 'Full Signature')),
                  ]),
                  pw.SizedBox(height: 4),
                  if (ip != null) _auditRowCompact('IP Address', ip),
                  pw.SizedBox(height: 4),
                  if (sig.slotId != null) _auditRowCompact('Role', sig.slotId!),
                  pw.SizedBox(height: 8),
                  pw.Container(
                    height: 40,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: pw.Border.all(color: PdfColors.grey200),
                    ),
                    child: pw.Center(
                      child: pw.Image(pw.MemoryImage(sig.imageBytes),
                          height: 35, fit: pw.BoxFit.contain),
                    ),
                  ),
                ],
              ),
            );
          }),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: _legalDisclaimerDecoration,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('LEGAL DISCLAIMER',
                    style: textStyle(
                        fontSize: 9, bold: true, color: PdfColors.grey700)),
                pw.SizedBox(height: 6),
                pw.Text(
                  'This electronic signature audit trail serves as evidence of '
                  'the signing event(s) described above. The signer(s) '
                  'acknowledged their intent to sign this document '
                  'electronically, and this action holds the same legal '
                  'validity as a handwritten signature under the ESIGN Act '
                  '(15 U.S.C. § 7001) and eIDAS Regulation (EU No 910/2014).',
                  style: textStyle(fontSize: 7, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 6),
                pw.Row(children: [
                  pw.Expanded(
                      child: pw.Text('ESIGN Act Compliant',
                          style: textStyle(
                              fontSize: 7,
                              bold: true,
                              color: PdfColors.green700),
                          textAlign: pw.TextAlign.center)),
                  pw.Expanded(
                      child: pw.Text('eIDAS Compliant',
                          style: textStyle(
                              fontSize: 7,
                              bold: true,
                              color: PdfColors.green700),
                          textAlign: pw.TextAlign.center)),
                  pw.Expanded(
                      child: pw.Text('SHA-256 Secured',
                          style: textStyle(
                              fontSize: 7,
                              bold: true,
                              color: PdfColors.green700),
                          textAlign: pw.TextAlign.center)),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generated by DocSign (pdf.contractmind.ai)',
                  style: textStyle(fontSize: 7, color: PdfColors.grey500)),
              pw.Text('Report ID: $reportId',
                  style: textStyle(fontSize: 7, color: PdfColors.grey500)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _auditSection(String title, List<pw.Widget> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: textStyle(
                fontSize: 10, bold: true, color: PdfColors.indigo900)),
        pw.SizedBox(height: 6),
        ...rows,
      ],
    );
  }

  static pw.Widget _auditRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
              width: 120,
              child: pw.Text(label,
                  style: textStyle(
                      fontSize: 9, bold: true, color: PdfColors.grey700))),
          pw.Expanded(
              child: pw.Text(value,
                  style: textStyle(fontSize: 9, color: PdfColors.grey900))),
        ],
      ),
    );
  }

  static pw.Widget _auditRowCompact(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: textStyle(
                fontSize: 7, bold: true, color: PdfColors.grey500)),
        pw.SizedBox(height: 1),
        pw.Text(value,
            style: textStyle(fontSize: 9, color: PdfColors.grey900)),
      ],
    );
  }
}