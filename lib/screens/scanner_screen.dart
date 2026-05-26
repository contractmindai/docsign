import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
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

// ---------------------------------------------------------------------------
// Smart Document Classifier (reuses TextRecognizer)
// ---------------------------------------------------------------------------
class SmartDocumentClassifier {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<String> classify(Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/classify_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);
      final inputImage = InputImage.fromFile(tempFile);
      final recognized = await _recognizer.processImage(inputImage);
      await tempFile.delete();
      final text = recognized.text.toLowerCase();
      if (text.contains('invoice')) return 'Invoice';
      if (text.contains('receipt')) return 'Receipt';
      if (text.contains('id card') || text.contains('passport')) return 'ID Card';
      if (text.contains('contract') || text.contains('agreement')) return 'Contract';
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

  late SmartDocumentClassifier _classifier;
  late final TextRecognizer _ocrRecognizer; // dedicated for OCR

  @override
  void initState() {
    super.initState();
    _classifier = SmartDocumentClassifier();
    _ocrRecognizer = TextRecognizer(); // reusable for all OCR calls
  }

  @override
  void dispose() {
    _classifier.dispose();
    _ocrRecognizer.close();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Clear all pages and cache
  // --------------------------------------------------------------------------
  void _clearAll() async {
    setState(() {
      _pages.clear();
    });
    // Clear cached files (optional)
     PlatformFileService.clearCache(); // implement if not exists (see below)
    _snack('Cleared all pages');
  }

  // --------------------------------------------------------------------------
  // Scan using doc_scan_flutter
  // --------------------------------------------------------------------------
  Future<void> _autoDetectScan() async {
    if (kIsWeb) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Not available on web'),
          content: const Text(
              'Document scanning requires a real device with a camera.\n\nPlease use the mobile app or upload images from the gallery.'),
          actions: [TextButton(onPressed: () => Navigator.pop(_), child: const Text('OK'))],
        ),
      );
      return;
    }

    try {
      final List<String>? scannedImages = await DocumentScanner.scan();

      if (scannedImages != null && scannedImages.isNotEmpty && mounted) {
        for (final imagePath in scannedImages) {
          final bytes = await File(imagePath).readAsBytes();
          await _addScannedPage(bytes, 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }

        if (_batchMode && mounted) {
          _autoDetectScan();
        }
      }
    } on DocumentScannerException catch (e) {
      if (mounted) _snack('Scanning error: $e', err: true);
    } catch (e) {
      if (mounted) _snack('An unexpected error occurred: $e', err: true);
    }
  }

  // --------------------------------------------------------------------------
  // Gallery pick
  // --------------------------------------------------------------------------
  Future<void> _gallery() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 92);
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
      _snack('Gallery: $e', err: true);
    }
  }

  // --------------------------------------------------------------------------
  // Process image: manual editor → grayscale → classification (category)
  // --------------------------------------------------------------------------
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
    return Uint8List.fromList(img.encodeJpg(gray, quality: 85));
  }

  // --------------------------------------------------------------------------
  // Optimized OCR (reuses recognizer, no double decoding)
  // --------------------------------------------------------------------------
  Future<void> _performOCR(Uint8List imageBytes) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);
      final inputImage = InputImage.fromFile(tempFile);
      final recognized = await _ocrRecognizer.processImage(inputImage);
      await tempFile.delete();

      if (mounted) {
        Navigator.pop(context);
        if (recognized.text.isNotEmpty) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Extracted Text'),
              content: SingleChildScrollView(
                child: Text(recognized.text, style: const TextStyle(fontSize: 14)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(_),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        } else {
          _snack('No text found in this image.');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _snack('OCR error: $e', err: true);
      }
    }
  }

  // --------------------------------------------------------------------------
  // PDF creation with automatic memory clear
  // --------------------------------------------------------------------------
  Future<void> _build() async {
    if (_pages.isEmpty) {
      _snack('Add at least one page');
      return;
    }

    setState(() => _building = true);
    try {
      final doc = pw.Document(compress: true);
      const double targetDpi = 300.0;
      const double pdfDpi = 72.0;
      final double scale = pdfDpi / targetDpi;

      for (final pg in _pages) {
        final Uint8List bytes = pg.bytes;
        if (bytes.length < 100) {
          _snack('Image data corrupted for ${pg.name}', err: true);
          continue;
        }
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final imgWidget = frame.image;
        final pxW = imgWidget.width.toDouble();
        final pxH = imgWidget.height.toDouble();
        imgWidget.dispose();
        codec.dispose();
        final pageW = pxW * scale;
        final pageH = pxH * scale;
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pageW, pageH),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
          ),
        );
      }

      final pdfBytes = Uint8List.fromList(await doc.save());
      final defaultName = 'scan_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // Clear pages from memory
      setState(() => _pages.clear());

      if (kIsWeb) {
        downloadFile(defaultName, pdfBytes);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PdfViewerScreen(
                filePath: defaultName,
                preloadedBytes: pdfBytes,
              ),
            ),
          );
        }
      } else {
        final path = await _saveToDisk(pdfBytes, defaultName);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path)),
          );
        }
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', err: true);
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

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
        backgroundColor: err ? DS.red : DS.bgCard2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

Future<String?> _askFileName({String? defaultName}) async {
  final controller = TextEditingController(text: defaultName ?? 'document');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DS.bgCard,
      title: Text('Save PDF as',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Enter file name',
          filled: true,
          fillColor: DS.bgCard2,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: DS.indigo),
          child: const Text('Create PDF'),
        ),
      ],
    ),
  );
}

Future<void> _addScannedPage(Uint8List bytes, String name) async {
  // Apply grayscale if the user wants it
  final finalBytes = _grayscale ? _applyGrayscale(bytes) : bytes;

  if (finalBytes.isNotEmpty && mounted) {
    // Classify the page
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

    // OCR if text extraction is on
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Document Scanner',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          if (_pages.isNotEmpty)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, color: DS.red, size: 22),
                  tooltip: 'Clear all',
                  onPressed: _clearAll,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _building ? null : _build,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: Text('Create PDF (${_pages.length})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: DS.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _pages.isEmpty ? _emptyState() : _pageGrid(),
      bottomNavigationBar: _pages.isEmpty ? _captureButtons() : null,
    );
  }

  Widget _emptyState() {
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
                border: Border.all(color: DS.indigo.withOpacity(0.15), width: 2),
              ),
              child: Icon(Icons.document_scanner_rounded, size: 52, color: DS.indigo.withOpacity(0.6)),
            ),
            const SizedBox(height: 32),
            Text('Scan Documents',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Capture pages with your camera or upload from gallery\nto create a professional PDF document',
              style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageGrid() {
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
                  const Icon(Icons.collections_rounded, color: DS.indigo, size: 18),
                  const SizedBox(width: 8),
                  const Spacer(),
                  _chip('B&W', _grayscale, () => setState(() => _grayscale = !_grayscale)),
                  const SizedBox(width: 8),
                  _chip('Batch', _batchMode, () => setState(() => _batchMode = !_batchMode)),
                  const SizedBox(width: 8),
                  _chip('Extract Text', _extractText, () => setState(() => _extractText = !_extractText)),
                ],
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
            _captureButtons(),
          ],
        );
      },
    );
  }

  Widget _pageTile(int i) {
    final pg = _pages[i];
    return GestureDetector(
      onLongPress: () => _delete(i),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: DS.bgCard2,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(pg.bytes, fit: BoxFit.cover),
              // Gradient overlay at the bottom
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
                      colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                    ),
                  ),
                ),
              ),
              // Page number (bottom-left)
              Positioned(
                bottom: 8,
                left: 8,
                child: Text('Page ${pg.n}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              // Category label (bottom-right)
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _showCategoryPicker(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.label_outline, size: 10, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(pg.category, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Delete button (top‑right) ──
              Positioned(top: 6, right: 6, child: _deleteBtn(() => _delete(i))),

              // ── NEW: OCR button (top‑left) ──
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: () => _performOCR(pg.bytes),   // ← runs OCR for this page
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Icon(Icons.text_snippet, color: Colors.white, size: 14),
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
    final categories = ['Uncategorized', 'Document', 'Receipt', 'Invoice', 'ID Card', 'Contract', 'Other'];
    showModalBottomSheet(
      context: context,
      backgroundColor: DS.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (modalContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set Category',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
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
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 12),
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

  Widget _captureButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      decoration: BoxDecoration(
        color: DS.bgCard,
        border: Border(top: BorderSide(color: DS.separator.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Expanded(
              child: _actionCard(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  color: DS.cyan,
                  onTap: _gallery)),
          const SizedBox(width: 12),
          Expanded(
              child: _actionCard(
                  icon: Icons.camera_alt_rounded,
                  label: 'Scan',
                  color: DS.indigo,
                  onTap: _autoDetectScan,
                  primary: true)),
        ],
      ),
    );
  }

  Widget _actionCard(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
      bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: primary ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: primary ? null : Border.all(color: color.withOpacity(0.3), width: 1),
          boxShadow: primary
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: primary ? Colors.white : color, size: 22),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(color: primary ? Colors.white : color, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? DS.indigo.withOpacity(0.15) : DS.bgCard2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? DS.indigo.withOpacity(0.5) : DS.separator),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.invert_colors_rounded, size: 14, color: active ? DS.indigo : Colors.white38),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: active ? DS.indigo : Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

