import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

  /// Load Unicode-supporting fonts
  static Future<void> _ensureFontsLoaded() async {
    if (_fontsLoaded) return;
    _fontsLoaded = true;
    
    try {
      final regularData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      _regularFont = pw.Font.ttf(regularData);
      _boldFont = pw.Font.ttf(boldData);
    } catch (_) {
      _regularFont = pw.Font.helvetica();
      _boldFont = pw.Font.helveticaBold();
    }
  }

  /// Unicode-safe text style
  static pw.TextStyle _textStyle({
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
    await _ensureFontsLoaded();
    
    final doc = pw.Document();

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
      // ✅ Process 3 pages at a time
      const batchSize = 3;
      for (int i = 0; i < pageCount; i += batchSize) {
        final batch = <Future>[];
        for (int j = i; j < (i + batchSize).clamp(0, pageCount); j++) {
          batch.add(_processPage(
            doc: doc, src: src, pageIndex: j,
            pageW: src.pages[j].width,
            pageH: src.pages[j].height,
            rectAnnotations: rectAnnotations,
            inkAnnotations: inkAnnotations,
            stickyNotes: stickyNotes,
            signatures: signatures,
            textStamps: textStamps,
            redactions: redactions,
            bookmarks: bookmarks,
            textEdits: textEdits,
          ));
        }
        await Future.wait(batch);
      }

      final signed = signatures.values.expand((l) => l).toList();
      if (signed.isNotEmpty) {
        doc.addPage(_auditPage(signed, signerProfile, sourcePath, signatureIps: signatureIps));
      }

      final outName = '${p.basenameWithoutExtension(p.basename(sourcePath))}_signed.pdf';
      final output = await PlatformFileService.outputPath(outName);
      final pdfBytes = Uint8List.fromList(await doc.save());
      
      PlatformFileService.cache(output, pdfBytes);
      await PlatformFileService.writeBytes(output, pdfBytes);
      
      return output;
    } finally {
      src.dispose();
    }
  }

  /// ✅ Extracted page processing for cleaner code
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
    
    // ✅ Adaptive render scale based on page size
    final pageArea = pageW * pageH;
    double renderScale;
    if (pageArea < 500000) {
      renderScale = 2.0;       // Tiny pages: high quality
    } else if (pageArea < 2000000) {
      renderScale = 1.5;       // Medium pages: balanced
    } else if (pageArea < 4000000) {
      renderScale = 1.2;       // Large pages: good enough
    } else {
      renderScale = 1.0;       // Very large: fastest
    }

    final pdfImg = await page.render(
      fullWidth: pageW * renderScale, 
      fullHeight: pageH * renderScale,
      backgroundColor: Colors.white,
    );
    
    if (pdfImg == null) return;

    final pngBytes = await _pdfImageToPng(pdfImg);
    if (pngBytes == null) return;
    
    final pageImage = pw.MemoryImage(pngBytes);
    final overlays = <pw.Widget>[];
    
    // Base page image
    overlays.add(
      pw.Positioned(
        left: 0, top: 0,
        child: pw.Image(pageImage, width: pageW, height: pageH, fit: pw.BoxFit.fill),
      ),
    );

    // Highlights, underlines, strikethrough
    for (final r in rectAnnotations[pageIndex] ?? []) {
      final l = r.normRect.left * pageW;
      final t = r.normRect.top * pageH;
      final w = r.normRect.width * pageW;
      final h = r.normRect.height * pageH;
      
      switch (r.type) {
        case AnnotationType.highlight:
          overlays.add(pw.Positioned(left: l, top: t,
              child: pw.Container(width: w, height: h, color: _pdfColor(r.color, opacity: 0.4))));
          break;
        case AnnotationType.underline:
          overlays.add(pw.Positioned(left: l, top: t + h - 1.5,
              child: pw.Container(width: w, height: 1.5, color: _pdfColor(r.color))));
          break;
        case AnnotationType.strikethrough:
          overlays.add(pw.Positioned(left: l, top: t + h / 2 - 0.75,
              child: pw.Container(width: w, height: 1.5, color: _pdfColor(r.color))));
          break;
        default: break;
      }
    }

    // Ink annotations
    final ink = inkAnnotations[pageIndex];
    if (ink != null) {
      for (final stroke in ink.strokes) {
        if (stroke.points.length < 2) continue;
        for (int k = 0; k < stroke.points.length - 1; k++) {
          final a = stroke.points[k]; 
          final b = stroke.points[k + 1];
          final x1 = a.dx * pageW; 
          final y1 = a.dy * pageH;
          final x2 = b.dx * pageW; 
          final y2 = b.dy * pageH;
          final left = x1 < x2 ? x1 : x2;
          final top = y1 < y2 ? y1 : y2;
          final width = (x1 - x2).abs() + (stroke.normWidth * pageW);
          final height = (y1 - y2).abs() + (stroke.normWidth * pageW);
          if (width > 0.5 || height > 0.5) {
            overlays.add(pw.Positioned(left: left, top: top,
              child: pw.Container(
                width: width < 1 ? 1 : width, 
                height: height < 1 ? 1 : height,
                color: _pdfColor(stroke.color),
              ),
            ));
          }
        }
      }
    }

    // Sticky notes
    for (final note in stickyNotes[pageIndex] ?? []) {
      final x = note.normPosition.dx * pageW;
      final y = note.normPosition.dy * pageH;
      overlays.add(pw.Positioned(
        left: x.clamp(0.0, pageW - 120), 
        top: y.clamp(0.0, pageH - 60),
        child: pw.Container(
          width: 120, 
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: PdfColors.amber100,
            border: pw.Border.all(color: PdfColors.amber), 
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(note.text, style: _textStyle(fontSize: 7)),
        ),
      ));
    }

    // Signatures
    for (final sig in signatures[pageIndex] ?? []) {
      final x = sig.normPosition.dx * pageW;
      final y = sig.normPosition.dy * pageH;
      final w = sig.normSize.width * pageW;
      final h = sig.normSize.height * pageH;
      overlays.add(pw.Positioned(
        left: x.clamp(0.0, pageW - w), 
        top: y.clamp(0.0, pageH - h),
        child: pw.Image(pw.MemoryImage(sig.imageBytes), width: w, height: h, fit: pw.BoxFit.contain),
      ));
    }

    // Text stamps
    for (final stamp in textStamps[pageIndex] ?? []) {
      final x = stamp.normPosition.dx * pageW;
      final y = stamp.normPosition.dy * pageH;
      overlays.add(pw.Positioned(
        left: x.clamp(0.0, pageW - 50), 
        top: y.clamp(0.0, pageH - 14),
        child: pw.Text(stamp.text, style: _textStyle(fontSize: 12, color: _pdfColor(stamp.color), bold: true)),
      ));
    }

    // Text edits
    for (final textEdit in textEdits[pageIndex] ?? []) {
      final x = textEdit.normPosition.dx * pageW;
      final y = textEdit.normPosition.dy * pageH;
      overlays.add(pw.Positioned(
        left: x.clamp(0.0, pageW - 100), 
        top: y.clamp(0.0, pageH - 20),
        child: pw.Text(textEdit.text, style: _textStyle(
          fontSize: textEdit.fontSize,
          color: _pdfColor(textEdit.color),
          bold: textEdit.isBold,
        )),
      ));
    }

    // Redactions
    for (final r in redactions[pageIndex] ?? []) {
      overlays.add(pw.Positioned(
        left: r.normRect.left * pageW, 
        top: r.normRect.top * pageH,
        child: pw.Container(width: r.normRect.width * pageW, height: r.normRect.height * pageH, color: PdfColors.black),
      ));
    }

    // Bookmarks
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
  }

  static PdfColor _pdfColor(dynamic color, {double opacity = 1.0}) {
    int r, g, b;
    
    if (color is Color) {
      final value = color.value;
      r = (value >> 16) & 0xFF;
      g = (value >> 8) & 0xFF;
      b = value & 0xFF;
    } else if (color is int) {
      r = (color >> 16) & 0xFF;
      g = (color >> 8) & 0xFF;
      b = color & 0xFF;
    } else {
      r = 0; g = 0; b = 0;
    }
    
    return PdfColor(
      (r / 255.0) * opacity,
      (g / 255.0) * opacity,
      (b / 255.0) * opacity,
    );
  }

  static Future<Uint8List?> _pdfImageToPng(pdfr.PdfImage img) async {
    try {
      final pixels = img.pixels;
      final convertedPixels = Uint8List(pixels.length);
      for (int i = 0; i < pixels.length; i += 4) {
        convertedPixels[i] = pixels[i + 2];
        convertedPixels[i + 1] = pixels[i + 1];
        convertedPixels[i + 2] = pixels[i];
        convertedPixels[i + 3] = pixels[i + 3];
      }
      final comp = Completer<ui.Image>();
      ui.decodeImageFromPixels(convertedPixels, img.width, img.height,
          ui.PixelFormat.rgba8888, (i) => comp.complete(i));
      final uiImg = await comp.future;
      final bd = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      uiImg.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════════
  // AUDIT PAGE
  // ═══════════════════════════════════════════════════════

  static pw.Page _auditPage(
    List<SignatureOverlay> sigs, 
    SignerProfile? profile, 
    String src, {
    Map<String, String?>? signatureIps,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(45),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.indigo50,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.indigo200, width: 1),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 40, height: 40,
                  decoration: const pw.BoxDecoration(color: PdfColors.indigo900, shape: pw.BoxShape.circle),
                  child: pw.Center(
                    child: pw.Text('OK', style: const pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('ELECTRONIC SIGNATURE AUDIT TRAIL', style: _textStyle(fontSize: 16, bold: true, color: PdfColors.indigo900)),
                    pw.SizedBox(height: 4),
                    pw.Text('Legally binding under ESIGN Act (U.S.) and eIDAS (EU)', style: _textStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                )),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          
          // Document Info
          _auditSection('DOCUMENT INFORMATION', [
            _auditRow('Document Name', p.basename(src)),
            _auditRow('Generated Date', DateTime.now().toIso8601String().split('T').first),
            _auditRow('Generated Time', '${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second} UTC'),
            _auditRow('Total Signatures', '${sigs.length}'),
          ]),
          pw.SizedBox(height: 16),
          
          // Signer Profile
          if (profile != null && !profile.isEmpty)
            _auditSection('SIGNER PROFILE', [
              _auditRow('Full Name', profile.fullName),
              if (profile.email.isNotEmpty) _auditRow('Email', profile.email),
              if (profile.title.isNotEmpty) _auditRow('Title', profile.title),
              if (profile.company.isNotEmpty) _auditRow('Company', profile.company),
            ]),
          pw.SizedBox(height: 16),
          
          // Signature Details
          pw.Text('SIGNATURE DETAILS', style: _textStyle(fontSize: 11, bold: true, color: PdfColors.indigo900)),
          pw.SizedBox(height: 8),
          ...sigs.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final sig = entry.value;
            final ip = signatureIps?[sig.id];
            
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
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
                        child: pw.Center(
                          child: pw.Text('$index', style: _textStyle(fontSize: 11, bold: true, color: sig.isInitials ? PdfColors.amber900 : PdfColors.green900)),
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(sig.isInitials ? 'INITIALLED' : 'SIGNED',
                            style: _textStyle(fontSize: 12, bold: true, color: sig.isInitials ? PdfColors.amber900 : PdfColors.green900)),
                          pw.SizedBox(height: 2),
                          pw.Text('by ${sig.signerName ?? "Unknown Signer"}', style: _textStyle(fontSize: 10, color: PdfColors.grey700)),
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
          
          // Legal Disclaimer
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('LEGAL DISCLAIMER', style: _textStyle(fontSize: 9, bold: true, color: PdfColors.grey700)),
                pw.SizedBox(height: 6),
                pw.Text(
                  'This electronic signature audit trail serves as evidence of the signing event(s) described above. '
                  'The signer(s) acknowledged their intent to sign this document electronically, and this action holds '
                  'the same legal validity as a handwritten signature under the ESIGN Act (15 U.S.C. § 7001) and '
                  'eIDAS Regulation (EU No 910/2014).',
                  style: _textStyle(fontSize: 7, color: PdfColors.grey600)),
                pw.SizedBox(height: 6),
                pw.Row(children: [
                  pw.Expanded(child: pw.Text('ESIGN Act Compliant', style: _textStyle(fontSize: 7, bold: true, color: PdfColors.green700), textAlign: pw.TextAlign.center)),
                  pw.Expanded(child: pw.Text('eIDAS Compliant', style: _textStyle(fontSize: 7, bold: true, color: PdfColors.green700), textAlign: pw.TextAlign.center)),
                  pw.Expanded(child: pw.Text('SHA-256 Secured', style: _textStyle(fontSize: 7, bold: true, color: PdfColors.green700), textAlign: pw.TextAlign.center)),
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
              pw.Text('Generated by DocSign (pdf.contractmind.ai)', style: _textStyle(fontSize: 7, color: PdfColors.grey500)),
              pw.Text('Report ID: ${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}', style: _textStyle(fontSize: 7, color: PdfColors.grey500)),
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
        pw.Text(title, style: _textStyle(fontSize: 10, bold: true, color: PdfColors.indigo900)),
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
          pw.SizedBox(width: 120, child: pw.Text(label, style: _textStyle(fontSize: 9, bold: true, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(value, style: _textStyle(fontSize: 9, color: PdfColors.grey900))),
        ],
      ),
    );
  }

  static pw.Widget _auditRowCompact(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: _textStyle(fontSize: 7, bold: true, color: PdfColors.grey500)),
        pw.SizedBox(height: 1),
        pw.Text(value, style: _textStyle(fontSize: 9, color: PdfColors.grey900)),
      ],
    );
  }
}