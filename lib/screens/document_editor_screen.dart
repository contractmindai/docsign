import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/platform_file_service.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_viewer_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DocumentEditorScreen v6 — ALL issues fixed
//
// Fixed:
//   1. KEYBOARD NOT SHOWING: autofocus: true + FocusNode.requestFocus on mount
//   2. SAVE NOT WORKING: save() now correctly writes and shows snack
//   3. DOCX READING: archive package unzips .docx, parses word/document.xml
//   4. Toolbar scrollable — all buttons accessible on small phones
//   5. AutoFocus properly triggers keyboard on first open
// ─────────────────────────────────────────────────────────────────────────────

class DocumentEditorScreen extends StatefulWidget {
  final String? existingPath;
  final String? initialContent; // plain text pre-fill (from docx import)

  const DocumentEditorScreen({super.key, this.existingPath, this.initialContent});

  static Future<void> openNew(BuildContext ctx) => Navigator.push(
      ctx, MaterialPageRoute(builder: (_) => const DocumentEditorScreen()));

  static Future<void> openFile(BuildContext ctx, String path) =>
      Navigator.push(ctx,
          MaterialPageRoute(builder: (_) =>
              DocumentEditorScreen(existingPath: path)));

  static Future<void> openDocx(BuildContext ctx, String path,
      String extractedText) => Navigator.push(ctx,
      MaterialPageRoute(builder: (_) => DocumentEditorScreen(
          existingPath: path, initialContent: extractedText)));

  @override
  State<DocumentEditorScreen> createState() => _DocEditorState();
}

class _DocEditorState extends State<DocumentEditorScreen> {
  late quill.QuillController _ctrl;
  late TextEditingController _titleCtrl;
  final _focus = FocusNode();

  bool    _dirty   = false;
  bool    _saving  = false;
  String? _savedPath;

  bool   _bold      = false;
  bool   _italic    = false;
  bool   _underline = false;
  bool   _strike    = false;
  double _fontSize  = 14.0;
  Color  _color     = Colors.black;
  String _alignVal  = 'left';

  @override
  void initState() {
    super.initState();

    _titleCtrl = TextEditingController(
      text: widget.existingPath != null
          ? p.basenameWithoutExtension(widget.existingPath!)
          : 'Untitled Document',
    );

    // ✅ FIX: Initialize controller with content if provided
    if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
      // Build a Quill document from plain text
      final doc = quill.Document()..insert(0, widget.initialContent!);
      _ctrl = quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0));
      _dirty = true; // mark as needing save
    } else {
      _ctrl = quill.QuillController.basic();
    }

    _ctrl.addListener(_sync);
    _savedPath = widget.existingPath;

    if (widget.existingPath != null &&
        widget.initialContent == null &&
        widget.existingPath!.endsWith('.qldoc')) {
      _loadFile(widget.existingPath!);
    }

    // ✅ FIX: Request focus to show keyboard after frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focus);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_sync);
    _ctrl.dispose();
    _titleCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final s = _ctrl.getSelectionStyle();
    setState(() {
      _dirty     = true;
      _bold      = s.containsKey(quill.Attribute.bold.key);
      _italic    = s.containsKey(quill.Attribute.italic.key);
      _underline = s.containsKey(quill.Attribute.underline.key);
      _strike    = s.containsKey(quill.Attribute.strikeThrough.key);
      final av   = s.attributes[quill.Attribute.align.key]?.value;
      _alignVal  = av?.toString() ?? 'left';
    });
  }

  // ── File I/O ──────────────────────────────────────────────────────────────

  Future<void> _loadFile(String path) async {
    try {
      final raw  = await PlatformFileService.readText(path) ?? '\\';
      final json = jsonDecode(raw) as List;
      final doc  = quill.Document.fromJson(json);
      if (!mounted) return;
      _ctrl.removeListener(_sync);
      setState(() {
        _ctrl = quill.QuillController(
            document: doc,
            selection: const TextSelection.collapsed(offset: 0));
        _ctrl.addListener(_sync);
        _dirty = false;
      });
    } catch (e) {
      _snack('Could not load: $e', err: true);
    }
  }

  // ✅ FIX: Save correctly writes file and confirms to user
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final name = _safeName(_titleCtrl.text.trim());
      // ✅ Save as .docx for Word compatibility
      _savedPath ??= p.join(dir.path, '$name.docx');
      // Also save delta for re-editing
      final deltaPath = _savedPath!.replaceAll('.docx', '.qldoc');
      await PlatformFileService.writeBytes(deltaPath,
          Uint8List.fromList(jsonEncode(_ctrl.document.toDelta().toJson()).codeUnits));
      // Build proper .docx
      await _writeDocx(_savedPath!, _ctrl.document.toPlainText());
      if (mounted) {
        setState(() => _dirty = false);
        _snack('Saved ✓  ${p.basename(_savedPath!)}');
      }
    } catch (e) {
      _snack('Save failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAs() async { _savedPath = null; await _save(); }

  Future<void> _writeDocx(String path, String text) async {
    final paras = text.split('\n').map((line) {
      final esc = line
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      final t = esc.isEmpty ? ' ' : esc;
      return '<w:p><w:r><w:t xml:space="preserve">$t</w:t></w:r></w:p>';
    }).join('\n');

    final docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$paras<w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr>'
        '</w:body></w:document>';

    final contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';

    final rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';

    final archive = Archive();
    void add(String n, String s) {
      final b = utf8.encode(s);
      archive.addFile(ArchiveFile(n, b.length, b));
    }
    add('[Content_Types].xml', contentTypes);
    add('_rels/.rels', rels);
    add('word/document.xml', docXml);
    final zip = ZipEncoder().encode(archive);
    if (zip != null) await PlatformFileService.writeBytes(path, Uint8List.fromList(zip));
  }

  String _safeName(String raw) {
    final s = raw.isEmpty
        ? 'doc_${DateTime.now().millisecondsSinceEpoch}' : raw;
    return s.replaceAll(RegExp(r'[^\w\s\-]'), '_').trim();
  }

  // ── PDF export ────────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    setState(() => _saving = true);
    try {
      final title  = _titleCtrl.text.trim().isEmpty
          ? 'Document' : _titleCtrl.text.trim();
      final ops    = _ctrl.document.toDelta().toJson() as List;
      final wgts   = <pw.Widget>[];

      wgts.add(pw.Text(title, style: pw.TextStyle(
          fontSize: 20, fontWeight: pw.FontWeight.bold,
          color: PdfColors.indigo900)));
      wgts.add(pw.SizedBox(height: 16));

      final buf = StringBuffer();

      void flush(Map<String, dynamic> attrs) {
        final text = buf.toString().trim();
        buf.clear();
        if (text.isEmpty) { wgts.add(pw.SizedBox(height: 5)); return; }

        final style = pw.TextStyle(
          fontSize: 11,
          fontWeight: attrs['bold']   == true ? pw.FontWeight.bold  : null,
          fontStyle:  attrs['italic'] == true ? pw.FontStyle.italic : null,
        );
        final hdr  = attrs['header'];
        final list = attrs['list'];

        if (hdr == 1) {
          wgts.add(pw.Text(text, style: pw.TextStyle(
              fontSize: 20, fontWeight: pw.FontWeight.bold)));
        } else if (hdr == 2) {
          wgts.add(pw.Text(text, style: pw.TextStyle(
              fontSize: 16, fontWeight: pw.FontWeight.bold)));
        } else if (hdr == 3) {
          wgts.add(pw.Text(text, style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold)));
        } else if (list == 'bullet') {
          wgts.add(pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('• ', style: pw.TextStyle(fontSize: 11)),
                pw.Expanded(child: pw.Text(text, style: style)),
              ]));
        } else if (list == 'ordered') {
          wgts.add(pw.Text(text, style: style));
        } else if (attrs['blockquote'] == true) {
          wgts.add(pw.Container(
              padding: const pw.EdgeInsets.only(left: 10),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(left: pw.BorderSide(
                      color: PdfColors.indigo300, width: 3))),
              child: pw.Text(text, style: pw.TextStyle(
                  fontSize: 11, fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey600))));
        } else {
          wgts.add(pw.Text(text, style: style));
        }
        wgts.add(pw.SizedBox(height: 3));
      }

      for (final op in ops) {
        if (op['insert'] is! String) continue;
        final txt   = op['insert'] as String;
        final attrs = (op['attributes'] as Map?)
                ?.cast<String, dynamic>() ?? {};
        final parts = txt.split('\n');
        for (int i = 0; i < parts.length; i++) {
          buf.write(parts[i]);
          if (i < parts.length - 1) flush(attrs);
        }
      }
      if (buf.isNotEmpty) flush({});

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(52),
        header: (_) => pw.Text(title,
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey400)),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey400))),
        build: (_) => wgts,
      ));

      final dir  = await getApplicationDocumentsDirectory();
      final out  = p.join(dir.path, '${_safeName(title)}.pdf');
      await PlatformFileService.writeBytes(out, await doc.save());

      if (mounted) {
        _snack('PDF exported — opening viewer');
        await Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => PdfViewerScreen(filePath: out)));
      }
    } catch (e) {
      _snack('Export failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
      backgroundColor: err ? Colors.red.shade700 : const Color(0xFF1E1E3F),
      behavior: SnackBarBehavior.floating));
  }

  // ── Format actions ────────────────────────────────────────────────────────

  void _toggle(quill.Attribute attr) => _ctrl.formatSelection(attr);
  void _heading(int level) => _ctrl.formatSelection(
      quill.Attribute.fromKeyValue('header', level == 0 ? null : level));
  void _setSize(double sz) {
    setState(() => _fontSize = sz);
    _ctrl.formatSelection(quill.Attribute.fromKeyValue(
        'size', sz == 14.0 ? null : '${sz.toInt()}'));
  }
  void _align(String? val) {
    setState(() => _alignVal = val ?? 'left');
    _ctrl.formatSelection(quill.Attribute.fromKeyValue('align', val));
  }
  void _list(String t) =>
      _ctrl.formatSelection(quill.Attribute.fromKeyValue('list', t));
  void _blockQuote() =>
      _ctrl.formatSelection(quill.Attribute.fromKeyValue('blockquote', true));
  void _codeBlock() =>
      _ctrl.formatSelection(quill.Attribute.fromKeyValue('code-block', true));
  void _applyColor(Color c) {
    setState(() => _color = c);
    final hex = c.value.toRadixString(16).padLeft(8, '0').substring(2);
    _ctrl.formatSelection(
        quill.Attribute.fromKeyValue('color', '#$hex'));
  }
  void _clearFmt() {
    for (final a in [quill.Attribute.bold, quill.Attribute.italic,
        quill.Attribute.underline, quill.Attribute.strikeThrough]) {
      _ctrl.formatSelection(quill.Attribute.clone(a, null));
    }
    setState(() { _bold = false; _italic = false;
                  _underline = false; _strike = false; });
  }

  void _pickColor() {
    Color tmp = _color;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Text colour',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 15)),
      content: ColorPicker(pickerColor: _color,
          onColorChanged: (c) => tmp = c,
          enableAlpha: false, labelTypes: const [],
          pickerAreaHeightPercent: 0.65),
      actions: [TextButton(
        onPressed: () { _applyColor(tmp); Navigator.pop(context); },
        child: const Text('Done',
            style: TextStyle(color: Color(0xFF6366F1))),
      )],
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar(),
      body: Column(children: [
        _toolbar(),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Expanded(child: _editor()),
      ]),
      resizeToAvoidBottomInset: true,
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: const Color(0xFF14142B),
    foregroundColor: Colors.white,
    elevation: 0, titleSpacing: 8,
    title: Row(children: [
      Expanded(child: TextField(
        controller: _titleCtrl,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 14,
            fontWeight: FontWeight.w600),
        decoration: const InputDecoration(isDense: true,
            border: InputBorder.none, hintText: 'Document title',
            hintStyle: TextStyle(color: Color(0x66FFFFFF))),
        onChanged: (_) => setState(() => _dirty = true),
      )),
      if (_dirty)
        Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4)),
          child: const Text('unsaved',
              style: TextStyle(color: Colors.orange, fontSize: 10))),
    ]),
    actions: [
      IconButton(icon: const Icon(Icons.undo_rounded, size: 20),
          tooltip: 'Undo', onPressed: () => _ctrl.undo()),
      IconButton(icon: const Icon(Icons.redo_rounded, size: 20),
          tooltip: 'Redo', onPressed: () => _ctrl.redo()),
      // ✅ Save button always visible
      _saving
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: Color(0xFF6366F1))))
          : IconButton(
              icon: const Icon(Icons.save_rounded,
                  color: Color(0xFF6366F1), size: 22),
              tooltip: 'Save document', onPressed: _save),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        color: const Color(0xFF1A1A2E),
        onSelected: (v) async {
          if (v == 'saveAs') await _saveAs();
          if (v == 'pdf')    await _exportPdf();
        },
        itemBuilder: (_) => [
          _mi('saveAs', Icons.save_as_rounded, 'Save As…'),
          const PopupMenuDivider(),
          _mi('pdf', Icons.picture_as_pdf_rounded, 'Export to PDF'),
        ],
      ),
    ],
  );

  PopupMenuItem<String> _mi(String v, IconData icon, String label) =>
      PopupMenuItem(value: v, child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF818CF8)),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.inter(
            color: Colors.white.withOpacity(0.75), fontSize: 13)),
      ]));

  Widget _toolbar() => Container(
    color: const Color(0xFF1A1A2E),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _StyleDrop(onSelect: _heading),
        _sep(),
        _SizeDrop(current: _fontSize, onSelect: _setSize),
        _sep(),
        _Btn(Icons.format_bold_rounded,      _bold,      'Bold',      () => _toggle(quill.Attribute.bold)),
        _Btn(Icons.format_italic_rounded,    _italic,    'Italic',    () => _toggle(quill.Attribute.italic)),
        _Btn(Icons.format_underline_rounded, _underline, 'Underline', () => _toggle(quill.Attribute.underline)),
        _Btn(Icons.strikethrough_s_rounded,  _strike,    'Strike',    () => _toggle(quill.Attribute.strikeThrough)),
        _sep(),
        GestureDetector(onTap: _pickColor,
          child: Tooltip(message: 'Text colour',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.format_color_text_rounded,
                    size: 20, color: Colors.white),
                Container(height: 3, width: 18,
                    margin: const EdgeInsets.only(top: 2),
                    color: _color == Colors.black
                        ? Colors.white.withOpacity(0.7) : _color),
              ]),
            ),
          ),
        ),
        _sep(),
        _Btn(Icons.format_align_left_rounded,    _alignVal == 'left',    'Left',    () => _align(null)),
        _Btn(Icons.format_align_center_rounded,  _alignVal == 'center',  'Center',  () => _align('center')),
        _Btn(Icons.format_align_right_rounded,   _alignVal == 'right',   'Right',   () => _align('right')),
        _Btn(Icons.format_align_justify_rounded, _alignVal == 'justify', 'Justify', () => _align('justify')),
        _sep(),
        _Btn(Icons.format_list_bulleted_rounded, false, 'Bullets',  () => _list('bullet')),
        _Btn(Icons.format_list_numbered_rounded, false, 'Numbered', () => _list('ordered')),
        _sep(),
        _Btn(Icons.format_quote_rounded, false, 'Quote',      _blockQuote),
        _Btn(Icons.code_rounded,         false, 'Code block', _codeBlock),
        _sep(),
        _Btn(Icons.format_clear_rounded, false, 'Clear fmt',
            _clearFmt, tint: const Color(0xFFF87171)),
      ]),
    ),
  );

  Widget _sep() => Container(
      width: 1, height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white12);

  Widget _editor() => Container(
    color: Colors.white,
    child: GestureDetector(
      onTap: () => FocusScope.of(context).requestFocus(_focus),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: quill.QuillEditor.basic(
          controller: _ctrl,
          focusNode: _focus,
          configurations: quill.QuillEditorConfigurations(
            autoFocus: true,
            placeholder: 'Start typing your document…',
            padding: EdgeInsets.zero,
            customStyles: quill.DefaultStyles(
              paragraph: quill.DefaultTextBlockStyle(
                GoogleFonts.inter(fontSize: 14,
                    color: const Color(0xFF111827), height: 1.65),
                const quill.HorizontalSpacing(0, 0),
                const quill.VerticalSpacing(4, 0),
                const quill.VerticalSpacing(0, 0),
                null),
              h1: quill.DefaultTextBlockStyle(
                GoogleFonts.inter(fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF111827), height: 1.3),
                const quill.HorizontalSpacing(0, 0),
                const quill.VerticalSpacing(16, 6),
                const quill.VerticalSpacing(0, 0),
                null),
              h2: quill.DefaultTextBlockStyle(
                GoogleFonts.inter(fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937), height: 1.35),
                const quill.HorizontalSpacing(0, 0),
                const quill.VerticalSpacing(12, 4),
                const quill.VerticalSpacing(0, 0),
                null),
              h3: quill.DefaultTextBlockStyle(
                GoogleFonts.inter(fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151), height: 1.4),
                const quill.HorizontalSpacing(0, 0),
                const quill.VerticalSpacing(10, 3),
                const quill.VerticalSpacing(0, 0),
                null),
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Docx reader (no external lib — just unzip + parse XML) ───────────────────

class DocxReader {
  /// Extract plain text from a .docx file using the archive package.
  /// .docx is a ZIP containing word/document.xml
  static Future<String> extractFromBytes(List<int> bytes) async {
    return _parse(bytes);
  }

  static Future<String> extract(String path) async {
    try {
      // Use platform-safe read
      List<int>? bytes;
      if (kIsWeb) {
        bytes = PlatformFileService.getCached(path);
      } else {
        bytes = await PlatformFileService.readBytes(path);
      }
      if (bytes == null) return '';
      return _parse(bytes);
    } catch (_) { return ''; }
  }

  static String _parse(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final xmlFile = archive.findFile('word/document.xml');
      if (xmlFile == null) return '';

      final xml = utf8.decode(xmlFile.content as List<int>);

      // Extract text from <w:t> tags (Word text runs)
      final tPattern = RegExp(r'<w:t[^>]*>([^<]*)</w:t>',
          multiLine: true);
      final pPattern = RegExp(r'<w:p[ />]', multiLine: true);

      final buf = StringBuffer();
      int lastPPos = 0;

      // Process paragraph by paragraph
      for (final pMatch in pPattern.allMatches(xml)) {
        // Find end of this paragraph (next </w:p>)
        final pEnd = xml.indexOf('</w:p>', pMatch.start);
        if (pEnd == -1) continue;
        final para = xml.substring(pMatch.start, pEnd);

        bool hasText = false;
        for (final tMatch in tPattern.allMatches(para)) {
          final text = tMatch.group(1)?.trim() ?? '';
          if (text.isNotEmpty) {
            buf.write(text);
            buf.write(' ');
            hasText = true;
          }
        }
        if (hasText) buf.write('\n');
        lastPPos = pEnd;
      }

      return buf.toString().trim();
    } catch (e) {
      return '';
    }
  }
}

// ── Toolbar widgets ───────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final IconData icon; final bool active;
  final VoidCallback onTap; final String tip;
  final Color tint;
  const _Btn(this.icon, this.active, this.tip, this.onTap,
      {this.tint = const Color(0xFF6366F1)});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: GestureDetector(onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: active ? tint.withOpacity(0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: active ? Border.all(color: tint.withOpacity(0.55)) : null),
        child: Icon(icon, size: 19,
            color: active ? tint : Colors.white.withOpacity(0.6)),
      ),
    ),
  );
}

class _StyleDrop extends StatelessWidget {
  final void Function(int) onSelect;
  const _StyleDrop({required this.onSelect});
  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    color: const Color(0xFF1A1A2E), offset: const Offset(0, 38),
    onSelected: onSelect,
    child: _dropChip('Style'),
    itemBuilder: (_) => [
      PopupMenuItem(value: 0, child: Text('Body',
          style: GoogleFonts.inter(color: Colors.white.withOpacity(0.8), fontSize: 13))),
      PopupMenuItem(value: 1, child: Text('Heading 1',
          style: GoogleFonts.inter(color: Colors.white.withOpacity(0.8), fontSize: 20, fontWeight: FontWeight.bold))),
      PopupMenuItem(value: 2, child: Text('Heading 2',
          style: GoogleFonts.inter(color: Colors.white.withOpacity(0.8), fontSize: 16, fontWeight: FontWeight.bold))),
      PopupMenuItem(value: 3, child: Text('Heading 3',
          style: GoogleFonts.inter(color: Colors.white.withOpacity(0.8), fontSize: 14, fontWeight: FontWeight.w600))),
    ],
  );
}

class _SizeDrop extends StatelessWidget {
  final double current; final void Function(double) onSelect;
  const _SizeDrop({required this.current, required this.onSelect});
  @override
  Widget build(BuildContext context) => PopupMenuButton<double>(
    color: const Color(0xFF1A1A2E), offset: const Offset(0, 38),
    onSelected: onSelect,
    child: _dropChip('${current.toInt()}'),
    itemBuilder: (_) => [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32]
        .map((sz) => PopupMenuItem(value: sz.toDouble(),
          child: Text('$sz', style: GoogleFonts.inter(
              color: sz == current.toInt()
                  ? const Color(0xFF6366F1)
                  : Colors.white.withOpacity(0.8),
              fontSize: 13,
              fontWeight: sz == current.toInt()
                  ? FontWeight.bold : FontWeight.normal))))
        .toList(),
  );
}

Widget _dropChip(String label) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(6)),
  child: Row(mainAxisSize: MainAxisSize.min, children: [
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Colors.white38),
  ]),
);
