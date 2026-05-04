import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import 'pdf_viewer_screen.dart';

class PdfToolsScreen extends StatefulWidget {
  final String filePath;
  final Uint8List? fileBytes;
  final pdfrx.PdfDocument? document;

  const PdfToolsScreen({
    super.key,
    required this.filePath,
    this.fileBytes,
    this.document,
  });

  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  pdfrx.PdfDocument? _doc;
  int _pageCount = 0;
  bool _loading = true;
  final Set<int> _selectedPages = {};
  int _rotation = 0;
  String _watermarkText = 'CONFIDENTIAL';
  final Map<int, Uint8List?> _pageThumbnails = {};

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      // ✅ PRIORITY 1: Already have document object
      if (widget.document != null) {
        _doc = widget.document;
        _pageCount = _doc!.pages.length;
        if (mounted) setState(() => _loading = false);
        return;
      }
      
      // ✅ PRIORITY 2: Have bytes directly
      if (widget.fileBytes != null && widget.fileBytes!.isNotEmpty) {
        _doc = await pdfrx.PdfDocument.openData(widget.fileBytes!);
        _pageCount = _doc!.pages.length;
        if (mounted) setState(() => _loading = false);
        return;
      }
      
      // ✅ PRIORITY 3: Load from file path
      if (widget.filePath.isNotEmpty) {
        Uint8List? bytes;
        
        // Try cache first
        bytes = PlatformFileService.getCached(widget.filePath);
        
        // Try reading from disk
        if (bytes == null && !kIsWeb) {
          final file = File(widget.filePath);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
          }
        }
        
        // Try multiple cached keys
        if (bytes == null) {
          final name = widget.filePath.split('/').last;
          bytes = PlatformFileService.getCached(name);
        }
        
        if (bytes != null && bytes.isNotEmpty) {
          _doc = await pdfrx.PdfDocument.openData(bytes);
          _pageCount = _doc!.pages.length;
        } else {
          if (mounted) _snack('Cannot open file', err: true);
        }
      }
    } catch (e) {
      debugPrint('Error loading PDF in tools: $e');
      if (mounted) _snack('Error: $e', err: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  // ✅ Save tool output properly for both web and mobile
  Future<String> _saveOutput(Uint8List bytes, String name) async {
    PlatformFileService.cache(name, bytes);
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$name';
      await File(path).writeAsBytes(bytes);
      PlatformFileService.cache(path, bytes);
      return path;
    }
    return name;
  }

  void _openResult(Uint8List bytes, String name, {bool replace = false}) {
    final route = MaterialPageRoute(
      builder: (_) => PdfViewerScreen(filePath: name, preloadedBytes: bytes));
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  }

  // ═══ SIZE GUARD ═══
  Future<bool> _checkSize(String op, {int warn = 20, int max = 80}) async {
    if (_pageCount <= warn) return true;
    if (_pageCount > max) { _snack('Max $max pages', err: true); return false; }
    return await showDialog<bool>(context: context, builder: (_) => AlertDialog(backgroundColor: DS.bgCard, title: const Text('Large Document', style: TextStyle(color: Colors.white)), content: Text('$_pageCount pages. $op may be slow.', style: const TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: DS.indigo), child: const Text('Continue'))])) ?? false;
  }

  // ═══ MERGE ═══
  Future<void> _mergePdfs() async {
    if (_doc == null) return;
    if (!await _checkSize('Merging', warn: 15, max: 50)) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true, withData: kIsWeb);
    if (result == null || result.files.isEmpty) return;
    _showProgress('Merging...');
    try {
      final merged = pw.Document();
      Future<void> addDoc(pdfrx.PdfDocument d) async {
        for (final p in d.pages) {
          final img = await p.render(fullWidth: p.width * 2, fullHeight: p.height * 2, backgroundColor: Colors.white);
          if (img == null) continue;
          final png = await _pdfImageToPng(img);
          if (png == null) continue;
          merged.addPage(pw.Page(pageFormat: PdfPageFormat(p.width, p.height), margin: pw.EdgeInsets.zero, build: (_) => pw.Image(pw.MemoryImage(png))));
        }
      }
      await addDoc(_doc!);
      for (final f in result.files) {
        final b = kIsWeb ? f.bytes! : (await PlatformFileService.readBytes(f.path!) ?? Uint8List(0));
        final d = await pdfrx.PdfDocument.openData(b);
        await addDoc(d);
        d.dispose();
      }
      final bytes = Uint8List.fromList(await merged.save());
      final path = await _saveOutput(bytes, 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) { Navigator.pop(context); _openResult(bytes, path, replace: true); }
    } catch (e) { if (mounted) _snack('Error: $e', err: true); Navigator.pop(context); }
  }

  // ═══ EXTRACT ═══
  Future<void> _extractPages() async {
    if (_doc == null || _selectedPages.isEmpty) { _snack('Select pages', err: true); return; }
    if (_selectedPages.length > 30) { _snack('Max 30 pages', err: true); return; }
    _showProgress('Extracting...');
    try {
      final doc = pw.Document();
      for (final i in _selectedPages.toList()..sort()) {
        final img = await _doc!.pages[i].render(fullWidth: _doc!.pages[i].width * 2, fullHeight: _doc!.pages[i].height * 2, backgroundColor: Colors.white);
        if (img == null) continue;
        final png = await _pdfImageToPng(img);
        if (png == null) continue;
        doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].width, _doc!.pages[i].height), margin: pw.EdgeInsets.zero, build: (_) => pw.Image(pw.MemoryImage(png))));
      }
      final bytes = Uint8List.fromList(await doc.save());
      final path = await _saveOutput(bytes, 'extract_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) { Navigator.pop(context); _openResult(bytes, path); }
    } catch (e) { if (mounted) _snack('Error: $e', err: true); Navigator.pop(context); }
  }

  // ═══ ROTATE ═══
  Future<void> _rotateSelected() async {
    if (_doc == null || _selectedPages.isEmpty) { _snack('Select pages', err: true); return; }
    if (!await _checkSize('Rotating', warn: 30)) return;
    _showProgress('Rotating...');
    _rotation = (_rotation + 90) % 360;
    try {
      final doc = pw.Document();
      for (int i = 0; i < _pageCount; i++) {
        final img = await _doc!.pages[i].render(fullWidth: _doc!.pages[i].width * 2, fullHeight: _doc!.pages[i].height * 2, backgroundColor: Colors.white);
        if (img == null) continue;
        final png = await _pdfImageToPng(img);
        if (png == null) continue;
        if (_selectedPages.contains(i)) {
          doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].height, _doc!.pages[i].width), margin: pw.EdgeInsets.zero, build: (_) => pw.Center(child: pw.Transform.rotate(angle: 1.5708, child: pw.Image(pw.MemoryImage(png), width: _doc!.pages[i].height, height: _doc!.pages[i].width, fit: pw.BoxFit.contain)))));
        } else {
          doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].width, _doc!.pages[i].height), margin: pw.EdgeInsets.zero, build: (_) => pw.Image(pw.MemoryImage(png))));
        }
      }
      final bytes = Uint8List.fromList(await doc.save());
      final path = await _saveOutput(bytes, 'rotated_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) { Navigator.pop(context); _openResult(bytes, path, replace: true); }
    } catch (e) { if (mounted) { Navigator.pop(context); _snack('Error: $e', err: true); } }
  }

  // ═══ WATERMARK ═══
  Future<void> _addWatermark() async {
    if (_doc == null) return;
    if (!await _checkSize('Watermarking', warn: 25, max: 80)) return;
    final ctrl = TextEditingController(text: _watermarkText);
    bool applyAll = true;
    final input = await showDialog<Map>(context: context, builder: (_) => StatefulBuilder(builder: (__, setSt) => AlertDialog(backgroundColor: DS.bgCard, title: const Text('Watermark', style: TextStyle(color: Colors.white)), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'e.g. CONFIDENTIAL', filled: true, fillColor: DS.bgCard2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))), const SizedBox(height: 12), Row(children: [const Text('Apply:', style: TextStyle(color: Colors.white60)), const Spacer(), ChoiceChip(label: const Text('All'), selected: applyAll, onSelected: (_) => setSt(() => applyAll = true)), const SizedBox(width: 8), ChoiceChip(label: Text('Sel (${_selectedPages.length})'), selected: !applyAll, onSelected: (_) => setSt(() => applyAll = false))])]), actions: [TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(_, {'text': ctrl.text, 'all': applyAll}), style: FilledButton.styleFrom(backgroundColor: DS.indigo), child: const Text('Apply'))])));
    if (input == null || input['text'].toString().isEmpty) return;
    _showProgress('Watermarking...');
    try {
      final doc = pw.Document();
      for (int i = 0; i < _pageCount; i++) {
        final img = await _doc!.pages[i].render(fullWidth: _doc!.pages[i].width * 2, fullHeight: _doc!.pages[i].height * 2, backgroundColor: Colors.white);
        if (img == null) continue;
        final png = await _pdfImageToPng(img);
        if (png == null) continue;
        final mark = (input['all'] == true) || _selectedPages.contains(i);
        final children = <pw.Widget>[pw.Image(pw.MemoryImage(png))];
        if (mark) children.add(pw.Center(child: pw.Transform.rotate(angle: -0.4, child: pw.Text(input['text'], style: pw.TextStyle(fontSize: 60, color: const PdfColor(1, 0, 0, 0.15), fontWeight: pw.FontWeight.bold)))));
        doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].width, _doc!.pages[i].height), margin: pw.EdgeInsets.zero, build: (_) => pw.Stack(children: children)));
      }
      final bytes = Uint8List.fromList(await doc.save());
      final path = await _saveOutput(bytes, 'wm_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) { Navigator.pop(context); _openResult(bytes, path); }
    } catch (e) { if (mounted) { Navigator.pop(context); _snack('Error: $e', err: true); } }
  }

  // ═══ DUPLICATE ═══
  Future<void> _duplicatePage(int pageIndex) async {
    if (_doc == null) return;
    if (!await _checkSize('Duplicating', warn: 10, max: 40)) return;
    final pages = _selectedPages.isNotEmpty ? (_selectedPages.toList()..sort()) : [pageIndex];
    _showProgress('Duplicating...');
    try {
      final doc = pw.Document();
      for (int i = 0; i < _pageCount; i++) {
        final img = await _doc!.pages[i].render(fullWidth: _doc!.pages[i].width * 2, fullHeight: _doc!.pages[i].height * 2, backgroundColor: Colors.white);
        if (img == null) continue;
        final png = await _pdfImageToPng(img);
        if (png == null) continue;
        doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].width, _doc!.pages[i].height), margin: pw.EdgeInsets.zero, build: (_) => pw.Image(pw.MemoryImage(png))));
        if (pages.contains(i)) doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].width, _doc!.pages[i].height), margin: pw.EdgeInsets.zero, build: (_) => pw.Image(pw.MemoryImage(png))));
      }
      final bytes = Uint8List.fromList(await doc.save());
      final path = await _saveOutput(bytes, 'dup_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) { Navigator.pop(context); _openResult(bytes, path); }
    } catch (e) { if (mounted) { Navigator.pop(context); _snack('Error: $e', err: true); } }
  }

  // ═══ QR CODE ═══
  Future<void> _addQrCode() async {
    if (_doc == null) return;
    final ctrl = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (_) => AlertDialog(backgroundColor: DS.bgCard, title: const Text('QR Code', style: TextStyle(color: Colors.white)), content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'URL or payment link', filled: true, fillColor: DS.bgCard2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), style: FilledButton.styleFrom(backgroundColor: DS.green), child: const Text('Generate'))]));
    if (text == null || text.isEmpty) return;
    _showProgress('Adding QR...');
    try {
      final qr = QrPainter(data: text, version: QrVersions.auto, color: Colors.black, emptyColor: Colors.white);
      final rec = ui.PictureRecorder();
      qr.paint(Canvas(rec, Rect.fromLTWH(0, 0, 200, 200)), const Size(200, 200));
      final pic = rec.endRecording();
      final img = await pic.toImage(200, 200);
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (pngBytes == null) { Navigator.pop(context); return; }
      final doc = pw.Document();
      for (int i = 0; i < _pageCount; i++) {
        final pageImg = await _doc!.pages[i].render(fullWidth: _doc!.pages[i].width * 2, fullHeight: _doc!.pages[i].height * 2, backgroundColor: Colors.white);
        if (pageImg == null) continue;
        final pagePng = await _pdfImageToPng(pageImg);
        if (pagePng == null) continue;
        doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].width, _doc!.pages[i].height), margin: pw.EdgeInsets.zero, build: (_) => pw.Stack(children: [pw.Image(pw.MemoryImage(pagePng)), pw.Positioned(right: 20, bottom: 20, child: pw.Container(width: 80, height: 80, padding: const pw.EdgeInsets.all(4), decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(4)), child: pw.Image(pw.MemoryImage(Uint8List.view(pngBytes.buffer)), fit: pw.BoxFit.contain)))])));
      }
      final bytes = Uint8List.fromList(await doc.save());
      final path = await _saveOutput(bytes, 'qr_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) { Navigator.pop(context); _openResult(bytes, path); }
    } catch (e) { if (mounted) { Navigator.pop(context); _snack('Error: $e', err: true); } }
  }

  // ═══ HELPERS ═══
  void _showProgress(String m) => showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(backgroundColor: DS.bgCard, content: Row(children: [const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo)), const SizedBox(width: 16), Text(m, style: const TextStyle(color: Colors.white))])));

  Future<Uint8List?> _pdfImageToPng(pdfrx.PdfImage img) async {
    try {
      final p = img.pixels;
      final c = Uint8List(p.length);
      for (int i = 0; i < p.length; i += 4) { c[i] = p[i + 2]; c[i + 1] = p[i + 1]; c[i + 2] = p[i]; c[i + 3] = p[i + 3]; }
      final comp = Completer<ui.Image>();
      ui.decodeImageFromPixels(c, img.width, img.height, ui.PixelFormat.rgba8888, (i) => comp.complete(i));
      final uiImg = await comp.future;
      final bd = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      uiImg.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) { return null; }
  }

  void _snack(String m, {bool err = false}) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(color: Colors.white, fontSize: 13)), backgroundColor: err ? DS.red : DS.bgCard2, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2))); }

  void _toggle(int i) => setState(() { _selectedPages.contains(i) ? _selectedPages.remove(i) : _selectedPages.add(i); });

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: DS.bg, appBar: AppBar(backgroundColor: DS.bgCard, elevation: 0, surfaceTintColor: Colors.transparent, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20), onPressed: () => Navigator.pop(context)), title: Text('PDF Tools', style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)), centerTitle: true), body: _loading ? const Center(child: CircularProgressIndicator(color: DS.indigo)) : _pageCount == 0 ? Center(child: Text('No PDF loaded', style: DS.body(size: 16))) : Column(children: [_buildTools(), const Divider(color: DS.separator), Expanded(child: _buildGrid()), if (_selectedPages.isNotEmpty) _buildBottom()]));

  Widget _buildTools() => Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 10, runSpacing: 10, children: [_card('Merge', Icons.merge_rounded, DS.indigo, _mergePdfs), _card('Extract', Icons.content_cut_rounded, DS.orange, _extractPages), _card('Rotate', Icons.rotate_right_rounded, DS.green, _rotateSelected), _card('Watermark', Icons.branding_watermark_rounded, DS.red, _addWatermark), _card('Duplicate', Icons.copy_rounded, DS.cyan, () => _duplicatePage(0)), _card('QR Code', Icons.qr_code_rounded, DS.green, _addQrCode)]));

  Widget _card(String l, IconData i, Color c, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 105, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.3))), child: Column(children: [Icon(i, color: c, size: 28), const SizedBox(height: 6), Text(l, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)])));

    Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: _pageCount,
      itemBuilder: (_, i) {
        final sel = _selectedPages.contains(i);
        final thumbnail = _pageThumbnails[i];
        
        // Load thumbnail if needed
        if (!_pageThumbnails.containsKey(i)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadPageThumbnail(i));
        }
        
        return GestureDetector(
          onTap: () => _toggle(i),
          onLongPress: () => _duplicatePage(i),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: sel ? DS.indigo : Colors.grey.withOpacity(0.2),
                width: sel ? 2.5 : 1,
              ),
            ),
            child: Stack(children: [
              // ✅ Show thumbnail or loading spinner
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: thumbnail != null
                    ? Image.memory(thumbnail, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                    : Container(
                        color: Colors.grey[50],
                        child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo))),
                      ),
              ),
              // Page number badge
              Positioned(
                bottom: 4, left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ),
              // Checkmark
              if (sel)
                Positioned(
                  top: 4, right: 4,
                  child: Container(
                    width: 22, height: 22,
                    decoration: const BoxDecoration(color: DS.indigo, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Colors.white, size: 14),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
  Widget _buildBottom() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: DS.bgCard, border: Border(top: BorderSide(color: DS.separator))), child: Row(children: [Text('${_selectedPages.length} selected', style: const TextStyle(color: Colors.white, fontSize: 13)), const Spacer(), PrimaryButton(label: 'Extract', icon: Icons.content_cut_rounded, onTap: _extractPages, height: 38)]));

 Future<void> _loadPageThumbnail(int pageIndex) async {
    if (_pageThumbnails.containsKey(pageIndex)) return;
    if (_doc == null) return;
    
    try {
      final page = _doc!.pages[pageIndex];
      final thumbWidth = 200.0;
      final thumbHeight = thumbWidth / (page.width / page.height);
      
      final img = await page.render(
        fullWidth: thumbWidth,
        fullHeight: thumbHeight,
        backgroundColor: Colors.white,
      );
      
      if (img == null || !mounted) return;
      
      // Convert to PNG
      final pixels = img.pixels;
      final converted = Uint8List(pixels.length);
      for (int j = 0; j < pixels.length; j += 4) {
        converted[j] = pixels[j + 2];
        converted[j + 1] = pixels[j + 1];
        converted[j + 2] = pixels[j];
        converted[j + 3] = pixels[j + 3];
      }
      
      final comp = Completer<ui.Image>();
      ui.decodeImageFromPixels(converted, img.width, img.height, ui.PixelFormat.rgba8888, (i) => comp.complete(i));
      final uiImg = await comp.future;
      final bd = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      uiImg.dispose();
      
      if (bd != null && mounted) {
        setState(() {
          _pageThumbnails[pageIndex] = bd.buffer.asUint8List();
        });
      }
    } catch (e) {
      debugPrint('Thumbnail error: $e');
    }
  }
}