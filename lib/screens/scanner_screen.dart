import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:doc_scan_flutter/doc_scan.dart';

import '../utils/platform_file_service.dart';
import '../utils/web_download.dart';
import '../widgets/ds.dart';
import 'pdf_viewer_screen.dart';
import '../utils/app_localizations.dart';

// ---------------------------------------------------------------------------
// SmartDocumentClassifier (unchanged)
// ---------------------------------------------------------------------------
class SmartDocumentClassifier {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  Future<String> classify(Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final tempFile = File(
          '${dir.path}/classify_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);
      final inputImage = InputImage.fromFile(tempFile);
      final recognized = await _recognizer.processImage(inputImage);
      await tempFile.delete();
      final text = recognized.text.toLowerCase();
      if (text.contains('invoice')) return 'Invoice';
      if (text.contains('receipt')) return 'Receipt';
      if (text.contains('id card') || text.contains('passport')) {
        return 'ID Card';
      }
      if (text.contains('contract') || text.contains('agreement')) {
        return 'Contract';
      }
      if (text.isNotEmpty) return 'Document';
      return 'Uncategorized';
    } catch (e) {
      debugPrint('Classification error: $e');
      return 'Uncategorized';
    }
  }

  void dispose() => _recognizer.close();
}

// ---------------------------------------------------------------------------
// Page model
// ---------------------------------------------------------------------------
class _Page {
  final String name;
  final Uint8List bytes;
  int n;
  String category;
  _Page({
    required this.name,
    required this.bytes,
    required this.n,
    this.category = 'Uncategorized',
  });
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  static Future<void> show(BuildContext ctx) => Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => const ScannerScreen()),
      );

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _picker = ImagePicker();
  final List<_Page> _pages = [];
  bool _grayscale = false;
  bool _building = false;
  bool _batchMode = false;
  bool _extractText = false;
  bool _hdMode = false;

  late SmartDocumentClassifier _classifier;
  late final TextRecognizer _ocrRecognizer;

  @override
  void initState() {
    super.initState();
    _classifier = SmartDocumentClassifier();
    _ocrRecognizer = TextRecognizer();
  }

  @override
  void dispose() {
    _classifier.dispose();
    _ocrRecognizer.close();
    super.dispose();
  }

  void _clearAll() async {
    setState(() {
      _pages.clear();
      _grayscale = false;
    });
    PlatformFileService.clearCache();
    _snack(AppLocalizations.of(context)!.clearedAllPages);
  }

  Future<void> _autoDetectScan() async {
    if (kIsWeb) {
      final l10n = AppLocalizations.of(context)!;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.notAvailableOnWeb),
          content: Text(l10n.scanWebMessage),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(_), child: Text(l10n.ok)),
          ],
        ),
      );
      return;
    }

    try {
      final List<String>? scannedImages = await DocumentScanner.scan();

      if (scannedImages != null && scannedImages.isNotEmpty && mounted) {
        for (final imagePath in scannedImages) {
          final bytes = await File(imagePath).readAsBytes();
          await _addScannedPage(bytes,
              'scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }

        if (_batchMode && mounted) {
          _autoDetectScan();
        }
      }
    } on DocumentScannerException catch (e) {
      if (mounted) {
        _snack('${AppLocalizations.of(context)!.scanningError}: $e',
            err: true);
      }
    } catch (e) {
      if (mounted) {
        _snack('${AppLocalizations.of(context)!.unexpectedError}: $e',
            err: true);
      }
    }
  }

  Future<void> _gallery() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: _hdMode ? null : 92,
      );
      if (!mounted || files.isEmpty) return;
      for (final f in files) {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty || !mounted) continue;
        await _processAndAddImage(bytes, f.name);
        if (_extractText && mounted) {
          await _performOCR(bytes);
        }
      }
    } catch (e) {
      _snack('${AppLocalizations.of(context)!.galleryError}: $e', err: true);
    }
  }

  Future<void> _processAndAddImage(Uint8List bytes, String name) async {
    final edited = await _launchManualEditor(bytes);
    if (edited == null) return;
    final finalBytes = _grayscale ? _applyGrayscale(edited) : edited;

    if (finalBytes.isNotEmpty && mounted) {
      String category = 'Uncategorized';
      try {
        category = await _classifier.classify(finalBytes);
      } catch (_) {}
      setState(() {
        _pages.add(_Page(
          name: name,
          bytes: finalBytes,
          n: _pages.length + 1,
          category: category,
        ));
      });
      if (_batchMode && mounted) {
        _autoDetectScan();
      }
    }
  }

  Future<Uint8List?> _launchManualEditor(Uint8List bytes) async {
    return Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => ProImageEditor.memory(
          bytes,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List editedBytes) async {
              Navigator.pop(context, editedBytes);
            },
          ),
          configs: const ProImageEditorConfigs(),
        ),
      ),
    );
  }

  Uint8List _applyGrayscale(Uint8List bytes) {
    final original = img.decodeImage(bytes);
    if (original == null) return bytes;
    final gray = img.grayscale(original);
    final quality = _hdMode ? 95 : 85;
    return Uint8List.fromList(img.encodeJpg(gray, quality: quality));
  }

  Future<String> _extractTextFromImage(Uint8List imageBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
          '${tempDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);
      final inputImage = InputImage.fromFile(tempFile);
      final recognized = await _ocrRecognizer.processImage(inputImage);
      await tempFile.delete();
      return recognized.text;
    } catch (_) {
      return '';
    }
  }

  Future<void> _performOCR(Uint8List imageBytes) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final text = await _extractTextFromImage(imageBytes);

    if (mounted) {
      Navigator.pop(context); // close loading

      if (text.isNotEmpty) {
        final extractedText = text;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.extractedText),
            content: SingleChildScrollView(
              child: Text(extractedText, style: const TextStyle(fontSize: 14)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(_),
                child: Text(l10n.close),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: extractedText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(l10n.textCopied),
                        duration: const Duration(seconds: 1)),
                  );
                  Navigator.pop(_);
                },
                child: Text(l10n.copy),
              ),
            ],
          ),
        );
      } else {
        _snack(l10n.noTextFound);
      }
    }
  }

  /// Builds the PDF, asks the user for a filename, then writes it to
  /// somewhere they can actually find:
  ///   * web → browser download
  ///   * native → system save dialog via `FilePicker.saveFile`, plus an
  ///     internal copy so the viewer has a path to open
  Future<void> _build() async {
    final l10n = AppLocalizations.of(context)!;
    if (_pages.isEmpty) {
      _snack(l10n.addAtLeastOnePage);
      return;
    }

    // 1. Ask the user what to call the file. Default is timestamped.
    final defaultName = 'scan_${DateTime.now().millisecondsSinceEpoch}';
    final rawName = await _askFileName(defaultName: defaultName);
    if (rawName == null) return; // user cancelled
    final trimmed = rawName.trim();
    final baseName = trimmed.isEmpty ? defaultName : trimmed;
    final safeName = baseName.toLowerCase().endsWith('.pdf')
        ? baseName
        : '$baseName.pdf';

    setState(() => _building = true);
    try {
      // 2. Build the PDF in memory.
      final doc = pw.Document(compress: true);
      const double targetDpi = 300.0;
      const double pdfDpi = 72.0;
      final double scale = pdfDpi / targetDpi;

      for (final pg in _pages) {
        final Uint8List bytes = pg.bytes;
        if (bytes.length < 100) {
          _snack('${l10n.imageCorrupted} ${pg.name}', err: true);
          continue;
        }
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final imgWidget = frame.image;
        final pxW = imgWidget.width.toDouble();
        final pxH = imgWidget.height.toDouble();
        imgWidget.dispose();
        codec.dispose();
        final pageW = pxW * 72 / 72.0;
        final pageH = pxH * 72 / 72.0;
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pageW, pageH),
            margin: pw.EdgeInsets.zero,
            build: (_) =>
                pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
          ),
        );
      }

      final pdfBytes = Uint8List.fromList(await doc.save());

      setState(() => _pages.clear());

      // 3a. Web: browser download; then open viewer from in-memory bytes.
      if (kIsWeb) {
        downloadFile(safeName, pdfBytes);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PdfViewerScreen(
                filePath: safeName,
                preloadedBytes: pdfBytes,
              ),
            ),
          );
        }
        return;
      }

      // 3b. Native: keep an internal copy for the viewer, then hand the
      //     bytes to the system save dialog so the user's file lands
      //     somewhere visible (Downloads, Documents, Drive, …).
      final internalPath = await _saveToDisk(pdfBytes, safeName);

      if (!mounted) return;

      try {
        final pickedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save PDF',
          fileName: safeName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: pdfBytes,
        );
        if (pickedPath != null) {
          _snack('${l10n.savedTo} ${p.basename(pickedPath)}', duration: 4);
        }
        // If pickedPath is null the user cancelled the external save. We
        // still open the viewer so nothing is lost — the internal copy
        // remains reachable from the viewer's Save button.
      } catch (e) {
        debugPrint('External save failed: $e');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => PdfViewerScreen(filePath: internalPath)),
        );
      }
    } catch (e) {
      if (mounted) _snack('${l10n.error}: $e', err: true);
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<String> _saveToDisk(Uint8List bytes, String fileName) async {
    final safeName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
    final path = await PlatformFileService.outputPath(safeName);
    await PlatformFileService.writeBytes(path, bytes);
    return path;
  }

  void _snack(String msg, {bool err = false, int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        backgroundColor: err ? DS.red : DS.bgCard2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
        duration: Duration(seconds: duration),
      ),
    );
  }

  Future<String?> _askFileName({String? defaultName}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: defaultName ?? 'document');
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: DS.bgCard,
          title: Text(l10n.savePdfAs,
              style:
                  GoogleFonts.inter(color: Colors.white, fontSize: 16)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.enterFileName,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: DS.bgCard2,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel,
                  style: const TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: DS.indigo),
              child: Text(l10n.createPdfButton),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _addScannedPage(Uint8List bytes, String name) async {
    final finalBytes = _grayscale ? _applyGrayscale(bytes) : bytes;

    if (finalBytes.isNotEmpty && mounted) {
      String category = 'Uncategorized';
      try {
        category = await _classifier.classify(finalBytes);
      } catch (_) {}

      setState(() {
        _pages.add(_Page(
          name: name,
          bytes: finalBytes,
          n: _pages.length + 1,
          category: category,
        ));
      });

      if (_extractText && mounted) {
        await _performOCR(finalBytes);
      }
    }
  }

  // --------------------------------------------------------------------------
  // UI Builders
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    DS.setStatusBar();
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: DS.indigo, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.documentScanner,
          style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          if (_pages.isNotEmpty)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded,
                      color: DS.red, size: 22),
                  tooltip: AppLocalizations.of(context)!.clearAll,
                  onPressed: _clearAll,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _building ? null : _build,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: Text(
                      '${AppLocalizations.of(context)!.createPdf} (${_pages.length})',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: DS.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _pages.isEmpty ? _emptyState() : _pageGrid(),
    );
  }

  Widget _emptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: DS.indigo.withOpacity(0.08),
                shape: BoxShape.circle,
                border:
                    Border.all(color: DS.indigo.withOpacity(0.15), width: 2),
              ),
              child: Icon(Icons.document_scanner_rounded,
                  size: 52, color: DS.indigo.withOpacity(0.6)),
            ),
            const SizedBox(height: 32),
            Text(l10n.scanDocumentsTitle,
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              l10n.scanDocumentsSubtitle,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            _chip(
              l10n.hd,
              _hdMode,
              () => setState(() => _hdMode = !_hdMode),
              icon: Icons.high_quality_rounded,
            ),
            if (_grayscale)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Black & white mode is on — colors will be removed.',
                  style: TextStyle(color: DS.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _actionCard(
                    icon: Icons.photo_library_rounded,
                    label: l10n.gallery,
                    color: DS.cyan,
                    onTap: _gallery,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionCard(
                    icon: Icons.camera_alt_rounded,
                    label: l10n.scan,
                    color: DS.indigo,
                    onTap: _autoDetectScan,
                    primary: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageGrid() {
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        int crossAxisCount;
        if (w < 420) crossAxisCount = 2;
        else if (w < 900) crossAxisCount = 3;
        else crossAxisCount = 4;

        return Column(
          children: [
            Row(
              children: [
                const Icon(Icons.collections_rounded,
                    color: DS.indigo, size: 18),
                const SizedBox(width: 8),
                const Spacer(),
                _chip(l10n.bw, _grayscale,
                    () => setState(() => _grayscale = !_grayscale),
                    icon: Icons.monochrome_photos_outlined),
                const SizedBox(width: 8),
                _chip(l10n.batch, _batchMode,
                    () => setState(() => _batchMode = !_batchMode),
                    icon: Icons.burst_mode_rounded),
                const SizedBox(width: 8),
                _chip(l10n.hd, _hdMode,
                    () => setState(() => _hdMode = !_hdMode),
                    icon: Icons.high_quality_rounded),
                const SizedBox(width: 8),
                _chip(l10n.extractText, _extractText,
                    () => setState(() => _extractText = !_extractText),
                    icon: Icons.text_snippet_outlined),
              ],
            ),
            if (_grayscale)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: DS.orange.withOpacity(0.15),
                child: Row(
                  children: [
                    const Icon(Icons.monochrome_photos_outlined,
                        size: 14, color: DS.orange),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Black & white mode is on — new pages will not keep '
                        'their colors.',
                        style: TextStyle(color: DS.orange, fontSize: 11),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _grayscale = false),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Turn off',
                          style: TextStyle(color: DS.orange, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1, color: DS.separator),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.75,
                ),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _pageTile(i),
              ),
            ),
            SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: DS.bgCard,
                  border: Border(
                      top: BorderSide(
                          color: DS.separator.withOpacity(0.5))),
                ),
                child: Row(
                  children: [
                    Expanded(
                        child: _actionCard(
                            icon: Icons.photo_library_rounded,
                            label: l10n.gallery,
                            color: DS.cyan,
                            onTap: _gallery)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _actionCard(
                            icon: Icons.camera_alt_rounded,
                            label: l10n.scan,
                            color: DS.indigo,
                            onTap: _autoDetectScan,
                            primary: true)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pageTile(int i) {
    final l10n = AppLocalizations.of(context)!;
    final pg = _pages[i];
    return GestureDetector(
      onLongPress: () => _delete(i),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: DS.bgCard2,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(pg.bytes, fit: BoxFit.cover),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Text('${l10n.page} ${pg.n}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _showCategoryPicker(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.label_outline,
                            size: 10, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(pg.category,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(top: 6, right: 6, child: _deleteBtn(() => _delete(i))),
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: () => _performOCR(pg.bytes),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Icon(Icons.text_snippet,
                        color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _delete(int i) {
    setState(() {
      _pages.removeAt(i);
      for (int k = 0; k < _pages.length; k++) {
        _pages[k].n = k + 1;
      }
    });
  }

  void _setCategory(int i, String cat) {
    setState(() => _pages[i].category = cat);
  }

  void _showCategoryPicker(int index) {
    final l10n = AppLocalizations.of(context)!;
    final categories = [
      l10n.categoryUncategorized,
      l10n.categoryDocument,
      l10n.categoryReceipt,
      l10n.categoryInvoice,
      l10n.categoryIdCard,
      l10n.categoryContract,
      l10n.categoryOther
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: DS.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (modalContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.setCategory,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories.map((cat) {
                  final isSelected = _pages[index].category == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: DS.indigo.withOpacity(0.3),
                    backgroundColor: DS.bgCard2,
                    labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.white54,
                        fontSize: 12),
                    onSelected: (_) {
                      _setCategory(index, cat);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _deleteBtn(VoidCallback onDelete) {
    return GestureDetector(
      onTap: onDelete,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: primary ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: primary
              ? null
              : Border.all(color: color.withOpacity(0.3), width: 1),
          boxShadow: primary
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6)),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: primary ? Colors.white : color, size: 22),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: primary ? Colors.white : color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    String label,
    bool active,
    VoidCallback onTap, {
    IconData icon = Icons.tune_rounded,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? DS.indigo.withOpacity(0.15) : DS.bgCard2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? DS.indigo.withOpacity(0.5) : DS.separator),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? DS.indigo : Colors.white38),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: active ? DS.indigo : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}