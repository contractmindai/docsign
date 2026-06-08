import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import '../widgets/apple_dialog.dart';
import '../utils/app_localizations.dart'; // for AppLocalizations

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
  String _watermarkText = 'CONFIDENTIAL';
  final Map<int, Uint8List?> _pageThumbnails = {};

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      if (widget.document != null) {
        _doc = widget.document;
        _pageCount = _doc!.pages.length;
      } else if (widget.fileBytes != null && widget.fileBytes!.isNotEmpty) {
        _doc = await pdfrx.PdfDocument.openData(widget.fileBytes!);
        _pageCount = _doc!.pages.length;
      } else if (widget.filePath.isNotEmpty) {
        Uint8List? bytes = PlatformFileService.getCached(widget.filePath);
        if (bytes == null && !kIsWeb) {
          final file = File(widget.filePath);
          if (await file.exists()) bytes = await file.readAsBytes();
        }
        if (bytes == null) {
          final name = widget.filePath.split('/').last;
          bytes = PlatformFileService.getCached(name);
        }
        if (bytes != null && bytes.isNotEmpty) {
          _doc = await pdfrx.PdfDocument.openData(bytes);
          _pageCount = _doc!.pages.length;
        } else {
          if (mounted) _snack(AppLocalizations.of(context)!.cannotOpenFile, err: true);
        }
      }
    } catch (e) {
      debugPrint('Error loading PDF in tools: $e');
      if (mounted) _snack('${AppLocalizations.of(context)!.error}: $e', err: true);
    }
    if (mounted) setState(() => _loading = false);
  }

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

  void _finish(Uint8List bytes, String name) async {
    final path = await _saveOutput(bytes, name);
    if (mounted) {
      Navigator.pop(context, {
        'path': path,
        'bytes': bytes,
      });
    }
  }

  Future<bool> _checkSize(String op, {int warn = 20, int max = 80}) async {
    final l10n = AppLocalizations.of(context)!;
    if (_pageCount <= warn) return true;
    if (_pageCount > max) {
      _snack('${l10n.maxPages} $max', err: true);
      return false;
    }
    return await AppleDialog.show<bool>(
      context: context,
      title: l10n.largeDocument,
      content: '$_pageCount ${l10n.pages} $op ${l10n.mayBeSlow}',
      actions: [
        AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context, false)),
        AppleDialogAction(label: l10n.continue_, onPressed: () => Navigator.pop(context, true)),
      ],
    ) ?? false;
  }

  // ═══ MERGE ═══
  Future<void> _mergePdfs() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null) return;
    if (!await _checkSize(l10n.merging, warn: 15, max: 50)) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true, withData: kIsWeb);
    if (result == null || result.files.isEmpty) return;
    _showProgress(l10n.merging);
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
      if (mounted) {
        Navigator.pop(context);
        _finish(bytes, 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${l10n.error}: $e', err: true); }
    }
  }

  // ═══ EXTRACT ═══
  Future<void> _extractPages() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null || _selectedPages.isEmpty) { _snack(l10n.selectPages, err: true); return; }
    if (_selectedPages.length > 30) { _snack('${l10n.maxPages} 30', err: true); return; }
    _showProgress(l10n.extracting);
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
      if (mounted) {
        Navigator.pop(context);
        _finish(bytes, 'extract_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${l10n.error}: $e', err: true); }
    }
  }

  // ═══ ROTATE ═══
  Future<void> _rotateSelected() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null || _selectedPages.isEmpty) {
      _snack(l10n.selectPages, err: true);
      return;
    }

    _showProgress(l10n.rotating);

    try {
      final doc = pw.Document();

      for (int i = 0; i < _pageCount; i++) {
        final page = _doc!.pages[i];
        final bool shouldRotate = _selectedPages.contains(i);

        final renderWidth = (page.width * 2).clamp(0.0, 3000.0);
        final renderHeight = (page.height * 2).clamp(0.0, 4000.0);
        final rendered = await page.render(
          fullWidth: renderWidth,
          fullHeight: renderHeight,
          backgroundColor: Colors.white,
        );
        if (rendered == null) continue;

        Uint8List? png = await _pdfImageToPng(rendered);
        if (png == null) continue;

        if (shouldRotate) {
          png = await _rotateImage90(png!);
        }

        final pageFormat = shouldRotate
            ? PdfPageFormat(page.height, page.width)
            : PdfPageFormat(page.width, page.height);

        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(pw.MemoryImage(png!), fit: pw.BoxFit.fill),
          ),
        );
      }

      final bytes = Uint8List.fromList(await doc.save());
      if (mounted) {
        Navigator.pop(context);
        _finish(bytes, 'rotated.pdf');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _snack('${l10n.rotateFailed}: $e', err: true);
      }
    }
  }

  Future<Uint8List> _rotateImage90(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.translate(image.height.toDouble(), 0);
    canvas.rotate(1.5708);
    canvas.drawImage(image, Offset.zero, Paint());

    final picture = recorder.endRecording();
    final rotatedImage = await picture.toImage(image.height, image.width);
    final byteData = await rotatedImage.toByteData(format: ui.ImageByteFormat.png);
    rotatedImage.dispose();
    image.dispose();

    return byteData!.buffer.asUint8List();
  }

  // ═══ WATERMARK ═══
  Future<void> _addWatermark() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null) return;
    if (!await _checkSize(l10n.watermarking, warn: 25, max: 80)) return;
    final ctrl = TextEditingController(text: _watermarkText);
    bool applyAll = true;
    Color selectedColor = Colors.red;

    final input = await AppleDialog.show<Map>(
      context: context,
      title: l10n.watermark,
      child: StatefulBuilder(
        builder: (__, setSt) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: l10n.watermarkHint,
                filled: true,
                fillColor: DS.bgCard2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text(l10n.textColor, style: const TextStyle(color: Colors.white60)),
              const SizedBox(width: 12),
              ..._buildTextColorSwatches(selectedColor, (color) {
                setSt(() => selectedColor = color);
              }),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Text(l10n.apply, style: const TextStyle(color: Colors.white60)),
              const Spacer(),
              ChoiceChip(
                label: Text(l10n.all),
                selected: applyAll,
                onSelected: (_) => setSt(() => applyAll = true),
                backgroundColor: Colors.white10,
                selectedColor: DS.indigo.withOpacity(0.3),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('${l10n.selected} (${_selectedPages.length})'),
                selected: !applyAll,
                onSelected: (_) => setSt(() => applyAll = false),
                backgroundColor: Colors.white10,
                selectedColor: DS.indigo.withOpacity(0.3),
              ),
            ]),
          ],
        ),
      ),
      actions: [
        AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context)),
        AppleDialogAction(
          label: l10n.apply,
          onPressed: () => Navigator.pop(context, {'text': ctrl.text, 'all': applyAll, 'color': selectedColor}),
        ),
      ],
    );

    if (input == null || input['text'].toString().isEmpty) return;
    _showProgress(l10n.watermarking);
    try {
      final doc = pw.Document();
      final watermarkText = input['text'] as String;
      final bool applyToAll = input['all'] as bool;
      final Color selectedWatermarkColor = input['color'] as Color;
      final pdfColor = PdfColor(selectedWatermarkColor.red / 255, selectedWatermarkColor.green / 255, selectedWatermarkColor.blue / 255, 0.15);
      for (int i = 0; i < _pageCount; i++) {
        final img = await _doc!.pages[i].render(fullWidth: _doc!.pages[i].width * 2, fullHeight: _doc!.pages[i].height * 2, backgroundColor: Colors.white);
        if (img == null) continue;
        final png = await _pdfImageToPng(img);
        if (png == null) continue;
        final bool mark = applyToAll || _selectedPages.contains(i);
        final children = <pw.Widget>[pw.Image(pw.MemoryImage(png))];
        if (mark) {
          children.add(pw.Center(child: pw.Transform.rotate(angle: -0.4,
              child: pw.Text(watermarkText, style: pw.TextStyle(fontSize: 60, color: pdfColor, fontWeight: pw.FontWeight.bold)))));
        }
        doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].width, _doc!.pages[i].height), margin: pw.EdgeInsets.zero, build: (_) => pw.Stack(children: children)));
      }
      final bytes = Uint8List.fromList(await doc.save());
      if (mounted) {
        Navigator.pop(context);
        _finish(bytes, 'wm_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${l10n.error}: $e', err: true); }
    }
  }

  List<Widget> _buildTextColorSwatches(Color current, ValueChanged<Color> onChanged) {
    final colors = [
      Colors.red, Colors.blue, Colors.green, Colors.black,
      Colors.purple, Colors.orange, DS.indigo, Colors.white,
    ];
    return colors.map((c) {
      final isSelected = c == current;
      return GestureDetector(
        onTap: () => onChanged(c),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSelected ? Border.all(color: DS.indigo, width: 2) : null,
          ),
          child: Center(
            child: Text(
              'A',
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  // ═══ DUPLICATE ═══
  Future<void> _duplicatePage(int pageIndex) async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null) return;
    if (!await _checkSize(l10n.duplicating, warn: 10, max: 40)) return;
    final pages = _selectedPages.isNotEmpty ? (_selectedPages.toList()..sort()) : [pageIndex];
    _showProgress(l10n.duplicating);
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
      if (mounted) {
        Navigator.pop(context);
        _finish(bytes, 'dup_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${l10n.error}: $e', err: true); }
    }
  }

  // ═══ QR CODE ═══
  Future<void> _addQrCode() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null) return;
    final ctrl = TextEditingController();
    final text = await AppleDialog.show<String>(
      context: context,
      title: l10n.qrCode,
      child: TextField(
        controller: ctrl,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: l10n.qrHint,
          filled: true,
          fillColor: DS.bgCard2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context)),
        AppleDialogAction(
          label: l10n.generate,
          onPressed: () => Navigator.pop(context, ctrl.text),
          isDestructive: false,
        ),
      ],
    );
    if (text == null || text.isEmpty) return;
    _showProgress(l10n.addingQr);
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
        doc.addPage(pw.Page(pageFormat: PdfPageFormat(_doc!.pages[i].width, _doc!.pages[i].height), margin: pw.EdgeInsets.zero, build: (_) => pw.Stack(children: [
          pw.Image(pw.MemoryImage(pagePng)),
          pw.Positioned(right: 20, bottom: 20, child: pw.Container(width: 80, height: 80, padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Image(pw.MemoryImage(Uint8List.view(pngBytes.buffer)), fit: pw.BoxFit.contain)))
        ])));
      }
      final bytes = Uint8List.fromList(await doc.save());
      if (mounted) {
        Navigator.pop(context);
        _finish(bytes, 'qr_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${l10n.error}: $e', err: true); }
    }
  }

  void _showProgress(String m) => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: DS.bgCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo)),
            const SizedBox(height: 12),
            Text(m, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    ),
  );

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

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: err ? DS.red : DS.bgCard2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _toggle(int i) => setState(() { _selectedPages.contains(i) ? _selectedPages.remove(i) : _selectedPages.add(i); });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(l10n.pdfTools, style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DS.indigo))
          : _pageCount == 0
              ? Center(child: Text(l10n.noPdfLoaded, style: DS.body(size: 16)))
              : Column(children: [
                  _buildTools(l10n),
                  const Divider(color: DS.separator),
                  Expanded(child: _buildGrid(l10n)),
                  if (_selectedPages.isNotEmpty) _buildBottom(l10n),
                ]),
    );
  }

  Widget _buildTools(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.all(16),
    child: Wrap(spacing: 10, runSpacing: 10, children: [
      _card(l10n.merge, Icons.merge_rounded, DS.indigo, _mergePdfs),
      _card(l10n.extract, Icons.content_cut_rounded, DS.orange, _extractPages),
      _card(l10n.rotate, Icons.rotate_right_rounded, DS.green, _rotateSelected),
      _card(l10n.watermark, Icons.branding_watermark_rounded, DS.red, _addWatermark),
      _card(l10n.duplicate, Icons.copy_rounded, DS.cyan, () => _duplicatePage(0)),
      _card(l10n.qrCode, Icons.qr_code_rounded, DS.green, _addQrCode),
    ]),
  );

  Widget _card(String l, IconData i, Color c, VoidCallback t) => ScaleTap(
    onTap: t,
    child: Container(
      width: 105, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withOpacity(0.12), c.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Column(children: [
        Icon(i, color: c, size: 28),
        const SizedBox(height: 6),
        Text(l, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      ]),
    ),
  );

  Widget _buildGrid(AppLocalizations l10n) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.72),
      itemCount: _pageCount,
      itemBuilder: (_, i) {
        final sel = _selectedPages.contains(i);
        final thumbnail = _pageThumbnails[i];
        if (!_pageThumbnails.containsKey(i)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadPageThumbnail(i));
        }
        return InkWell(
          onTap: () => _toggle(i),
          onLongPress: () => _duplicatePage(i),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sel ? DS.indigo : Colors.grey.withOpacity(0.2), width: sel ? 2.5 : 1),
            ),
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: thumbnail != null
                    ? Image.memory(thumbnail, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                    : Container(color: Colors.grey[50], child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo)))),
              ),
              Positioned(bottom: 4, left: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)))),
              if (sel)
                Positioned(top: 4, right: 4, child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: DS.indigo, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size: 14))),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildBottom(AppLocalizations l10n) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: DS.bgCard, border: Border(top: BorderSide(color: DS.separator))),
    child: Row(children: [
      Text('${_selectedPages.length} ${l10n.selected}', style: const TextStyle(color: Colors.white, fontSize: 13)),
      const Spacer(),
      ScaleTap(
        onTap: _extractPages,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: DS.indigo,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            const Icon(Icons.content_cut_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(l10n.extract, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]),
  );

  Future<void> _loadPageThumbnail(int pageIndex) async {
    if (_pageThumbnails.containsKey(pageIndex)) return;
    if (_doc == null) return;
    try {
      final page = _doc!.pages[pageIndex];
      final thumbWidth = 200.0;
      final thumbHeight = thumbWidth / (page.width / page.height);
      final img = await page.render(fullWidth: thumbWidth, fullHeight: thumbHeight, backgroundColor: Colors.white);
      if (img == null || !mounted) return;
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
        setState(() { _pageThumbnails[pageIndex] = bd.buffer.asUint8List(); });
      }
    } catch (e) { debugPrint('Thumbnail error: $e'); }
  }
}