// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/web_download.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import 'pdf_viewer_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  static Future<void> show(BuildContext ctx) => Navigator.push(
      ctx, MaterialPageRoute(builder: (_) => const ScannerScreen()));
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _picker = ImagePicker();
  final List<_Page> _pages = [];
  bool _grayscale = false;
  bool _building = false;

  Future<void> _camera() async {
    try {
      final f = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 95,
          preferredCameraDevice: CameraDevice.rear);
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return;
      
      if (!kIsWeb) {
        final cropped = await Navigator.push<Uint8List>(context,
            MaterialPageRoute(builder: (_) => _CropScreen(imageBytes: bytes)));
        if (cropped == null || !mounted) return;
        setState(() => _pages.add(_Page(name: f.name, bytes: cropped, n: _pages.length + 1)));
      } else {
        final confirmed = await Navigator.push<Uint8List>(context,
            MaterialPageRoute(builder: (_) => _WebImagePreview(imageBytes: bytes, fileName: f.name)));
        if (confirmed != null && mounted) {
          setState(() => _pages.add(_Page(name: f.name, bytes: confirmed, n: _pages.length + 1)));
        }
      }
    } catch (e) { _snack('Camera: $e', err: true); }
  }

  Future<void> _gallery() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 92);
      if (!mounted || files.isEmpty) return;
      for (final f in files) {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty || !mounted) continue;
        
        if (!kIsWeb) {
          final cropped = await Navigator.push<Uint8List>(context,
              MaterialPageRoute(builder: (_) => _CropScreen(imageBytes: bytes)));
          if (cropped != null && mounted) {
            setState(() => _pages.add(_Page(name: f.name, bytes: cropped, n: _pages.length + 1)));
          }
        } else {
          final confirmed = await Navigator.push<Uint8List>(context,
              MaterialPageRoute(builder: (_) => _WebImagePreview(imageBytes: bytes, fileName: f.name)));
          if (confirmed != null && mounted) {
            setState(() => _pages.add(_Page(name: f.name, bytes: confirmed, n: _pages.length + 1)));
          }
        }
      }
    } catch (e) { _snack('Gallery: $e', err: true); }
  }

  void _delete(int i) {
    setState(() {
      _pages.removeAt(i);
      for (int k = 0; k < _pages.length; k++) _pages[k].n = k + 1;
    });
  }

  Future<void> _build() async {
    if (_pages.isEmpty) { _snack('Add at least one page'); return; }
    setState(() => _building = true);
    try {
      final doc = pw.Document();
      int good = 0;

      for (final pg in _pages) {
        Uint8List bytes = pg.bytes;
        double pw_ = 595.0, ph_ = 842.0;
        try {
          final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1, targetHeight: 1);
          final frame = await codec.getNextFrame();
          final w = frame.image.width; final h = frame.image.height;
          frame.image.dispose();
          if (w > 0 && h > 0) {
            final asp = w / h;
            if (asp >= 1.0) { pw_ = 842.0; ph_ = 842.0 / asp; }
            else { ph_ = 842.0; pw_ = 842.0 * asp; }
          }
        } catch (_) {}

        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat(pw_, ph_), margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill)));
        good++;
      }

      if (good == 0) { _snack('No pages processed', err: true); return; }
      final pdfBytes = Uint8List.fromList(await doc.save());

      if (kIsWeb) {
        final name = 'scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
        downloadFile(name, pdfBytes);
        if (mounted) {
          await Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: name, preloadedBytes: pdfBytes)));
        }
      } else {
        final path = await _saveToDisk(pdfBytes);
        if (mounted) {
          await Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path)));
        }
      }
    } catch (e) { if (mounted) _snack('Error: $e', err: true); }
    finally { if (mounted) setState(() => _building = false); }
  }

  Future<String> _saveToDisk(Uint8List bytes) async {
    final path = await PlatformFileService.outputPath('scan_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await PlatformFileService.writeBytes(path, bytes);
    return path;
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: err ? DS.red : DS.bgCard2, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12)));
  }

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
          onPressed: () => Navigator.pop(context)),
        title: Text('Document Scanner', style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          if (_pages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _building ? null : _build,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: Text('Create PDF (${_pages.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: DS.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
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
              width: 120, height: 120,
              decoration: BoxDecoration(
                color: DS.indigo.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(color: DS.indigo.withOpacity(0.15), width: 2),
              ),
              child: Icon(
                Icons.document_scanner_rounded,
                size: 52,
                color: DS.indigo.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 32),
            Text('Scan Documents', style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Capture pages with your camera or upload from gallery\nto create a professional PDF document',
              style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _pageGrid() {
    return Column(children: [
      Container(
        color: DS.bgCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(Icons.collections_rounded, color: DS.indigo, size: 18),
          const SizedBox(width: 8),
          Text('${_pages.length} page${_pages.length == 1 ? '' : 's'} · Tap × to remove',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          _chip('B&W', _grayscale, () => setState(() => _grayscale = !_grayscale)),
        ]),
      ),
      const Divider(height: 1, color: DS.separator),
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.72),
        itemCount: _pages.length,
        itemBuilder: (_, i) {
          final pg = _pages[i];
          return GestureDetector(
            onLongPress: () => _delete(i),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(pg.bytes, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                      errorBuilder: (_, __, ___) => Container(color: DS.bgCard2, child: const Center(child: Icon(Icons.broken_image, color: Colors.white24))))),
                Positioned(bottom: 6, left: 6, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(6)),
                    child: Text('${pg.n}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)))),
                Positioned(top: 6, right: 6, child: GestureDetector(
                    onTap: () => _delete(i),
                    child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1)),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 14)))),
              ]),
            ),
          );
        }),
      ),
      _captureButtons(),
    ]);
  }

  Widget _captureButtons() {
    return Container(
      decoration: BoxDecoration(
        color: DS.bgCard,
        border: Border(top: BorderSide(color: DS.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(children: [
            Expanded(child: _proBtn(Icons.photo_library_rounded, 'Gallery', DS.indigo, _gallery)),
            const SizedBox(width: 12),
            Expanded(child: _proBtn(Icons.camera_alt_rounded, 'Camera', DS.indigo, _camera, primary: true)),
          ]),
        ),
      ),
    );
  }

  Widget _proBtn(IconData icon, String label, Color color, VoidCallback onTap, {bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: primary ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: primary ? null : Border.all(color: color.withOpacity(0.3), width: 1),
          boxShadow: primary ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: primary ? Colors.white : color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: primary ? Colors.white : color, fontSize: 14, fontWeight: FontWeight.w600)),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.invert_colors_rounded, size: 14, color: active ? DS.indigo : Colors.white38),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: active ? DS.indigo : Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── Crop screen ─────────────────────────────────────────────────
class _CropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const _CropScreen({required this.imageBytes});
  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  final _ctrl = CropController();
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: const Color(0xFF1C1C1E), elevation: 0,
      leading: TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel', style: TextStyle(color: Colors.white60, fontSize: 14))),
      title: const Text('Crop Document', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
      centerTitle: true,
      actions: [TextButton(onPressed: _done ? null : () => _ctrl.crop(), child: _done ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo)) : const Text('Use', style: TextStyle(color: DS.indigo, fontSize: 15, fontWeight: FontWeight.w700)))],
    ),
    body: Column(children: [
      Expanded(child: Crop(image: widget.imageBytes, controller: _ctrl, onCropped: (bytes) => Navigator.pop(context, Uint8List.fromList(bytes)), onStatusChanged: (s) { if (s == CropStatus.cropping && mounted) setState(() => _done = true); }, maskColor: Colors.black54, cornerDotBuilder: (_, __) => const DotControl(color: DS.indigo))),
      Container(color: const Color(0xFF1C1C1E), padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _cropBtn(Icons.crop_free_rounded, 'Free', () => _ctrl.aspectRatio = null),
        _cropBtn(Icons.crop_portrait_rounded, 'A4', () => _ctrl.aspectRatio = 1/1.414),
        _cropBtn(Icons.crop_landscape_rounded, 'Wide', () => _ctrl.aspectRatio = 16/9),
        _cropBtn(Icons.crop_square_rounded, 'Square', () => _ctrl.aspectRatio = 1),
      ])),
      SizedBox(height: MediaQuery.of(context).padding.bottom),
    ]),
  );

  Widget _cropBtn(IconData icon, String label, VoidCallback t) => GestureDetector(onTap: t, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white70, size: 22), const SizedBox(height: 3), Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500))]));
}

// ── Web image preview ──────────────────────────────────────────
class _WebImagePreview extends StatefulWidget {
  final Uint8List imageBytes;
  final String fileName;
  const _WebImagePreview({required this.imageBytes, required this.fileName});
  @override
  State<_WebImagePreview> createState() => _WebImagePreviewState();
}

class _WebImagePreviewState extends State<_WebImagePreview> {
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: const Color(0xFF1C1C1E), elevation: 0,
      leading: TextButton(onPressed: () => Navigator.pop(context, widget.imageBytes), child: const Text('Cancel', style: TextStyle(color: Colors.white60, fontSize: 14))),
      title: Text(widget.fileName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      centerTitle: true,
      actions: [TextButton(onPressed: () => Navigator.pop(context, widget.imageBytes), child: const Text('Use', style: TextStyle(color: DS.indigo, fontSize: 15, fontWeight: FontWeight.w700)))],
    ),
    body: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 3.0, child: Image.memory(widget.imageBytes, fit: BoxFit.contain))),
  );
}

class _Page { final String name; final Uint8List bytes; int n;
  _Page({required this.name, required this.bytes, required this.n}); }