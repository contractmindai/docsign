import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/annotation.dart';

class NativeTextEditWriter {
  static const bool isSupported = true;

  static Future<Uint8List?> applyTextEditsToPage({
    required Uint8List sourceBytes,
    required int pageIndex,
    required List<TextEditAnnotation> textEdits,
    required double pageWidth,
    required double pageHeight,
    String? password,
  }) async {
    if (textEdits.isEmpty) return sourceBytes;

    try {
      final pdf = pw.Document();
      final pageFormat = PdfPageFormat(pageWidth, pageHeight);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) {
            return pw.Stack(
              children: textEdits.map((edit) {
                final left = edit.originalNormRect.left * pageFormat.width;
                final top = edit.originalNormRect.top * pageFormat.height;
                final width = edit.originalNormRect.width * pageFormat.width;
                final height = edit.originalNormRect.height * pageFormat.height;
                final fontSize = _fitFontSize(
                    edit.text, edit.fontSize, width, height);

                return pw.Positioned(
                  left: left, top: top, width: width, height: height,
                  child: pw.Container(
                    color: PdfColors.white,
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      edit.text,
                      style: pw.TextStyle(
                        fontSize: fontSize,
                        color: PdfColor.fromInt(edit.color.value),
                        font: edit.isBold
                            ? pw.Font.helveticaBold()
                            : pw.Font.helvetica(),
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      );

      return await pdf.save() as Uint8List;
    } catch (e) {
      return null;
    }
  }

  static double _fitFontSize(
      String text, double originalSize, double boxWidth, double boxHeight) {
    double size = boxHeight * 0.80;
    size = size.clamp(6.0, originalSize * 1.5);
    return size;
  }
}