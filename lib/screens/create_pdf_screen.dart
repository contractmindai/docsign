import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/pdf_loader.dart';
import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import 'pdf_viewer_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CreatePdfScreen — Create a blank or pre-structured PDF from scratch
// ─────────────────────────────────────────────────────────────────────────────

class CreatePdfScreen extends StatefulWidget {
  const CreatePdfScreen({super.key});

  static void show(BuildContext context) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const CreatePdfScreen()));

  @override
  State<CreatePdfScreen> createState() => _CreatePdfState();
}

class _CreatePdfState extends State<CreatePdfScreen> {
  final _titleCtrl   = TextEditingController(text: 'My Document');
  final _contentCtrl = TextEditingController();
  String _pageSize   = 'A4 Portrait';
  int _pageCount     = 1;
  bool _addHeader    = true;
  bool _addPageNums  = true;
  bool _addLines     = false;
  bool _building     = false;

  final _sizes = [
    'A4 Portrait', 'A4 Landscape', 'Letter Portrait', 'Letter Landscape',
  ];

  PdfPageFormat get _format {
    switch (_pageSize) {
      case 'A4 Landscape':      return PdfPageFormat.a4.landscape;
      case 'Letter Portrait':   return PdfPageFormat.letter;
      case 'Letter Landscape':  return PdfPageFormat.letter.landscape;
      default:                  return PdfPageFormat.a4;
    }
  }

  Future<void> _create() async {
    setState(() => _building = true);
    try {
      final doc = pw.Document();

      for (int pg = 0; pg < _pageCount; pg++) {
        doc.addPage(pw.Page(
          pageFormat: _format,
          margin: const pw.EdgeInsets.fromLTRB(52, 44, 52, 44),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            // Header
            if (_addHeader && pg == 0) ...[
              pw.Text(_titleCtrl.text.trim().isEmpty ? 'Document' : _titleCtrl.text.trim(),
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900)),
              pw.SizedBox(height: 4),
              pw.Divider(color: PdfColors.indigo900, thickness: 1.5),
              pw.SizedBox(height: 16),
            ],
            // Content
            if (_contentCtrl.text.trim().isNotEmpty && pg == 0)
              pw.Text(_contentCtrl.text.trim(),
                  style: pw.TextStyle(fontSize: 11, height: 1.6)),
            // Lined paper
            if (_addLines) ...[
              pw.SizedBox(height: 8),
              ...List.generate(18, (_) => pw.Column(children: [
                pw.SizedBox(height: 22),
                pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              ])),
            ],
            // Page number
            if (_addPageNums) ...[
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('${pg + 1} / $_pageCount',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500))),
            ],
          ]),
        ));
      }

      // ✅ FIXED: Generate PDF bytes
      final pdfBytes = Uint8List.fromList(await doc.save());
      
      // ✅ FIXED: Use PlatformFileService for cross-platform save
      final name = (_titleCtrl.text.trim().isEmpty ? 'document' : _titleCtrl.text.trim())
          .replaceAll(RegExp(r'[^\w\s-]'), '_').trim();
      final fileName = '${name}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      
      if (kIsWeb) {
        // Web: Save to cache and open directly
        PlatformFileService.cache(fileName, pdfBytes);
        if (mounted) {
          await Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => PdfViewerScreen(
              filePath: fileName, 
              preloadedBytes: pdfBytes,
            )),
          );
        }
      } else {
        // Mobile/Desktop: Save to documents directory
        final outputPath = await PlatformFileService.outputPath(fileName);
        await PlatformFileService.writeBytes(outputPath, pdfBytes);
        PlatformFileService.cache(outputPath, pdfBytes);
        
        if (mounted) {
          await Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => PdfViewerScreen(
              filePath: outputPath, 
              preloadedBytes: pdfBytes,
            )),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error creating PDF: $e',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: DS.red));
      }
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        surfaceTintColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('Create PDF', style: GoogleFonts.inter(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [TextButton(
          onPressed: _building ? null : _create,
          child: _building
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo))
              : Text('Create', style: GoogleFonts.inter(
                  color: DS.indigo, fontSize: 14, fontWeight: FontWeight.w700)),
        )],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Document title
          _label('Document Title'),
          _textField(_titleCtrl, 'My Document'),
          const SizedBox(height: 16),

          // Content
          _label('Initial Content (optional)'),
          TextField(
            controller: _contentCtrl,
            maxLines: 5,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDec('Start typing content for page 1…'),
          ),
          const SizedBox(height: 16),

          // Page size
          _label('Page Size'),
          Container(
            decoration: BoxDecoration(color: DS.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DS.separator, width: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: DropdownButton<String>(
              value: _pageSize,
              isExpanded: true,
              dropdownColor: DS.bgCard2,
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: _sizes.map((s) => DropdownMenuItem(value: s,
                  child: Text(s))).toList(),
              onChanged: (v) { if (v != null) setState(() => _pageSize = v); }),
          ),
          const SizedBox(height: 16),

          // Page count
          _label('Number of Pages'),
          Container(
            decoration: BoxDecoration(color: DS.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DS.separator, width: 0.5)),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.remove_rounded, color: DS.indigo),
                onPressed: () { if (_pageCount > 1) setState(() => _pageCount--); }),
              Expanded(child: Text('$_pageCount page${_pageCount > 1 ? "s" : ""}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w600))),
              IconButton(
                icon: const Icon(Icons.add_rounded, color: DS.indigo),
                onPressed: () { if (_pageCount < 50) setState(() => _pageCount++); }),
            ]),
          ),
          const SizedBox(height: 16),

          // Options
          _label('Options'),
          Container(
            decoration: BoxDecoration(color: DS.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DS.separator, width: 0.5)),
            child: Column(children: [
              _toggle('Title header on first page', _addHeader, DS.indigo,
                  (v) => setState(() => _addHeader = v)),
              const Divider(height: 1, indent: 16, color: DS.separator),
              _toggle('Page numbers', _addPageNums, DS.green,
                  (v) => setState(() => _addPageNums = v)),
              const Divider(height: 1, indent: 16, color: DS.separator),
              _toggle('Lined paper (notebook style)', _addLines, DS.orange,
                  (v) => setState(() => _addLines = v)),
            ]),
          ),

          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Create PDF',
            icon: Icons.picture_as_pdf_rounded,
            onTap: _create,
            loading: _building,
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(
        color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)));

  Widget _textField(TextEditingController ctrl, String hint) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: _inputDec(hint));

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true, fillColor: DS.bgCard,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DS.separator, width: 0.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DS.separator, width: 0.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DS.indigo)));

  Widget _toggle(String label, bool value, Color color,
      ValueChanged<bool> onChange) =>
      SwitchListTile(
        value: value, onChanged: onChange,
        activeColor: color, dense: true,
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      );
}