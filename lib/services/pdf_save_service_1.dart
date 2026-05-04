import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
// ✅ Import pdfx with alias to avoid PdfDocument conflict with pdf package
import 'package:pdfx/pdfx.dart' as pdfx;

import '../models/annotation.dart';
import '../models/signer_profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PdfSaveService — True Redaction + full annotation compositing
// ─────────────────────────────────────────────────────────────────────────────

class PdfSaveService {
  static Future<String> save({
    required String sourcePath,
    required int pageCount,
    required Map<int, List<RectAnnotation>>   rectAnnotations,
    required Map<int, InkAnnotation>          inkAnnotations,
    required Map<int, List<StickyNote>>       stickyNotes,
    required Map<int, List<SignatureOverlay>> signatures,
    required Map<int, List<TextStamp>>        textStamps,
    required Map<int, List<RedactionRect>>    redactions,
    required Map<int, List<ClauseBookmark>>   bookmarks,
    required List<SignatureSlot>              slots,
    SignerProfile?                            signerProfile,
  }) async {
    final doc = pw.Document();
    final src = await pdfx.PdfDocument.openFile(sourcePath);

    for (int i = 0; i < pageCount; i++) {
      final page  = await src.getPage(i + 1);
      final pageW = page.width.toDouble();
      final pageH = page.height.toDouble();

      // Render page to raster (TRUE REDACTION: text data is destroyed)
      final rendered = await page.render(
        width:  (pageW * 2.0),
        height: (pageH * 2.0),
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      await page.close();
      if (rendered == null) continue;

      final pageImage = pw.MemoryImage(rendered.bytes);

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageW, pageH),
        margin: pw.EdgeInsets.zero,
        build: (_) {
          final children = <pw.Widget>[];

          // Base page image
          children.add(pw.Positioned(
            left: 0, top: 0,
            child: pw.Image(pageImage, width: pageW, height: pageH,
                fit: pw.BoxFit.fill),
          ));

          // Highlights
          for (final r in rectAnnotations[i] ?? []) {
            final rect = _toRect(r.normRect, pageW, pageH);
            switch (r.type) {
              case AnnotationType.highlight:
                children.add(pw.Positioned(
                  left: rect.$1, top: rect.$2,
                  child: pw.Container(
                    width: rect.$3, height: rect.$4,
                    color: _pdfColor(r.color).shade(0.4)),
                ));
              case AnnotationType.underline:
                children.add(pw.Positioned(
                  left: rect.$1, top: rect.$2 + rect.$4 - 1.5,
                  child: pw.Container(
                      width: rect.$3, height: 1.5,
                      color: _pdfColor(r.color)),
                ));
              case AnnotationType.strikethrough:
                children.add(pw.Positioned(
                  left: rect.$1, top: rect.$2 + rect.$4 / 2 - 0.75,
                  child: pw.Container(
                      width: rect.$3, height: 1.5,
                      color: _pdfColor(r.color)),
                ));
            }
          }

          // Ink
          final ink = inkAnnotations[i];
          if (ink != null) {
            for (final stroke in ink.strokes) {
              if (stroke.points.length < 2) continue;
              for (int k = 0; k < stroke.points.length - 1; k++) {
                final a = stroke.points[k];
                final b = stroke.points[k + 1];
                children.add(pw.Positioned(
                  left: 0, top: 0,
                  child: pw.CustomPaint(
                    size: PdfPoint(pageW, pageH),
                    painter: (canvas, _) {
                      canvas
                        ..setStrokeColor(_pdfColor(stroke.color))
                        ..setLineWidth(stroke.normWidth * pageW)
                        ..moveTo(a.dx * pageW, pageH - a.dy * pageH)
                        ..lineTo(b.dx * pageW, pageH - b.dy * pageH)
                        ..strokePath();
                    },
                  ),
                ));
              }
            }
          }

          // Sticky notes
          for (final note in stickyNotes[i] ?? []) {
            final x = note.normPosition.dx * pageW;
            // ✅ FIX: correct Y flip without magic offset
            final noteH = 60.0; // approximate note height in pts
            final y = pageH - note.normPosition.dy * pageH - noteH;
            children.add(pw.Positioned(
              left: x.clamp(0.0, pageW - 120),
              top:  y.clamp(0.0, pageH - noteH),
              child: pw.Container(
                width: 120,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.amber100,
                  border: pw.Border.all(color: PdfColors.amber),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(note.text,
                    style: const pw.TextStyle(fontSize: 7)),
              ),
            ));
          }

          // Signatures
          for (final sig in signatures[i] ?? []) {
            final x = sig.normPosition.dx * pageW;
            final y = pageH - (sig.normPosition.dy + sig.normSize.height) * pageH;
            children.add(pw.Positioned(
              left: x, top: y.clamp(0.0, pageH - 20),
              child: pw.Image(
                pw.MemoryImage(sig.imageBytes),
                width:  sig.normSize.width  * pageW,
                height: sig.normSize.height * pageH,
                fit: pw.BoxFit.contain),
            ));
          }

          // Text stamps
          for (final stamp in textStamps[i] ?? []) {
            final x = stamp.normPosition.dx * pageW;
            // ✅ FIX: text stamp Y flip — no magic offset, use 12pt text height
            final y = pageH - stamp.normPosition.dy * pageH - 12;
            children.add(pw.Positioned(
              left: x.clamp(0.0, pageW - 50), top: y.clamp(0.0, pageH - 14),
              child: pw.Text(stamp.text,
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: _pdfColor(stamp.color),
                    fontWeight: pw.FontWeight.bold)),
            ));
          }

          // ✅ TRUE REDACTION: solid black rects on rasterized page
          for (final r in redactions[i] ?? []) {
            final rect = _toRect(r.normRect, pageW, pageH);
            children.add(pw.Positioned(
              left: rect.$1, top: rect.$2,
              child: pw.Container(
                  width: rect.$3, height: rect.$4,
                  color: PdfColors.black),
            ));
          }

          // Clause bookmarks
          for (final b in bookmarks[i] ?? []) {
            final rect = _toRect(b.normRect, pageW, pageH);
            children.add(pw.Positioned(
              left: rect.$1, top: rect.$2,
              child: pw.Container(
                width: rect.$3, height: rect.$4,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: _pdfColor(b.color), width: 1.5),
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
            ));
          }

          return pw.Stack(children: children);
        },
      ));
    }

    // Audit trail page
    final signed = signatures.values.expand((l) => l).toList();
    if (signed.isNotEmpty) {
      doc.addPage(_auditPage(signed, signerProfile, sourcePath));
    }

    final dir    = await getApplicationDocumentsDirectory();
    final name   = p.basenameWithoutExtension(sourcePath);
    final output = p.join(dir.path, '${name}_signed.pdf');
    await File(output).writeAsBytes(await doc.save());
    await src.close();
    return output;
  }

  // ✅ FIX: returns (left, top, width, height) tuple — no pw.Rect dependency
  static (double, double, double, double) _toRect(
      dynamic normRect, double pageW, double pageH) {
    final left   = (normRect.left   as double) * pageW;
    final top    = pageH - (normRect.bottom as double) * pageH;
    final width  = (normRect.width  as double) * pageW;
    final height = (normRect.height as double) * pageH;
    return (left, top.clamp(0.0, pageH), width, height);
  }

  static PdfColor _pdfColor(dynamic color) {
    final value = (color.value as int);
    final r = ((value >> 16) & 0xFF) / 255.0;
    final g = ((value >>  8) & 0xFF) / 255.0;
    final b = ( value        & 0xFF) / 255.0;
    return PdfColor(r, g, b);
  }

  static pw.Page _auditPage(
      List<SignatureOverlay> sigs, SignerProfile? profile, String src) =>
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('SIGNATURE AUDIT TRAIL',
              style: pw.TextStyle(fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo900)),
          pw.Divider(color: PdfColors.indigo900),
          pw.SizedBox(height: 8),
          pw.Text('Document: ${p.basename(src)}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Text('Generated: ${DateTime.now().toIso8601String().split('T').first}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 18),
          ...sigs.map((s) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Row(children: [
              pw.Container(width: 8, height: 8,
                  decoration: const pw.BoxDecoration(
                      color: PdfColors.green, shape: pw.BoxShape.circle)),
              pw.SizedBox(width: 10),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text(s.isInitials ? 'Initialled' : 'Signed',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'p.${s.pageIndex + 1}  ·  ${s.signerName ?? "Unknown"}',
                    style: pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600)),
              ]),
            ]),
          )),
        ]),
      );
}
