import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io' if (dart.library.io) 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfr;

import '../models/annotation.dart';
import '../models/signer_profile.dart';
import '../utils/platform_file_service.dart';

class PdfSaveService {
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;
  static bool _fontsLoaded = false;

  // Adaptive rendering limit: 2.5 megapixels per page
  static const int _maxRenderedPixels = 2500000;

  // Prebuilt decorations
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
  static final pw.BoxDecoration _redactionDecoration = pw.BoxDecoration(
    color: PdfColors.black,
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
      font: bold ? (_boldFont ?? pw.Font.helveticaBold())
                 : (_regularFont ?? pw.Font.helvetica()),
      fontSize: fontSize,
      color: color,
    );
  }

  static Future<void> _loadFonts() async {
    if (_fontsLoaded) return;
    try {
      final regularData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      _regularFont = pw.Font.ttf(regularData);
      _boldFont = pw.Font.ttf(boldData);
      _fontsLoaded = true;
    } catch (_) {
      _regularFont = pw.Font.helvetica();
      _boldFont = pw.Font.helveticaBold();
      _fontsLoaded = true;
    }
  }

  // ----------------------------------------------------------------------
  // Main save method (processes one page at a time to save memory)
  // ----------------------------------------------------------------------
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
  }) async {
    await _loadFonts();

    final doc = pw.Document(compress: true);

    final pdfr.PdfPasswordProvider? pwProvider = (password != null && password.isNotEmpty)
        ? () => Future<String?>.value(password)
        : null;

    late pdfr.PdfDocument src;
    if (kIsWeb) {
      final bytes = sourceBytes ?? PlatformFileService.getCached(sourcePath);
      if (bytes == null) throw Exception('No PDF bytes available for: $sourcePath');
      src = await pdfr.PdfDocument.openData(bytes,
          sourceName: p.basename(sourcePath),
          passwordProvider: pwProvider);
    } else {
      src = await pdfr.PdfDocument.openFile(sourcePath, passwordProvider: pwProvider);
    }

    try {
      // Process pages sequentially (batch size = 1)
      for (int i = 0; i < pageCount; i++) {
        await _processPage(
          doc: doc, src: src, pageIndex: i,
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
        // Allow garbage collection between pages
        await Future.delayed(Duration.zero);
      }

      final signed = signatures.values.expand((l) => l).toList();
      if (signed.isNotEmpty) {
        doc.addPage(_auditPage(signed, signerProfile, sourcePath, signatureIps: signatureIps));
      }

      final outName = '${p.basenameWithoutExtension(p.basename(sourcePath))}_signed.pdf';
      final output = await PlatformFileService.outputPath(outName);
      final pdfBytes = await doc.save() as Uint8List;

      PlatformFileService.cache(output, pdfBytes);
      await PlatformFileService.writeBytes(output, pdfBytes);

      return output;
    } finally {
      src.dispose();
    }
  }

  // ----------------------------------------------------------------------
  // Process a single page (smooth ink, proper highlight transparency)
  // ----------------------------------------------------------------------
  static Future<void> _processPage({
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

    // Adaptive render scale based on pixel limit
    double renderScale;
    if (pageArea <= _maxRenderedPixels) {
      renderScale = 1.0;
    } else {
      renderScale = math.sqrt(_maxRenderedPixels / pageArea);
      renderScale = renderScale.clamp(0.3, 1.0);
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
        left: 0, top: 0,
        child: pw.Image(pageImage, width: pageW, height: pageH, fit: pw.BoxFit.fill),
      ));

  // ===== HIGHLIGHTS, UNDERLINES, STRIKETHROUGH =====
  for (final r in rectAnnotations[pageIndex] ?? []) {
    final l = r.normRect.left * pageW;
    final t = r.normRect.top * pageH;
    final w = r.normRect.width * pageW;
    final h = r.normRect.height * pageH;
    switch (r.type) {
      case AnnotationType.highlight:
        final baseColor = PdfColor.fromInt(r.color.value);

        // ✅ FIX: Use pw.Opacity wrapper to force the PDF engine to allow transparency
        overlays.add(pw.Positioned(
          left: l, top: t,
          child: pw.Opacity(
            opacity: 0.4,
            child: pw.Container(
              width: w,
              height: h,
              color: baseColor,
            ),
          ),
        ));
        break;
      case AnnotationType.underline:
        overlays.add(pw.Positioned(
          left: l, top: t + h - 1.5,
          child: pw.Container(width: w, height: 1.5, color: _pdfColor(r.color)),
        ));
        break;
      case AnnotationType.strikethrough:
        overlays.add(pw.Positioned(
          left: l, top: t + h / 2 - 0.75,
          child: pw.Container(width: w, height: 1.5, color: _pdfColor(r.color)),
        ));
        break;
      default: break;
    }
  }

  // ===== INK ANNOTATIONS – SMOOTH QUADRATIC BEZIER =====
  final ink = inkAnnotations[pageIndex];
  if (ink != null) {
    for (final stroke in ink.strokes) {
      final points = stroke.points;
      if (points.isEmpty) continue; 

      double strokeWidth;
      if (stroke.normWidth > 1.0) {
        strokeWidth = stroke.normWidth.clamp(0.5, 12.0);
      } else {
        strokeWidth = (stroke.normWidth * pageW) / 72;
        strokeWidth = strokeWidth.clamp(0.5, 12.0);
      }
      
      final drawColor = _pdfColor(stroke.color);

      overlays.add(
        pw.Positioned(
          left: 0, 
          top: 0,
          child: pw.SizedBox(
            width: pageW,
            height: pageH,
            child: pw.CustomPaint(
              painter: (canvas, size) {
                // ✅ FIX: Move context setup cleanly between save/restore blocks
                canvas.saveContext();
                
                canvas
                  ..setStrokeColor(drawColor)
                  ..setFillColor(drawColor) 
                  ..setLineWidth(strokeWidth)
                  ..setLineCap(PdfLineCap.round)
                  ..setLineJoin(PdfLineJoin.round);

                final List<({double x, double y})> pdfPoints = points.map((p) => (
                  x: p.dx * pageW,
                  y: p.dy * pageH, 
                )).toList();

                if (pdfPoints.length == 1) {
                  canvas.drawEllipse(pdfPoints[0].x, pdfPoints[0].y, strokeWidth / 2, strokeWidth / 2);
                  canvas.fillPath();
                } else if (pdfPoints.length == 2) {
                  canvas.moveTo(pdfPoints[0].x, pdfPoints[0].y);
                  canvas.lineTo(pdfPoints[1].x, pdfPoints[1].y);
                  canvas.strokePath();
                } else {
                  canvas.moveTo(pdfPoints[0].x, pdfPoints[0].y);
                  
                  final firstMidX = (pdfPoints[0].x + pdfPoints[1].x) / 2;
                  final firstMidY = (pdfPoints[0].y + pdfPoints[1].y) / 2;
                  canvas.lineTo(firstMidX, firstMidY);

                  for (int i = 1; i < pdfPoints.length - 1; i++) {
                    final current = pdfPoints[i];
                    final next = pdfPoints[i + 1];
                    final midX = (current.x + next.x) / 2;
                    final midY = (current.y + next.y) / 2;
                    
                    canvas.curveTo(current.x, current.y, current.x, current.y, midX, midY);
                  }
                  
                  final last = pdfPoints.last;
                  canvas.lineTo(last.x, last.y);
                  canvas.strokePath(); 
                }
                
                canvas.restoreContext();
              },
            ),
          ),
        ),
      );
    }
  }



      // ===== STICKY NOTES =====
      for (final note in stickyNotes[pageIndex] ?? []) {
        final x = note.normPosition.dx * pageW;
        final y = note.normPosition.dy * pageH;
        overlays.add(pw.Positioned(
          left: x.clamp(0.0, pageW - 120), top: y.clamp(0.0, pageH - 60),
          child: pw.Container(
            width: 120, padding: _stickyPadding,
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
          left: x.clamp(0.0, pageW - w), top: y.clamp(0.0, pageH - h),
          child: pw.Image(pw.MemoryImage(sig.imageBytes), width: w, height: h, fit: pw.BoxFit.contain),
        ));
      }

      // ===== TEXT STAMPS =====
      for (final stamp in textStamps[pageIndex] ?? []) {
        final x = stamp.normPosition.dx * pageW;
        final y = stamp.normPosition.dy * pageH;
        overlays.add(pw.Positioned(
          left: x.clamp(0.0, pageW - 50), top: y.clamp(0.0, pageH - 14),
          child: pw.Text(stamp.text, style: textStyle(fontSize: 12, color: _pdfColor(stamp.color), bold: true)),
        ));
      }

      // ===== TEXT EDITS =====
      for (final textEdit in textEdits[pageIndex] ?? []) {
        final x = textEdit.normPosition.dx * pageW;
        final y = textEdit.normPosition.dy * pageH;
        overlays.add(pw.Positioned(
          left: x.clamp(0.0, pageW - 100), top: y.clamp(0.0, pageH - 20),
          child: pw.Text(textEdit.text, style: textStyle(
            fontSize: textEdit.fontSize,
            color: _pdfColor(textEdit.color),
            bold: textEdit.isBold,
          )),
        ));
      }

      // ===== REDACTIONS =====
      for (final r in redactions[pageIndex] ?? []) {
        overlays.add(pw.Positioned(
          left: r.normRect.left * pageW, top: r.normRect.top * pageH,
          child: pw.Container(width: r.normRect.width * pageW, height: r.normRect.height * pageH, decoration: _redactionDecoration),
        ));
      }

      // ===== BOOKMARKS (borders) =====
      for (final b in bookmarks[pageIndex] ?? []) {
        overlays.add(pw.Positioned(
          left: b.normRect.left * pageW, top: b.normRect.top * pageH,
          child: pw.Container(
            width: b.normRect.width * pageW, height: b.normRect.height * pageH,
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

  // ----------------------------------------------------------------------
  // PNG conversion – optimized (no manual pixel shuffling)
  // ----------------------------------------------------------------------
  static Future<Uint8List?> _pdfImageToPng(pdfr.PdfImage img) async {
    try {
      final completer = Completer<ui.Image>();
      // Assume pdfrx gives BGRA format
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

  // ----------------------------------------------------------------------
  // AUDIT PAGE (full implementation)
  // ----------------------------------------------------------------------
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
                  width: 40, height: 40,
                  decoration: const pw.BoxDecoration(color: PdfColors.indigo900, shape: pw.BoxShape.circle),
                  child: pw.Center(child: pw.Text('✓', style: textStyle(fontSize: 24, bold: true, color: PdfColors.white))),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('ELECTRONIC SIGNATURE AUDIT TRAIL', style: textStyle(fontSize: 16, bold: true, color: PdfColors.indigo900)),
                    pw.SizedBox(height: 4),
                    pw.Text('Legally binding under ESIGN Act (U.S.) and eIDAS (EU)', style: textStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                )),
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
              if (profile.company.isNotEmpty) _auditRow('Company', profile.company),
            ]),
          pw.SizedBox(height: 16),
          pw.Text('SIGNATURE DETAILS', style: textStyle(fontSize: 11, bold: true, color: PdfColors.indigo900)),
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
                        width: 24, height: 24,
                        decoration: pw.BoxDecoration(
                          color: sig.isInitials ? PdfColors.amber100 : PdfColors.green100,
                          shape: pw.BoxShape.circle,
                        ),
                        child: pw.Center(child: pw.Text('$index', style: textStyle(fontSize: 11, bold: true, color: sig.isInitials ? PdfColors.amber900 : PdfColors.green900))),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(sig.isInitials ? 'INITIALLED' : 'SIGNED',
                            style: textStyle(fontSize: 12, bold: true, color: sig.isInitials ? PdfColors.amber900 : PdfColors.green900)),
                          pw.SizedBox(height: 2),
                          pw.Text('by ${sig.signerName ?? "Unknown Signer"}', style: textStyle(fontSize: 10, color: PdfColors.grey700)),
                        ],
                      )),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(children: [
                    pw.Expanded(child: _auditRowCompact('Page', '${sig.pageIndex + 1}')),
                    pw.Expanded(child: _auditRowCompact('Type', sig.isInitials ? 'Initials' : 'Full Signature')),
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
                      child: pw.Image(pw.MemoryImage(sig.imageBytes), height: 35, fit: pw.BoxFit.contain),
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
                pw.Text('LEGAL DISCLAIMER', style: textStyle(fontSize: 9, bold: true, color: PdfColors.grey700)),
                pw.SizedBox(height: 6),
                pw.Text(
                  'This electronic signature audit trail serves as evidence of the signing event(s) described above. '
                  'The signer(s) acknowledged their intent to sign this document electronically, and this action holds '
                  'the same legal validity as a handwritten signature under the ESIGN Act (15 U.S.C. § 7001) and '
                  'eIDAS Regulation (EU No 910/2014).',
                  style: textStyle(fontSize: 7, color: PdfColors.grey600)),
                pw.SizedBox(height: 6),
                pw.Row(children: [
                  pw.Expanded(child: pw.Text('ESIGN Act Compliant', style: textStyle(fontSize: 7, bold: true, color: PdfColors.green700), textAlign: pw.TextAlign.center)),
                  pw.Expanded(child: pw.Text('eIDAS Compliant', style: textStyle(fontSize: 7, bold: true, color: PdfColors.green700), textAlign: pw.TextAlign.center)),
                  pw.Expanded(child: pw.Text('SHA-256 Secured', style: textStyle(fontSize: 7, bold: true, color: PdfColors.green700), textAlign: pw.TextAlign.center)),
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
              pw.Text('Generated by DocSign (pdf.contractmind.ai)', style: textStyle(fontSize: 7, color: PdfColors.grey500)),
              pw.Text('Report ID: $reportId', style: textStyle(fontSize: 7, color: PdfColors.grey500)),
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
        pw.Text(title, style: textStyle(fontSize: 10, bold: true, color: PdfColors.indigo900)),
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
          pw.SizedBox(width: 120, child: pw.Text(label, style: textStyle(fontSize: 9, bold: true, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(value, style: textStyle(fontSize: 9, color: PdfColors.grey900))),
        ],
      ),
    );
  }

  static pw.Widget _auditRowCompact(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: textStyle(fontSize: 7, bold: true, color: PdfColors.grey500)),
        pw.SizedBox(height: 1),
        pw.Text(value, style: textStyle(fontSize: 9, color: PdfColors.grey900)),
      ],
    );
  }
}