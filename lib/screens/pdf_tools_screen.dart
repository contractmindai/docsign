import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:file_selector/file_selector.dart';
import 'package:cross_file/cross_file.dart';
import 'package:image/image.dart' as img;

import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import '../widgets/apple_dialog.dart';
import '../utils/app_localizations.dart';
import 'pdf_tool_kind.dart';

class PdfToolsScreen extends StatefulWidget {
  final String filePath;
  final Uint8List? fileBytes;
  final dynamic document;
  final PdfToolKind? initialTool;

  const PdfToolsScreen({
    super.key,
    required this.filePath,
    this.fileBytes,
    this.document,
    this.initialTool,
  });

  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  Pdf? _pdf;
  dynamic _doc;
  int _pageCount = 0;
  bool _loading = true;
  final Set<int> _selectedPages = {};
  String _watermarkText = 'CONFIDENTIAL';
  final Map<int, Uint8List> _pageThumbnails = {};
  late PdfToolKind? _focusedTool;

  String? _resultPath;
  Uint8List? _resultBytes;
  bool get _hasChanges => _resultBytes != null;
  int _thumbnailGeneration = 0;

  // ------------------------------------------------------------------
  //  Helper: convert any exception to a user‑friendly string
  // ------------------------------------------------------------------
  String _userFriendlyError(dynamic e) {
    if (e is PdfCancelled) return '';
    if (e is PdfError) {
      final msg = e.message.toLowerCase();
      if (msg.contains('password')) {
        return 'The PDF is password‑protected. Please provide a password.';
      } else if (msg.contains('corrupt') || msg.contains('invalid')) {
        return 'The PDF appears to be corrupted. Try re‑exporting it.';
      } else if (msg.contains('not found')) {
        return 'The file could not be found.';
      } else {
        return 'A PDF error occurred: ${e.message}';
      }
    }
    if (e is FormatException) {
      return 'The file format is not recognised. Please select a valid PDF.';
    }
    if (e is FileSystemException) {
      return 'Unable to access the file. Check permissions or storage.';
    }
    if (e is StateError) {
      return 'Something went wrong with the PDF state. Please restart the tool.';
    }
    debugPrint('Unexpected error: $e');
    return 'Something went wrong. Please try again later.';
  }

  // ------------------------------------------------------------------
  //  Lifecycle
  // ------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _focusedTool = widget.initialTool;
    _loadDocument();
  }

  @override
  void dispose() {
    _doc?.dispose()?.catchError((_) {});
    _pdf?.dispose()?.catchError((_) {});
    super.dispose();
  }

  Future<void> _loadDocument() async {
    try {
      final bytes = widget.fileBytes ?? await File(widget.filePath).readAsBytes();
      _pdf = Pdf();
      final source = MemorySource(bytes);
      _doc = await _pdf!.open(source);
      _pageCount = _doc!.pageCount;
      _resultBytes = bytes;

      if (_focusedTool != null && _toolAutoRunsImmediately) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            _toolMeta(_focusedTool!, AppLocalizations.of(context)!).action();
          } catch (e) {
            final msg = _userFriendlyError(e);
            if (msg.isNotEmpty) _snack(msg, err: true);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _toolAutoRunsImmediately =>
      _focusedTool == PdfToolKind.merge ||
      _focusedTool == PdfToolKind.watermark ||
      _focusedTool == PdfToolKind.qrCode ||
      _focusedTool == PdfToolKind.jpg ||
      false;

  _ToolMeta _toolMeta(PdfToolKind kind, AppLocalizations l10n) {
    switch (kind) {
      case PdfToolKind.merge:
        return _ToolMeta(
          icon: Icons.merge_rounded,
          color: DS.indigo,
          label: l10n.merge,
          instruction: 'Choose the PDF(s) to merge in with this document.',
          action: _mergePdfs,
        );
      case PdfToolKind.extract:
        return _ToolMeta(
          icon: Icons.content_cut_rounded,
          color: DS.orange,
          label: l10n.extract,
          instruction: 'Tap pages below to select them, then tap Extract.',
          action: _extractPages,
        );
      case PdfToolKind.rotate:
        return _ToolMeta(
          icon: Icons.rotate_right_rounded,
          color: DS.green,
          label: l10n.rotate,
          instruction: 'Tap pages below to select them, then tap Rotate.',
          action: _rotateSelected,
        );
      case PdfToolKind.watermark:
        return _ToolMeta(
          icon: Icons.branding_watermark_rounded,
          color: DS.red,
          label: l10n.watermark,
          instruction: 'Tap Watermark to stamp text on all pages, or select pages below to stamp just those.',
          action: _addWatermark,
        );
      case PdfToolKind.duplicate:
        return _ToolMeta(
          icon: Icons.copy_rounded,
          color: DS.cyan,
          label: l10n.duplicate,
          instruction: 'Tap a page below to select it, then tap Duplicate.',
          action: () => _duplicatePage(_selectedPages.isNotEmpty ? _selectedPages.first : 0),
        );
      case PdfToolKind.qrCode:
        return _ToolMeta(
          icon: Icons.qr_code_rounded,
          color: DS.green,
          label: l10n.qrCode,
          instruction: 'Enter the text or link to encode as a QR code.',
          action: _addQrCode,
        );
      case PdfToolKind.jpg:
        return _ToolMeta(
          icon: Icons.image_rounded,
          color: DS.orange,
          label: 'JPG',
          instruction: 'Tap Export to save all pages as JPG, or select pages below to export just those.',
          action: _exportToJpg,
        );
      case PdfToolKind.deletePages:
        return _ToolMeta(
          icon: Icons.delete_outline_rounded,
          color: DS.red,
          label: 'Delete Pages',
          instruction: 'Select pages to delete, then tap Delete Pages.',
          action: _deletePages,
        );
      case PdfToolKind.reorderPages:
        return _ToolMeta(
          icon: Icons.swap_vert_rounded,
          color: DS.indigo,
          label: 'Reorder Pages',
          instruction: 'Drag pages into the order you want.',
          action: _reorderPages,
        );
      case PdfToolKind.movePage:
        return _ToolMeta(
          icon: Icons.call_made_rounded,
          color: DS.green,
          label: 'Move Page',
          instruction: 'Tap a page to move, then tap where to put it.',
          action: _movePage,
        );
      case PdfToolKind.compress:
        return _ToolMeta(
          icon: Icons.compress_rounded,
          color: DS.orange,
          label: 'Compress',
          instruction: 'Select compression quality (1–100).',
          action: _compress,
        );
      case PdfToolKind.optimizeImages:
        return _ToolMeta(
          icon: Icons.image_rounded,
          color: DS.indigo,
          label: 'Optimize Images',
          instruction: 'Advanced recompression with min‑size threshold.',
          action: _optimizeImages,
        );
      case PdfToolKind.stamp:
        return _ToolMeta(
          icon: Icons.verified_rounded,
          color: DS.cyan,
          label: 'Stamp',
          instruction: 'Add a standard stamp (APPROVED, DRAFT…) to selected pages.',
          action: _addStamp,
        );
      case PdfToolKind.convertPdfA:
        return _ToolMeta(
          icon: Icons.verified_rounded,
          color: DS.green,
          label: 'Convert to PDF/A',
          instruction: 'Make the document PDF/A‑1b compliant for archiving.',
          action: _convertToPdfA,
        );
      default:
        return _ToolMeta(
          icon: Icons.construction_rounded,
          color: DS.textSecondary,
          label: kind.name,
          instruction: 'Coming soon.',
          action: () => _snack('This tool is not available yet.', err: true),
        );
    }
  }

  Future<Uint8List> _getCurrentBytes() async {
    if (_resultBytes != null) return _resultBytes!;
    if (widget.fileBytes != null) return widget.fileBytes!;
    return await File(widget.filePath).readAsBytes();
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
    try {
      final path = await _saveOutput(bytes, name);
      if (!mounted) return;
      setState(() {
        _resultPath = path;
        _resultBytes = bytes;
      });
      await _reloadFromBytes(bytes);
      if (mounted) _snack('Done — tap Done above when you’re ready to use this PDF.');
    } catch (e) {
      final msg = _userFriendlyError(e);
      if (msg.isNotEmpty && mounted) _snack(msg, err: true);
    }
  }

  Future<void> _reloadFromBytes(Uint8List bytes) async {
    try {
      final newPdf = Pdf();
      final source = MemorySource(bytes);
      final newDoc = await newPdf.open(source);
      if (!mounted) {
        newDoc.dispose();
        newPdf.dispose();
        return;
      }
      final oldDoc = _doc;
      final oldPdf = _pdf;

      setState(() {
        _thumbnailGeneration++;
        _doc = newDoc;
        _pdf = newPdf;
        _pageCount = newDoc.pageCount;
        _selectedPages.clear();
        _pageThumbnails.clear();
        _resultBytes = bytes;
      });

      await Future.delayed(Duration.zero);

      if (oldDoc != null) await oldDoc.dispose();
      if (oldPdf != null) await oldPdf.dispose();
    } on PdfCancelled {
      // ignored
    } catch (e) {
      debugPrint('Could not reload tool output for preview: $e');
    }
  }

  Future<bool> _checkSize(String op, {int warn = 20, int max = 80}) async {
    final l10n = AppLocalizations.of(context)!;
    if (_pageCount <= warn) return true;
    if (_pageCount > max) {
      _snack('${l10n.maxPages} $max', err: true);
      return false;
    }
    final confirmed = await AppleDialog.show<bool>(
          context: context,
          title: l10n.largeDocument,
          content: '$_pageCount ${l10n.pages} $op ${l10n.mayBeSlow}',
          actions: [
            AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context, false)),
            AppleDialogAction(label: l10n.continue_, onPressed: () => Navigator.pop(context, true)),
          ],
        );
    return confirmed ?? false;
  }

  // ======================== MERGE =================================
  Future<void> _mergePdfs() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null) return;
    if (!await _checkSize(l10n.merging, warn: 15, max: 50)) return;

    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PDF', extensions: ['pdf'], uniformTypeIdentifiers: ['com.adobe.pdf']),
        ],
      );
      if (files.isEmpty) {
        _snack('No files selected.', err: true);
        return;
      }

      List<int> pageCounts = [];
      List<Uint8List> otherBytes = [];
      for (final f in files) {
        final b = await f.readAsBytes();
        otherBytes.add(b);
        final pdf = Pdf();
        final src = MemorySource(b);
        final d = await pdf.open(src);
        pageCounts.add(d.pageCount);
        await d.dispose();
        await pdf.dispose();
      }

      final currentPageCount = _selectedPages.isNotEmpty ? _selectedPages.length : _pageCount;
      final total = currentPageCount + pageCounts.fold<int>(0, (s, e) => s + e);

      final confirmed = await AppleDialog.show<bool>(
        context: context,
        title: l10n.merge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pages that will be merged:', style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 10),
            _mergeRow('This document (${_selectedPages.isNotEmpty ? _selectedPages.length : 'all'})', currentPageCount),
            for (int i = 0; i < files.length; i++) _mergeRow(files[i].name, pageCounts[i]),
            const Divider(color: DS.separator, height: 20),
            Text('Total: $total pages', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context, false)),
          AppleDialogAction(label: l10n.continue_, onPressed: () => Navigator.pop(context, true)),
        ],
      );
      if (confirmed != true) return;

      _showProgress(l10n.merging);
      try {
        Uint8List currentBytes = await _getCurrentBytes();
        if (_selectedPages.isNotEmpty) {
          final extractPdf = Pdf();
          final extractSink = MemorySink();
          await extractPdf.extractPages(
            MemorySource(currentBytes),
            extractSink,
            pages: _selectedPages.toList()..sort(),
          );
          currentBytes = extractSink.takeBytes();
          await extractPdf.dispose();
        }

        final pdf = Pdf();
        final sources = <DataSource>[MemorySource(currentBytes)];
        for (final b in otherBytes) sources.add(MemorySource(b));
        final sink = MemorySink();
        await pdf.merge(sources, sink);
        final mergedBytes = sink.takeBytes();
        await pdf.dispose();
        if (mounted) {
          Navigator.pop(context);
          _finish(mergedBytes, 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf');
        }
      } on PdfCancelled {
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          final msg = _userFriendlyError(e);
          if (msg.isNotEmpty) _snack(msg, err: true);
        }
      }
    } catch (e) {
      final msg = _userFriendlyError(e);
      if (msg.isNotEmpty) _snack(msg, err: true);
    }
  }

  Widget _mergeRow(String name, int pages) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          const Icon(Icons.picture_as_pdf_rounded, size: 14, color: DS.indigo),
          const SizedBox(width: 6),
          Expanded(
              child: Text(name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
          Text('$pages pg', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      );

  // ======================== EXTRACT ==============================
  Future<void> _extractPages() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null || _selectedPages.isEmpty) {
      _snack(l10n.selectPages, err: true);
      return;
    }
    if (_selectedPages.length > 30) {
      _snack('${l10n.maxPages} 30', err: true);
      return;
    }
    _showProgress(l10n.extracting);
    try {
      final bytes = await _getCurrentBytes();
      final pdf = Pdf();
      final source = MemorySource(bytes);
      final sink = MemorySink();
      final pageList = _selectedPages.toList()..sort();
      await pdf.extractPages(source, sink, pages: pageList);
      final extracted = sink.takeBytes();
      await pdf.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(extracted, 'extract_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== ROTATE ==============================
  Future<int?> _askRotationDirection(AppLocalizations l10n) {
    return AppleDialog.show<int>(
      context: context,
      title: l10n.rotate,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${l10n.selected}: ${_selectedPages.length}',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 14),
          _rotateOption(Icons.rotate_left_rounded, '90° left', 270),
          const SizedBox(height: 8),
          _rotateOption(Icons.rotate_right_rounded, '90° right', 90),
          const SizedBox(height: 8),
          _rotateOption(Icons.cached_rounded, '180°', 180),
        ],
      ),
      actions: [
        AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _rotateOption(IconData icon, String label, int degrees) => ScaleTap(
        onTap: () => Navigator.pop(context, degrees),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: DS.bgCard2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(icon, color: DS.indigo, size: 20),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
          ]),
        ),
      );

  Future<void> _rotateSelected() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null || _selectedPages.isEmpty) {
      _snack(l10n.selectPages, err: true);
      return;
    }
    final degrees = await _askRotationDirection(l10n);
    if (degrees == null) return;

    _showProgress(l10n.rotating);
    try {
      final bytes = await _getCurrentBytes();
      final pdf = Pdf();
      final source = MemorySource(bytes);
      final sink = MemorySink();
      final rotations = {for (final p in _selectedPages) p: degrees};
      await pdf.rotatePages(source, sink, pages: rotations);
      final rotated = sink.takeBytes();
      await pdf.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(rotated, 'rotated_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== WATERMARK ===========================
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
              _colorButton(Colors.red, selectedColor == Colors.red,
                  () => setSt(() => selectedColor = Colors.red)),
              const SizedBox(width: 8),
              _colorButton(Colors.blue, selectedColor == Colors.blue,
                  () => setSt(() => selectedColor = Colors.blue)),
              const SizedBox(width: 8),
              _colorButton(Colors.green, selectedColor == Colors.green,
                  () => setSt(() => selectedColor = Colors.green)),
              const SizedBox(width: 8),
              _colorButton(Colors.grey, selectedColor == Colors.grey,
                  () => setSt(() => selectedColor = Colors.grey)),
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
            const SizedBox(height: 8),
            const Text('Watermark will appear diagonally across each page.',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
      actions: [
        AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context)),
        AppleDialogAction(
          label: l10n.apply,
          onPressed: () =>
              Navigator.pop(context, {'text': ctrl.text, 'all': applyAll, 'color': selectedColor}),
        ),
      ],
    );

    if (input == null || input['text'].toString().isEmpty) return;
    _showProgress(l10n.watermarking);
    try {
      final bytes = await _getCurrentBytes();
      final pdf = Pdf();
      final source = MemorySource(bytes);
      final sink = MemorySink();
      final c = input['color'] as Color;

      final wmStyle = PdfWatermarkStyle(
        opacity: 0.45,
        fontSize: 60,
        rotation: -45, // degrees, not radians
        color: PdfColor(c.red / 255.0, c.green / 255.0, c.blue / 255.0),
      );

      if (input['all'] == true) {
        await pdf.watermark(source, sink, text: input['text'], style: wmStyle);
      } else {
        final editor = await pdf.edit(source);
        for (final p in _selectedPages) {
          await editor.addWatermark(p, input['text'], style: wmStyle);
        }
        await editor.save(sink);
        await editor.dispose();
      }
      final watermarked = sink.takeBytes();
      await pdf.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(watermarked, 'wm_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  Widget _colorButton(Color color, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: selected ? Border.all(color: DS.indigo, width: 2) : null,
        ),
      ),
    );
  }

  // ======================== DUPLICATE ===========================
  Future<void> _duplicatePage(int pageIndex) async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null) return;
    if (!await _checkSize(l10n.duplicating, warn: 10, max: 40)) return;

    final List<int> pagesToDuplicate;
    if (_selectedPages.isNotEmpty) {
      pagesToDuplicate = _selectedPages.toList()..sort();
    } else {
      final picked = await _pickPageHuman('Which page to duplicate?');
      if (picked == null) return;
      pagesToDuplicate = [picked];
    }

    _showProgress(l10n.duplicating);
    try {
      final bytes = await _getCurrentBytes();
      final pdf = Pdf();
      final source = MemorySource(bytes);
      final sink = MemorySink();
      final order = <int>[];
      for (int i = 0; i < _pageCount; i++) {
        order.add(i);
        if (pagesToDuplicate.contains(i)) order.add(i);
      }
      await pdf.extractPages(source, sink, pages: order);
      final duplicated = sink.takeBytes();
      await pdf.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(duplicated, 'dup_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== QR CODE =============================
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
        ),
      ],
    );
    if (text == null || text.isEmpty) return;

    _showProgress(l10n.addingQr);
    try {
      final bytes = await _getCurrentBytes();
      final qr = QrPainter(
          data: text, version: QrVersions.auto, color: Colors.black, emptyColor: Colors.white);
      final rec = ui.PictureRecorder();
      qr.paint(Canvas(rec, Rect.fromLTWH(0, 0, 200, 200)), const Size(200, 200));
      final pic = rec.endRecording();
      final img = await pic.toImage(200, 200);
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (pngBytes == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final qrImage = pngBytes.buffer.asUint8List();

      final pdf = Pdf();
      final source = MemorySource(bytes);
      final editor = await pdf.edit(source);
      for (int i = 0; i < _pageCount; i++) {
        final page = _doc!.pages[i];
        final x = page.width - 90;
        final y = page.height - 90;
        final w = 80.0;
        final h = 80.0;
        await editor.addImageStamp(
          i,
          MemorySource(qrImage),
          rect: PdfRect(x: x, y: y, width: w, height: h),
        );
      }
      final sink = MemorySink();
      await editor.save(sink);
      await editor.dispose();
      final qrBytes = sink.takeBytes();
      await pdf.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(qrBytes, 'qr_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== JPG EXPORT ==========================
  Future<void> _exportToJpg() async {
    final l10n = AppLocalizations.of(context)!;
    final doc = _doc;
    if (doc == null) return;

    final List<int> indices = _selectedPages.isNotEmpty
        ? (_selectedPages.toList()..sort())
        : List.generate(_pageCount, (i) => i);

    if (indices.length > 40) {
      _snack('${l10n.maxPages} 40', err: true);
      return;
    }
    if (_selectedPages.isEmpty && !await _checkSize('Export to JPG', warn: 15, max: 40)) return;

    _showProgress('Exporting…');
    final files = <MapEntry<String, Uint8List>>[];
    String? genError;
    try {
      for (final i in indices) {
        final page = doc.pages[i];
        final w = page.width;
        final h = page.height;

        double renderW = w;
        double renderH = h;
        const maxDim = 2000.0;
        if (renderW > maxDim) {
          renderH = maxDim * (h / w);
          renderW = maxDim;
        }
        if (renderH > maxDim) {
          renderW = maxDim * (w / h);
          renderH = maxDim;
        }

        final renderedList = await doc.render(
          pages: PdfPages.single(i),
          size: PdfRenderSize(
            maxWidth: renderW.round(),
            maxHeight: renderH.round(),
          ),
        ).toList();

        if (renderedList.isEmpty) continue;
        final rendered = renderedList.first;

        final decoded = img.decodeImage(rendered.data);
        if (decoded == null) continue;

        final jpgBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
        files.add(MapEntry('page_${i + 1}.jpg', jpgBytes));
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
      return;
    } catch (e) {
      genError = e.toString();
    }

    if (!mounted) return;
    Navigator.pop(context);

    if (genError != null) {
      final msg = _userFriendlyError(genError);
      if (msg.isNotEmpty) _snack(msg, err: true);
      return;
    }
    if (files.isEmpty) {
      _snack('No images could be generated.', err: true);
      return;
    }

    try {
      await PlatformFileService.shareFiles(
        files,
        context: context,
        subject: '${files.length} page${files.length == 1 ? '' : 's'} exported as JPG',
      );
    } catch (e) {
      final msg = _userFriendlyError(e);
      if (msg.isNotEmpty) _snack(msg, err: true);
    }
  }

  // ======================== DELETE PAGES ========================
  Future<void> _deletePages() async {
    if (_doc == null) return;
    if (_selectedPages.isEmpty) {
      _snack('Select at least one page to delete.', err: true);
      return;
    }
    if (_selectedPages.length >= _pageCount) {
      _snack('Cannot delete all pages. A PDF must have at least one page.', err: true);
      return;
    }
    _showProgress('Deleting pages…');
    try {
      final bytes = await _getCurrentBytes();
      final pdf = Pdf();
      final sink = MemorySink();
      final pages = _selectedPages.toList()..sort();
      await pdf.deletePages(MemorySource(bytes), sink, pages: pages);
      final result = sink.takeBytes();
      await pdf.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(result, 'deleted_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== REORDER =============================
  Future<List<int>?> _showReorderDialog() async {
    final List<int> order = List.generate(_pageCount, (i) => i);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          decoration: const BoxDecoration(
            color: DS.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration:
                  BoxDecoration(color: DS.separator, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(children: [
                const Text('Reorder Pages',
                    style: TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: DS.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Apply'),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Drag pages using the handle icon',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: order.length,
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      final double elevation = 4.0 * animation.value;
                      return Material(
                        elevation: elevation,
                        color: Colors.transparent,
                        child: child,
                      );
                    },
                    child: child,
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  setBS(() {
                    final item = order.removeAt(oldIndex);
                    order.insert(newIndex, item);
                  });
                },
                itemBuilder: (_, idx) {
                  final pageNum = order[idx] + 1;
                  final thumb = _pageThumbnails[order[idx]];
                  return Container(
                    key: ValueKey(order[idx]),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: DS.bgCard2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 36,
                          height: 48,
                          child: thumb != null
                              ? Image.memory(thumb, fit: BoxFit.cover)
                              : Container(
                                  color: Colors.grey[800],
                                  child: const Center(
                                    child: Icon(Icons.picture_as_pdf_rounded,
                                        size: 18, color: Colors.white38),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Page $pageNum',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            if (idx != order[idx])
                              Text(
                                'was page ${order[idx] + 1}',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: idx,
                        child: const Icon(Icons.drag_handle_rounded, color: Colors.white38),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
    return confirmed == true ? order : null;
  }

  Future<void> _reorderPages() async {
    final order = await _showReorderDialog();
    if (order == null) return;
    _showProgress('Reordering…');
    try {
      final bytes = await _getCurrentBytes();
      final pdf = Pdf();
      final sink = MemorySink();
      await pdf.reorderPages(MemorySource(bytes), sink, order: order);
      final result = sink.takeBytes();
      await pdf.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(result, 'reordered_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== MOVE PAGE ===========================
  Future<void> _movePage() async {
    final l10n = AppLocalizations.of(context)!;
    if (_doc == null || _pdf == null) {
      _snack('Document not ready.', err: true);
      return;
    }
    final from = await _pickPageHuman('Which page to move?');
    if (from == null) return;
    final to = await _pickPageHuman('Move it after which page?');
    if (to == null) return;
    if (from == to) {
      _snack('Source and destination are the same page.', err: true);
      return;
    }
    _showProgress('Moving…');
    try {
      final bytes = await _getCurrentBytes();
      final editor = await _pdf!.edit(MemorySource(bytes));
      await editor.movePage(from: from, to: to);
      final sink = MemorySink();
      await editor.save(sink);
      final result = sink.takeBytes();
      await editor.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(result, 'moved_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== COMPRESS ============================
  Future<void> _compress() async {
    if (_pdf == null) {
      _snack('Document not ready.', err: true);
      return;
    }
    final quality = await _askQuality();
    if (quality == null) return;
    _showProgress('Compressing…');
    try {
      final bytes = await _getCurrentBytes();
      final pdf = Pdf();
      final sink = MemorySink();
      await pdf.compress(MemorySource(bytes), sink);
      final result = sink.takeBytes();
      await pdf.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(result, 'compressed_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== OPTIMIZE IMAGES =====================
  Future<void> _optimizeImages() async {
    if (_pdf == null) {
      _snack('Document not ready.', err: true);
      return;
    }
    final params = await _askOptimizeParams();
    if (params == null) return;
    _showProgress('Optimizing images…');
    try {
      final bytes = await _getCurrentBytes();
      final editor = await _pdf!.edit(MemorySource(bytes));
      await editor.optimizeImages(
        quality: params.quality,
        minSize: params.minSize,
      );
      final sink = MemorySink();
      await editor.save(sink);
      final result = sink.takeBytes();
      await editor.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(result, 'optimized_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== STAMP ===============================
  Future<void> _addStamp() async {
    if (_doc == null || _pdf == null) {
      _snack('Document not ready.', err: true);
      return;
    }
    final type = await _askStampType();
    if (type == null) return;
    final pages = _selectedPages.isNotEmpty
        ? _selectedPages.toList()
        : List.generate(_pageCount, (i) => i);
    _showProgress('Adding stamp…');
    try {
      final bytes = await _getCurrentBytes();
      final editor = await _pdf!.edit(MemorySource(bytes));
      for (final p in pages) {
        final page = _doc!.pages[p];
        final rect = PdfRect(x: page.width - 150, y: page.height - 60, width: 140, height: 50);
        await editor.addStamp(p, type: type, rect: rect, opacity: 0.8);
      }
      final sink = MemorySink();
      await editor.save(sink);
      final result = sink.takeBytes();
      await editor.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(result, 'stamped_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ======================== CONVERT TO PDF/A ====================
  Future<void> _convertToPdfA() async {
    if (_pdf == null) {
      _snack('Document not ready.', err: true);
      return;
    }
    _showProgress('Converting to PDF/A…');
    try {
      final bytes = await _getCurrentBytes();
      final editor = await _pdf!.edit(MemorySource(bytes));
      await editor.convertToPdfA(level: 1);
      final sink = MemorySink();
      await editor.save(sink);
      final result = sink.takeBytes();
      await editor.dispose();
      if (mounted) {
        Navigator.pop(context);
        _finish(result, 'pdfa_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } on PdfCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final msg = _userFriendlyError(e);
        if (msg.isNotEmpty) _snack(msg, err: true);
      }
    }
  }

  // ================================================================
  //  DIALOGS
  // ================================================================

  Future<int?> _pickPageHuman(String title) async {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.55,
        decoration: const BoxDecoration(
          color: DS.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration:
                BoxDecoration(color: DS.separator, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.72,
              ),
              itemCount: _pageCount,
              itemBuilder: (_, i) {
                final thumb = _pageThumbnails[i];
                return GestureDetector(
                  onTap: () => Navigator.pop(ctx, i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DS.separator),
                    ),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: thumb != null
                            ? Image.memory(thumb,
                                fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                            : Container(color: Colors.grey[50]),
                      ),
                      Positioned(
                        bottom: 4,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<int?> _pickPage(String title) => _pickPageHuman(title);

  Future<int?> _askQuality() async {
    final ctrl = TextEditingController(text: '75');
    final result = await AppleDialog.show<String>(
      context: context,
      title: 'Compression Quality',
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: '1–100 (default 75)',
          filled: true,
          fillColor: DS.bgCard2,
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
      ),
      actions: [
        AppleDialogAction(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        AppleDialogAction(
            label: 'Compress', onPressed: () => Navigator.pop(context, ctrl.text.trim())),
      ],
    );
    if (result == null) return null;
    final v = int.tryParse(result);
    if (v == null || v < 1 || v > 100) {
      _snack('Invalid quality. Enter a number between 1 and 100.', err: true);
      return null;
    }
    return v;
  }

  Future<_OptimizeParams?> _askOptimizeParams() async {
    final qualCtrl = TextEditingController(text: '75');
    final sizeCtrl = TextEditingController(text: '128');
    final result = await AppleDialog.show<Map<String, String>>(
      context: context,
      title: 'Optimize Images',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: qualCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Quality (1-100)', labelStyle: TextStyle(color: Colors.white54)),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: sizeCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Min size (pixels)', labelStyle: TextStyle(color: Colors.white54)),
          style: const TextStyle(color: Colors.white),
        ),
      ]),
      actions: [
        AppleDialogAction(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        AppleDialogAction(
            label: 'Optimize',
            onPressed: () =>
                Navigator.pop(context, {'quality': qualCtrl.text, 'minSize': sizeCtrl.text})),
      ],
    );
    if (result == null) return null;
    final q = int.tryParse(result['quality']!);
    final s = int.tryParse(result['minSize']!);
    if (q == null || s == null) {
      _snack('Invalid input. Please enter numbers.', err: true);
      return null;
    }
    return _OptimizeParams(q, s);
  }

  Future<PdfStampType?> _askStampType() async {
    return await showDialog<PdfStampType>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DS.bgCard,
        title: const Text('Choose stamp type', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: PdfStampType.values.length,
            itemBuilder: (_, i) {
              final type = PdfStampType.values[i];
              return InkWell(
                onTap: () => Navigator.pop(ctx, type),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Text(type.name, style: const TextStyle(color: Colors.white)),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: DS.indigo)),
          ),
        ],
      ),
    );
  }

  // ================================================================
  //  THUMBNAIL LOADING (FIXED)
  // ================================================================

  Future<void> _loadPageThumbnail(int pageIndex) async {
  if (_pageThumbnails.containsKey(pageIndex)) return;
  final doc = _doc;
  if (doc == null) return;

  final int generation = _thumbnailGeneration;
  try {
    final page = doc.pages[pageIndex];
    const targetWidth = 180.0;
    final targetHeight = targetWidth * (page.height / page.width);

    final results = await doc.render(
      pages: PdfPages.single(pageIndex),
      size: PdfRenderSize(
        maxWidth: targetWidth.toInt(),
        maxHeight: targetHeight.toInt(),
      ),
    ).toList();

    if (results.isEmpty) {
      // No data – place a placeholder to avoid infinite spinner
      if (mounted && generation == _thumbnailGeneration) {
        setState(() => _pageThumbnails[pageIndex] = Uint8List(0));
      }
      return;
    }
    final rendered = results.first;
    if (rendered.data.isEmpty) {
      if (mounted && generation == _thumbnailGeneration) {
        setState(() => _pageThumbnails[pageIndex] = Uint8List(0));
      }
      return;
    }

    if (!mounted || generation != _thumbnailGeneration) return;
    setState(() => _pageThumbnails[pageIndex] = rendered.data);
  } on PdfCancelled {
    // User cancelled – ignore
  } catch (e) {
    
    // On any error, place a placeholder so the spinner stops
    if (mounted && generation == _thumbnailGeneration) {
      setState(() => _pageThumbnails[pageIndex] = Uint8List(0));
    }
  }
}

  void _toggle(int i) => setState(() {
        if (_selectedPages.contains(i)) _selectedPages.remove(i);
        else _selectedPages.add(i);
      });

  // ================================================================
  //  BUILD
  // ================================================================

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
          onPressed: () => Navigator.pop(context, {
            'path': _resultPath ?? widget.filePath,
            'bytes': _resultBytes,
          }),
        ),
        title: Text(
          l10n.pdfTools,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Navigator.pop(context, {
                'path': _resultPath ?? widget.filePath,
                'bytes': _resultBytes,
              }),
              child: const Text('Done',
                  style: TextStyle(
                      color: DS.indigo, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DS.indigo))
          : _pageCount == 0
              ? Center(child: Text(l10n.noPdfLoaded, style: DS.body(size: 16)))
              : Column(children: [
                  _focusedTool == null ? _buildTools(l10n) : _buildFocusedHeader(l10n),
                  const Divider(color: DS.separator),
                  Expanded(child: _buildGrid(l10n)),
                  if (_selectedPages.isNotEmpty || _focusedTool != null) _buildBottom(l10n),
                ]),
    );
  }

  Widget _buildFocusedHeader(AppLocalizations l10n) {
    final meta = _toolMeta(_focusedTool!, l10n);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: meta.color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(meta.icon, color: meta.color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(meta.label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(meta.instruction,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _focusedTool = null),
          icon: const Icon(Icons.grid_view_rounded, size: 14, color: DS.indigo),
          label: const Text('All tools',
              style: TextStyle(color: DS.indigo, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _buildTools(AppLocalizations l10n) {
    final tools = [
      _CardData(l10n.merge, Icons.merge_rounded, DS.indigo, _mergePdfs, 'Combine PDFs'),
      _CardData(l10n.extract, Icons.content_cut_rounded, DS.orange, _extractPages, 'Extract pages'),
      _CardData(l10n.rotate, Icons.rotate_right_rounded, DS.green, _rotateSelected, 'Rotate pages'),
      _CardData(l10n.watermark, Icons.branding_watermark_rounded, DS.red, _addWatermark, 'Add watermark'),
      _CardData(l10n.duplicate, Icons.copy_rounded, DS.cyan, () => _duplicatePage(-1), 'Duplicate pages'),
      _CardData(l10n.qrCode, Icons.qr_code_rounded, DS.green, _addQrCode, 'Embed QR code'),
      _CardData('Export JPG', Icons.image_rounded, DS.orange, _exportToJpg, 'Pages as images'),
      _CardData('Delete Pages', Icons.delete_outline_rounded, DS.red, _deletePages, 'Remove pages'),
      _CardData('Reorder', Icons.swap_vert_rounded, DS.indigo, _reorderPages, 'Drag to reorder'),
      _CardData('Move Page', Icons.call_made_rounded, DS.green, _movePage, 'Move to position'),
      _CardData('Compress', Icons.compress_rounded, DS.orange, _compress, 'Reduce file size'),
      _CardData('Optimize', Icons.auto_fix_high_rounded, DS.indigo, _optimizeImages, 'Shrink images'),
      _CardData('Stamp', Icons.shield_rounded, DS.cyan, _addStamp, 'Add stamp label'),
      _CardData('PDF/A', Icons.verified_rounded, DS.green, _convertToPdfA, 'Archive format'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _toolsColumnCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.9,
        ),
        itemCount: tools.length,
        itemBuilder: (_, i) => _cardFromData(tools[i]),
      ),
    );
  }

  int get _toolsColumnCount {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 3;
    if (w < 500) return 4;
    return 5;
  }

  Widget _card(String l, IconData i, Color c, VoidCallback t) => ScaleTap(
        onTap: t,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.withOpacity(0.12), c.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: c.withOpacity(0.2)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(i, color: c, size: 22),
            ),
            const SizedBox(height: 6),
            Text(l,
                style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget _cardFromData(_CardData d) => ScaleTap(
        onTap: d.action,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [d.color.withOpacity(0.12), d.color.withOpacity(0.04)]),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: d.color.withOpacity(0.2)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: d.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(d.icon, color: d.color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(d.label,
                style: TextStyle(color: d.color, fontSize: 10.5, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(d.subtitle,
                style: const TextStyle(color: DS.textSecondary, fontSize: 9.0, fontWeight: FontWeight.w400),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

 Widget _buildGrid(AppLocalizations l10n) {
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
      final thumb = _pageThumbnails[i];
      if (!_pageThumbnails.containsKey(i)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadPageThumbnail(i));
      }

      Widget child;
      if (thumb == null) {
        // Still loading – show spinner
        child = Container(
          color: Colors.grey[50],
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo),
            ),
          ),
        );
      } else if (thumb.isEmpty) {
        // Failed – show a grey box with broken‑image icon
        child = Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 30),
          ),
        );
      } else {
        // Success – show the image
        child = Image.memory(
          thumb,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }

      return GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); _toggle(i); },
        onLongPress: () { HapticFeedback.mediumImpact(); _duplicatePage(i); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: sel ? DS.indigo : Colors.grey.withOpacity(0.15), width: sel ? 2.5 : 0.8),
            boxShadow: sel ? [
              BoxShadow(color: DS.indigo.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 3)),
            ] : [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: child,
              ),
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ),
              if (sel)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(color: DS.indigo, shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: Colors.white, size: 14)),
                ),
            ],
          ),
        ),
      );
    },
  );
}

  Widget _buildBottom(AppLocalizations l10n) {
    final meta = _focusedTool != null ? _toolMeta(_focusedTool!, l10n) : null;
    final icon = meta?.icon ?? Icons.content_cut_rounded;
    final label = meta?.label ?? l10n.extract;
    final action = meta?.action ?? _extractPages;
    final color = meta?.color ?? DS.indigo;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: DS.bgCard,
        border: Border(top: BorderSide(color: DS.separator, width: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          // selection badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: DS.bgCard2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DS.separator),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_rounded, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                '${_selectedPages.length} ${l10n.selected}',
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          const Spacer(),
          // clear selection
          TextButton(
            onPressed: () => setState(() => _selectedPages.clear()),
            child: Text(l10n.cancel, style: TextStyle(color: DS.textSecondary, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          // action button
          ScaleTap(
            onTap: action,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 17, color: Colors.white),
                const SizedBox(width: 7),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  void _showProgress(String m) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: DS.bgCard,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)
              ]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo)),
            const SizedBox(height: 12),
            Text(m, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
        ),
      ),
    );
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
}

class _CardData {
  final String label, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback action;
  const _CardData(this.label, this.icon, this.color, this.action, this.subtitle);
}

class _ToolMeta {
  final IconData icon;
  final Color color;
  final String label;
  final String instruction;
  final VoidCallback action;
  const _ToolMeta(
      {required this.icon,
      required this.color,
      required this.label,
      required this.instruction,
      required this.action});
}

class _OptimizeParams {
  final int quality;
  final int minSize;
  const _OptimizeParams(this.quality, this.minSize);
}
