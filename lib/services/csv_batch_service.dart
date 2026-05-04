import 'dart:typed_data';
import '../utils/platform_file_service.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;

// ─────────────────────────────────────────────────────────────────────────────
// CsvBatchService — Generate N personalized PDFs from a CSV
//
// No external CSV package needed — pure Dart parsing.
// Killer feature: upload a CSV with Name, Email, Amount → 50 personalized
// contracts generated in one tap.
// ─────────────────────────────────────────────────────────────────────────────

class CsvBatchService {
  /// Parse a CSV string → list of row maps
  static List<Map<String, String>> parseCsv(String raw) {
    final lines = const LineSplitter().convert(raw.trim());
    if (lines.isEmpty) return [];

    final headers = _parseLine(lines.first);
    final rows = <Map<String, String>>[];

    for (int i = 1; i < lines.length; i++) {
      final values = _parseLine(lines[i]);
      final row = <String, String>{};
      for (int j = 0; j < headers.length; j++) {
        row[headers[j]] = j < values.length ? values[j] : '';
      }
      rows.add(row);
    }
    return rows;
  }

  static List<String> _parseLine(String line) {
    final result = <String>[];
    bool inQuotes = false;
    final buf = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"'); i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        result.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    result.add(buf.toString().trim());
    return result;
  }

  /// Fill template text — replace {{FieldName}} with CSV values
  static String fillTemplate(String template, Map<String, String> row) {
    String result = template;
    row.forEach((key, value) {
      result = result.replaceAll('{{$key}}', value);
      result = result.replaceAll('{{ $key }}', value); // with spaces
    });
    return result;
  }

  /// Generate PDFs from a template string + CSV rows
  /// Returns list of generated file paths
  static Future<BatchResult> generateBatch({
    required String templateText,
    required String documentTitle,
    required String csvContent,
    void Function(int done, int total)? onProgress,
  }) async {
    final rows = parseCsv(csvContent);
    if (rows.isEmpty) {
      return BatchResult(paths: [], errors: ['CSV is empty or invalid']);
    }

    final dir = await getApplicationDocumentsDirectory();
    final batchDir = Directory('${dir.path}/batch_${DateTime.now().millisecondsSinceEpoch}');
    await batchDir.create(recursive: true);

    final paths  = <String>[];
    final errors = <String>[];

    for (int i = 0; i < rows.length; i++) {
      try {
        final row  = rows[i];
        final text = fillTemplate(templateText, row);
        final name = row['Name'] ?? row['name'] ?? 'document_${i + 1}';
        final safeName = name.replaceAll(RegExp(r'[^\w\s-]'), '_').trim();

        final doc = pw.Document();
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(52),
          header: (ctx) => pw.Text(documentTitle,
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey400)),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey400))),
          build: (_) {
            final widgets = <pw.Widget>[];
            for (final line in text.split('\n')) {
              if (line.trim().isEmpty) {
                widgets.add(pw.SizedBox(height: 6));
              } else {
                widgets.add(pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(line, style: pw.TextStyle(fontSize: 11)),
                ));
              }
            }
            return widgets;
          },
        ));

        final path = p.join(batchDir.path, '$safeName.pdf');
        await PlatformFileService.writeBytes(path, Uint8List.fromList(await doc.save()));
        paths.add(path);
        onProgress?.call(i + 1, rows.length);
      } catch (e) {
        errors.add('Row ${i + 1}: $e');
      }
    }

    return BatchResult(paths: paths, errors: errors, outputDir: batchDir.path);
  }
}

class BatchResult {
  final List<String> paths;
  final List<String> errors;
  final String? outputDir;

  const BatchResult({
    required this.paths,
    required this.errors,
    this.outputDir,
  });

  int get successCount => paths.length;
  int get errorCount   => errors.length;
  bool get hasErrors   => errors.isNotEmpty;
}
