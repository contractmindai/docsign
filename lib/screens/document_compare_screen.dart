import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/pdf_loader.dart';
import '../services/text_search_service.dart';
import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';

class DocumentCompareScreen extends StatefulWidget {
  final String pathA;
  const DocumentCompareScreen({super.key, required this.pathA});

  static void show(BuildContext ctx, String pathA) => Navigator.push(ctx,
      MaterialPageRoute(builder: (_) => DocumentCompareScreen(pathA: pathA)));
  @override
  State<DocumentCompareScreen> createState() => _DocumentCompareScreenState();
}

class _DocumentCompareScreenState extends State<DocumentCompareScreen> {
  PdfDocument? _docA, _docB;
  int _pagesA = 0, _pagesB = 0;
  bool _loadingA = true, _loadingB = false;
  double _diff = 0;
  bool _diffDone = false;
  final Map<String, Uint8List?> _cache = {};
  final _scrollA = ScrollController();
  final _scrollB = ScrollController();
  bool _syncing  = false;
  String? _pathB;

  @override
  void initState() {
    super.initState();
    _loadA();
    _scrollA.addListener(_syncA);
    _scrollB.addListener(_syncB);
  }

  @override
  void dispose() {
    _scrollA.dispose(); _scrollB.dispose(); super.dispose();
  }

  Future<void> _loadA() async {
    try {
      final doc = await PdfLoader.openForViewing(
          path: widget.pathA,
          bytes: PlatformFileService.getCached(widget.pathA));
      if (mounted) setState(() { _docA = doc; _pagesA = doc.pages.length; _loadingA = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingA = false);
    }
  }

  Future<void> _pickB() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: kIsWeb);
    if (r == null || r.files.isEmpty || !mounted) return;

    final pf   = r.files.first;
    // ✅ Safe path access: never use pf.path on web
    final path = kIsWeb ? pf.name : (pf.path ?? pf.name);
    if (kIsWeb && pf.bytes != null) PlatformFileService.cache(path, pf.bytes!);

    setState(() => _loadingB = true);
    try {
      final doc = await PdfLoader.openForViewing(
          path: path, bytes: PlatformFileService.getCached(path));
      if (mounted) {
        setState(() {
          _pathB = path; _docB = doc;
          _pagesB = doc.pages.length; _loadingB = false;
        });
        _runDiff();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingB = false);
    }
  }

  Future<void> _runDiff() async {
    if (_docA == null || _docB == null) return;
    setState(() => _diffDone = false);
    final pages = math.min(_pagesA, _pagesB);
    double total = 0;
    for (int i = 0; i < math.min(pages, 3); i++) {
      final bA = await _renderLow(_docA!, i);
      final bB = await _renderLow(_docB!, i);
      if (bA != null && bB != null) total += _pixelDiff(bA, bB);
    }
    if (mounted) setState(() { _diff = total / math.min(pages, 3); _diffDone = true; });
  }

  Future<Uint8List?> _renderLow(PdfDocument doc, int idx) async {
    try {
      final page  = doc.pages[idx];
      const w = 120.0;
      final h     = w / (page.width / page.height);
      final img   = await page.render(fullWidth: w, fullHeight: h,
          backgroundColor: const Color(0xFFFFFFFF));
      if (img == null) return null;
      return _pdfImageToPng(img);
    } catch (_) { return null; }
  }

  double _pixelDiff(Uint8List a, Uint8List b) {
    int diff = 0, count = 0;
    final len = math.min(a.length, b.length);
    for (int i = 0; i < len; i += 4) {
      diff += (a[i] - b[i]).abs() + (a[i+1] - b[i+1]).abs() + (a[i+2] - b[i+2]).abs();
      count++;
    }
    return count == 0 ? 0 : (diff / count / 255.0).clamp(0.0, 1.0);
  }

  void _syncA() {
    if (_syncing || !_scrollB.hasClients) return;
    _syncing = true;
    _scrollB.jumpTo(_scrollA.offset);
    _syncing = false;
  }

  void _syncB() {
    if (_syncing || !_scrollA.hasClients) return;
    _syncing = true;
    _scrollA.jumpTo(_scrollB.offset);
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    DS.setStatusBar();
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard, surfaceTintColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('Compare', style: GoogleFonts.inter(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          if (_diffDone)
            Container(margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _diff < 0.05 ? DS.green.withOpacity(0.15) : DS.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12)),
              child: Text('${(_diff * 100).toStringAsFixed(0)}% diff',
                  style: TextStyle(
                      color: _diff < 0.05 ? DS.green : DS.orange,
                      fontSize: 11, fontWeight: FontWeight.w700))),
        ],
      ),
      body: Column(children: [
        // Doc B picker
        if (_docB == null)
          Container(
            padding: const EdgeInsets.all(16),
            color: DS.bgCard,
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Document A loaded', style: DS.body(size: 12, color: DS.green)),
                Text('Select document B to compare', style: DS.caption()),
              ])),
              FilledButton.icon(
                onPressed: _loadingB ? null : _pickB,
                icon: const Icon(Icons.file_open_rounded, size: 16),
                label: Text(_loadingB ? 'Loading…' : 'Select PDF B'),
                style: FilledButton.styleFrom(backgroundColor: DS.indigo)),
            ]))
        else
          const Divider(height: 1, color: DS.separator),
        // Side-by-side view
        Expanded(child: _docA == null
            ? const Center(child: CircularProgressIndicator(color: DS.indigo))
            : _docB == null
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.compare_rounded, size: 48, color: DS.textTertiary),
                    const SizedBox(height: 12),
                    Text('Select a second PDF to compare',
                        style: DS.caption().copyWith(fontSize: 15))]))
                : Row(children: [
                    Expanded(child: _PdfColumn(
                        doc: _docA!, pages: _pagesA, loading: _loadingA,
                        label: 'Original', cache: _cache, side: 'A',
                        scroll: _scrollA)),
                    Container(width: 1, color: DS.separator),
                    Expanded(child: _PdfColumn(
                        doc: _docB!, pages: _pagesB, loading: _loadingB,
                        label: 'Modified', cache: _cache, side: 'B',
                        scroll: _scrollB)),
                  ])),
      ]),
    );
  }
}

// ✅ Convert PdfImage (pdfrx 1.3.5) to PNG bytes
Future<Uint8List?> _pdfImageToPng(PdfImage img) async {
  try {
    final comp = Completer<ui.Image>();
    ui.decodeImageFromPixels(img.pixels, img.width, img.height,
        ui.PixelFormat.bgra8888, (i) => comp.complete(i));
    final uiImg = await comp.future;
    final bd    = await uiImg.toByteData(format: ui.ImageByteFormat.png);
    uiImg.dispose();
    return bd?.buffer.asUint8List();
  } catch (_) { return null; }
}

// ── PDF column widget ─────────────────────────────────────────────────────────

class _PdfColumn extends StatelessWidget {
  final PdfDocument doc;
  final int pages;
  final bool loading;
  final String label, side;
  final Map<String, Uint8List?> cache;
  final ScrollController scroll;

  const _PdfColumn({required this.doc, required this.pages,
      required this.loading, required this.label, required this.side,
      required this.cache, required this.scroll});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(
        child: CircularProgressIndicator(color: DS.indigo));

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: DS.bgCard,
        child: Row(children: [
          Text(label, style: DS.body(size: 12, color: DS.indigo)),
          const Spacer(),
          Text('$pages pages', style: DS.caption()),
        ])),
      Expanded(child: ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.all(8),
        itemCount: pages,
        itemBuilder: (_, i) => _PageTile(
            doc: doc, pageIndex: i, side: side, cache: cache))),
    ]);
  }
}

// ── Page tile ─────────────────────────────────────────────────────────────────

class _PageTile extends StatefulWidget {
  final PdfDocument doc;
  final int pageIndex;
  final String side;
  final Map<String, Uint8List?> cache;
  const _PageTile({required this.doc, required this.pageIndex,
      required this.side, required this.cache});
  @override
  State<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<_PageTile> {
  @override
  void initState() { super.initState(); _render(); }

  Future<void> _render() async {
    final key = '${widget.side}_${widget.pageIndex}';
    if (widget.cache.containsKey(key)) { if (mounted) setState(() {}); return; }
    try {
      final page  = widget.doc.pages[widget.pageIndex];
      // ✅ Use context width inside build — use a fixed width here
      const renderW = 300.0;
      final renderH = renderW / (page.width / page.height);
      final img     = await page.render(fullWidth: renderW, fullHeight: renderH,
          backgroundColor: const Color(0xFFFFFFFF));
      if (img == null) return;
      final bytes = await _pdfImageToPng(img);
      if (mounted) { widget.cache[key] = bytes; setState(() {}); }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final key   = '${widget.side}_${widget.pageIndex}';
    final bytes = widget.cache[key];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DS.bgCard, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DS.separator, width: 0.5)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Text('Page ${widget.pageIndex + 1}',
                style: DS.caption().copyWith(fontSize: 10)),
          ])),
        if (bytes != null)
          ClipRRect(borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(7)),
            child: Image.memory(bytes, fit: BoxFit.fitWidth,
                width: double.infinity))
        else
          const Padding(padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                  color: DS.indigo, strokeWidth: 2)),
      ]),
    );
  }
}
