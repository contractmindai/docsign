import 'dart:convert';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

import '../models/annotation.dart';
import '../models/signer_profile.dart';
import '../services/annotation_persistence_service.dart';
import '../services/expiry_detector.dart';
import '../services/pdf_save_service.dart';
import '../services/signer_profile_service.dart';
import '../utils/web_download.dart';
import '../utils/platform_file_service.dart';
import '../services/pdf_loader.dart';
import '../widgets/annotation_summary_panel.dart';
import '../widgets/audit_trail_widget.dart';
import '../widgets/ds.dart';
import '../widgets/pdf_page_widget.dart';
import '../widgets/pro_panels.dart';
import '../widgets/search_panel.dart';
import '../widgets/signature_dialog.dart';
import '../widgets/signer_profile_dialog.dart';
import '../widgets/thumbnail_strip.dart';
import 'document_compare_screen.dart';
import 'pdf_tools_screen.dart';

class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final Uint8List? preloadedBytes;
  const PdfViewerScreen({super.key, required this.filePath, this.preloadedBytes});
  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen>
    with SingleTickerProviderStateMixin {

  PdfDocument? _doc;
  int _pageCount = 0;
  bool _docLoading = true;
  String? _docError;
  String? _password;

  final _scroll = ScrollController();
  int _visPage = 1;
  
  _TabMode _currentTab = _TabMode.annotate;
  AnnotationTool _tool = AnnotationTool.view;
  Color _inkColor = DS.indigo;

  final Map<int, List<RectAnnotation>> _rects = {};
  final Map<int, InkAnnotation> _ink = {};
  final Map<int, List<StickyNote>> _notes = {};
  final Map<int, List<SignatureOverlay>> _sigs = {};
  final Map<int, List<TextStamp>> _stamps = {};
  final Map<int, List<RedactionRect>> _redacts = {};
  final Map<int, List<ClauseBookmark>> _clauses = {};
  final Map<int, List<TextEditAnnotation>> _textEdits = {};
  final Map<String, String?> _signatureIps = {};
  final List<VoidCallback> _undoStack = [];

  Uint8List? _pendingSig;
  bool _initialsMode = false;
  List<SignatureSlot> _slots = [];
  String? _activeSlotId;
  SignerProfile? _profile;
  List<ExpiryDate> _expiries = [];
  bool _showExpiryBanner = false;
  bool _darkMode = false;
  bool _showSearch = false;
  bool _showThumbs = true;
  bool _isSaving = false;
  bool _readMode = true;
  bool _isSaved = true;  // ✅ Save status indicator

  double _defaultZoom = 1.0;

  DateTime? _lastMutation;
  final _uuid = const Uuid();

  bool get _annotating => _tool != AnnotationTool.view || _pendingSig != null;
  Uint8List? get _sourceBytes => widget.preloadedBytes ?? PlatformFileService.getCached(widget.filePath);

  @override
  void initState() {
    super.initState();
    _openDoc();
    _loadProfile();
    _scroll.addListener(_trackPage);
  }

  @override
  void dispose() {
    _autosaveNow();
    _scroll.dispose();
    super.dispose();
  }

  Future<String?> _getIpAddress() async {
    try {
      final uri = Uri.parse('https://api.ipify.org?format=json');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['ip'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _openDoc({String? password}) async {
    if (mounted) setState(() { _docLoading = true; _docError = null; });
    try {
      final doc = await PdfLoader.openForViewing(path: widget.filePath, bytes: _sourceBytes, password: password);
      if (mounted) setState(() { _doc = doc; _pageCount = doc.pages.length; _docLoading = false; });
      await _loadSidecar();
      _detectExpiry();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password') || msg.contains('encrypted') || msg.contains('unknown') || msg.contains('w1.d')) {
        if (mounted) { setState(() => _docLoading = false); _showPasswordDialog(); }
      } else {
        if (mounted) setState(() { _docLoading = false; _docError = e.toString(); });
      }
    }
  }

  Future<void> _showPasswordDialog() async {
    final ctrl = TextEditingController();
    final pwd = await showDialog<String>(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: DS.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [const Icon(Icons.lock_rounded, color: DS.orange, size: 20), const SizedBox(width: 8), Text('Password Protected', style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))]),
        content: TextField(controller: ctrl, autofocus: true, obscureText: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Password', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: DS.bgCard2, prefixIcon: const Icon(Icons.key_rounded, color: DS.indigo, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo))), onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))), FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), style: FilledButton.styleFrom(backgroundColor: DS.indigo), child: const Text('Open'))]));
    if (pwd != null && pwd.isNotEmpty) { _password = pwd; _openDoc(password: pwd); }
    else if (mounted) Navigator.pop(context);
  }

  void _trackPage() {
    if (!_scroll.hasClients || !mounted) return;
    final sw = MediaQuery.of(context).size.width;
    final ph = sw / 1.414 + 12;
    final pg = (_scroll.offset / ph).floor() + 1;
    if (pg != _visPage && pg >= 1 && pg <= _pageCount) setState(() => _visPage = pg);
  }

  void _toggleReadMode() {
    setState(() => _readMode = !_readMode);
    _snack(_readMode ? 'Read Mode — Scroll to navigate' : 'Zoom Mode — Pinch to zoom');
  }

  Future<void> _loadSidecar() async {
    final snap = await AnnotationPersistenceService.load(widget.filePath);
    if (snap == null || snap.isEmpty || !mounted) return;
    setState(() { _rects..clear()..addAll(snap.rects); _notes..clear()..addAll(snap.notes); _stamps..clear()..addAll(snap.stamps); _redacts..clear()..addAll(snap.redactions); _clauses..clear()..addAll(snap.bookmarks); _textEdits..clear()..addAll(snap.textEdits); snap.ink.forEach((k, v) { if (v != null) _ink[k] = v as InkAnnotation; }); });
  }

  Future<void> _loadProfile() async { final pr = await SignerProfileService.loadProfile(); if (mounted) setState(() => _profile = pr); }

  Future<void> _detectExpiry() async {
    try { final bytes = _sourceBytes ?? await PlatformFileService.readBytes(widget.filePath) ?? Uint8List(0); if (bytes.isEmpty) return; final raw = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127).take(60000)); final found = ExpiryDetector.detect(raw, 0); if (found.isNotEmpty && mounted) setState(() { _expiries = found; _showExpiryBanner = true; }); } catch (_) {}
  }

  void _markMutated() {
    _lastMutation = DateTime.now();
    setState(() => _isSaved = false);  // ✅ Show unsaved
    Future.delayed(const Duration(seconds: 3), _autosaveNow);
  }
  Future<void> _autosaveNow() async {
    if (_lastMutation == null) return;
    _lastMutation = null;
    try {
      await AnnotationPersistenceService.save(
        pdfPath: widget.filePath, rects: _rects, ink: _ink,
        notes: _notes, stamps: _stamps, redactions: _redacts, bookmarks: _clauses,
        textEdits: _textEdits);
      if (mounted) setState(() => _isSaved = true);  // ✅ Show saved
    } catch (_) {}
  }
  void _switchTab(_TabMode tab) { setState(() { _currentTab = tab; _tool = tab == _TabMode.edit ? AnnotationTool.textStamp : AnnotationTool.view; }); }
  void _onToolChanged(AnnotationTool t) { if (t == AnnotationTool.signature || t == AnnotationTool.initials) { _launchSigDialog(isInitials: t == AnnotationTool.initials); return; } setState(() { _tool = t; _pendingSig = null; _initialsMode = false; }); }
  Future<void> _launchSigDialog({bool isInitials = false}) async { final bytes = await SignatureDialog.show(context); if (bytes == null || !mounted) return; setState(() { _pendingSig = bytes; _initialsMode = isInitials; _tool = isInitials ? AnnotationTool.initials : AnnotationTool.signature; }); }

  void _addRect(RectAnnotation a) => _mutate(() { _rects.putIfAbsent(a.pageIndex, () => []).add(a); _undoStack.add(() => setState(() => _rects[a.pageIndex]?.removeWhere((r) => r.id == a.id))); });
  void _addInk(int pg, InkStroke s) => _mutate(() { final ex = _ink[pg]; _ink[pg] = ex == null ? InkAnnotation(id: _uuid.v4(), pageIndex: pg, strokes: [s]) : ex.addStroke(s); _undoStack.add(() => setState(() { final c = _ink[pg]; if (c == null) return; if (c.strokes.length == 1) { _ink.remove(pg); return; } _ink[pg] = InkAnnotation(id: c.id, pageIndex: pg, strokes: c.strokes.sublist(0, c.strokes.length - 1)); })); });
  void _addNote(StickyNote n) => _mutate(() { _notes.putIfAbsent(n.pageIndex, () => []).add(n); _undoStack.add(() => setState(() => _notes[n.pageIndex]?.removeWhere((x) => x.id == n.id))); });
  void _toggleNote(String id, bool e) => setState(() { for (final l in _notes.values) { for (final n in l) { if (n.id == id) n.isExpanded = e; } } });
  void _placeSig(SignatureOverlay sig) async { final ip = await _getIpAddress(); final m = SignatureOverlay(id: sig.id, imageBytes: sig.imageBytes, pageIndex: sig.pageIndex, normPosition: sig.normPosition, normSize: sig.normSize, isInitials: sig.isInitials, slotId: _activeSlotId, signerName: _profile?.fullName); _mutate(() { _sigs.putIfAbsent(m.pageIndex, () => []).add(m); _pendingSig = null; _initialsMode = false; _tool = AnnotationTool.view; _undoStack.add(() => setState(() => _sigs[m.pageIndex]?.removeWhere((s) => s.id == m.id))); }); if (ip != null) _signatureIps[m.id] = ip; }
  void _moveSig(String id, Offset pos) => setState(() { for (final l in _sigs.values) { for (final s in l) { if (s.id == id) s.normPosition = pos; } } _markMutated(); });
  void _resizeSig(String id, Size sz) => setState(() { for (final l in _sigs.values) { for (final s in l) { if (s.id == id) s.normSize = sz; } } _markMutated(); });
  void _deleteSig(String id) => setState(() { for (final l in _sigs.values) l.removeWhere((s) => s.id == id); _signatureIps.remove(id); _markMutated(); });
  void _addStamp(TextStamp s) => _mutate(() { _stamps.putIfAbsent(s.pageIndex, () => []).add(s); _undoStack.add(() => setState(() => _stamps[s.pageIndex]?.removeWhere((x) => x.id == s.id))); });
  void _addRedact(RedactionRect r) => _mutate(() { _redacts.putIfAbsent(r.pageIndex, () => []).add(r); _undoStack.add(() => setState(() => _redacts[r.pageIndex]?.removeWhere((x) => x.id == r.id))); });
  void _addBookmark(ClauseBookmark b) => _mutate(() { _clauses.putIfAbsent(b.pageIndex, () => []).add(b); _undoStack.add(() => setState(() => _clauses[b.pageIndex]?.removeWhere((x) => x.id == b.id))); });
  void _addTextEdit(TextEditAnnotation t) => _mutate(() { _textEdits.putIfAbsent(t.pageIndex, () => []).add(t); _undoStack.add(() => setState(() => _textEdits[t.pageIndex]?.removeWhere((x) => x.id == t.id))); });
  void _mutate(VoidCallback fn) { setState(fn); _markMutated(); }

  Map<int, int> get _annCounts { final m = <int, int>{}; for (int i = 0; i < _pageCount; i++) { final c = (_rects[i]?.length ?? 0) + (_notes[i]?.length ?? 0) + (_sigs[i]?.length ?? 0) + (_stamps[i]?.length ?? 0) + (_redacts[i]?.length ?? 0) + (_clauses[i]?.length ?? 0) + (_textEdits[i]?.length ?? 0) + (_ink[i] != null ? 1 : 0); if (c > 0) m[i] = c; } return m; }
  void _undo() { if (_undoStack.isEmpty) return; _undoStack.removeLast()(); _markMutated(); }

  Future<String?> _buildPdf() => PdfSaveService.save(sourcePath: widget.filePath, pageCount: _pageCount, rectAnnotations: _rects, inkAnnotations: _ink, stickyNotes: _notes, signatures: _sigs, textStamps: _stamps, redactions: _redacts, bookmarks: _clauses, textEdits: _textEdits, slots: _slots, signerProfile: _profile, signatureIps: _signatureIps, sourceBytes: _sourceBytes);

  Future<void> _save() async { if (_isSaving) return; String? customDir; if (!kIsWeb) customDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose save location'); setState(() => _isSaving = true); try { final path = await _buildPdf(); if (path == null) throw Exception('Build failed'); if (customDir != null && !kIsWeb) { final dest = '$customDir/${p.basename(path)}'; final bytes = await PlatformFileService.readBytes(path); if (bytes != null) await PlatformFileService.writeBytes(dest, bytes); _snack('Saved to $customDir', duration: 4); } else if (kIsWeb) { final bytes = PlatformFileService.getCached(path); if (bytes != null) { downloadFile(p.basename(path), bytes); _snack('Downloaded ${p.basename(path)}'); } } else { _snack('Saved ${p.basename(path)}'); } } catch (e) { if (mounted) _snack('Save failed: $e', err: true); } finally { if (mounted) setState(() => _isSaving = false); } }
  Future<void> _share() async { if (_isSaving) return; setState(() => _isSaving = true); try { final path = await _buildPdf(); if (path == null) throw Exception('Build failed'); if (kIsWeb) { final bytes = PlatformFileService.getCached(path); if (bytes != null) downloadFile(p.basename(path), bytes); } else { await Share.shareXFiles([XFile(path)], subject: p.basename(path)); } } catch (e) { if (mounted) _snack('Share failed: $e', err: true); } finally { if (mounted) setState(() => _isSaving = false); } }
  Future<void> _print() async { try { final path = await _buildPdf(); if (path == null) return; final bytes = await PlatformFileService.readBytes(path) ?? Uint8List(0); await Printing.layoutPdf(onLayout: (_) async => bytes); } catch (e) { if (mounted) _snack('Print error: $e', err: true); } }

  void _scrollToPage(int idx) { if (!_scroll.hasClients) return; final sw = MediaQuery.of(context).size.width - (kIsWeb && MediaQuery.of(context).size.width > 700 ? 200 : 0); final ph = sw / 1.414 + 12; _scroll.animateTo((idx * ph).clamp(0.0, _scroll.position.maxScrollExtent), duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }
  void _snack(String msg, {bool err = false, int duration = 3}) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)), backgroundColor: err ? DS.red : DS.bgCard2, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.all(12), duration: Duration(seconds: duration))); }
  
  void _openTools() {
    // ✅ Pass both bytes AND document
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PdfToolsScreen(
        filePath: widget.filePath,
        fileBytes: _sourceBytes,  // ✅ Pass the bytes!
        document: _doc,           // ✅ Pass the document!
      )));
  }
  // ✅ One-Click Email Signed PDF
  Future<void> _emailSignedPdf() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    
    try {
      final path = await _buildPdf();
      if (path == null) throw Exception('Build failed');
      
      final name = p.basenameWithoutExtension(widget.filePath);
      final subject = 'Signed: $name';
      final body = 'Please find the signed document attached.\n\n'
                   'Signed via DocSign — Free PDF Tools\n'
                   'https://pdf.contractmind.ai';
      
      if (kIsWeb) {
        final uri = Uri(scheme: 'mailto', queryParameters: {
          'subject': subject,
          'body': '$body\n\n(Attach the downloaded PDF manually)',
        });
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          _snack('Email client opened');
        }
      } else {
        await Share.shareXFiles(
          [XFile(path, mimeType: 'application/pdf')],
          subject: subject,
          text: body,
        );
        _snack('Choose Email to send');
      }
    } catch (e) {
      if (mounted) _snack('Email failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  bool get _isIOS {
    return Theme.of(context).platform == TargetPlatform.iOS;
  }
  // ✅ Add method to calculate fit-width zoom
  void _calculateFitZoom(double pageWidth, double displayWidth) {
    if (displayWidth > 0 && pageWidth > 0) {
      // Fit page width exactly, with 4% margin
      _defaultZoom = (displayWidth / pageWidth) * 0.96;
      _defaultZoom = _defaultZoom.clamp(0.8, 1.5); // Min 80%, Max 150%
    }
  }

  @override
  Widget build(BuildContext context) {
    DS.setStatusBar();
    final isWideWeb = kIsWeb && MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: _darkMode ? Colors.black : const Color(0xFFF0F0F0),
      body: Column(children: [
        SafeArea(bottom: false, child: Container(
          height: 52, color: DS.bgCard,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20), onPressed: () => Navigator.pop(context)),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(p.basename(widget.filePath), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white), overflow: TextOverflow.ellipsis, maxLines: 1),
              if (_pageCount > 0) Text('p.$_visPage / $_pageCount', style: DS.caption().copyWith(fontSize: 10)),
            ])),
            IconButton(icon: Icon(_readMode ? Icons.menu_book_rounded : Icons.zoom_in_rounded, color: Colors.white54, size: 20), tooltip: _readMode ? 'Read Mode' : 'Zoom Mode', onPressed: _toggleReadMode),
            if (_isSaving) const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo))) else IconButton(icon: const Icon(Icons.save_rounded, color: DS.indigo, size: 22), tooltip: kIsWeb ? 'Download' : 'Save', onPressed: _save),
            IconButton(icon: Icon(kIsWeb ? Icons.download_rounded : Icons.ios_share_rounded, color: DS.indigo, size: 20), onPressed: _share),
          ]),
        )),
        if (_showSearch && _doc != null) SearchPanel(pdfPath: widget.filePath, pageCount: _pageCount, onNavigate: (pg) { setState(() => _visPage = pg); _scrollToPage(pg-1); }, onClose: () => setState(() => _showSearch = false)),
        if (_showExpiryBanner && _expiries.isNotEmpty) Container(color: const Color(0xFFB45309).withOpacity(0.9), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber), const SizedBox(width: 6), Expanded(child: Text(ExpiryDetector.urgencyLabel(_expiries.first), style: const TextStyle(color: Colors.white, fontSize: 11))), IconButton(icon: const Icon(Icons.close_rounded, size: 12, color: Colors.white54), onPressed: () => setState(() => _showExpiryBanner = false), visualDensity: VisualDensity.compact)])),
        if (_pendingSig != null) Container(color: DS.indigo.withOpacity(0.15), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Row(children: [const Icon(Icons.touch_app_rounded, color: DS.indigo, size: 14), const SizedBox(width: 6), Expanded(child: Text('Tap page to place ${_initialsMode ? "initials" : "signature"}', style: TextStyle(color: DS.indigo, fontSize: 12))), TextButton(onPressed: () => setState(() { _pendingSig = null; _tool = AnnotationTool.view; }), child: const Text('Cancel', style: TextStyle(fontSize: 11)))])),
        Expanded(child: Row(children: [
          if (isWideWeb && _showThumbs && _doc != null) Container(width: 88, color: DS.bgCard, child: _SidebarThumbs(doc: _doc!, pageCount: _pageCount, currentPage: _visPage, darkMode: _darkMode, annotationCounts: _annCounts, onPageSelected: (pg) { setState(() => _visPage = pg); _scrollToPage(pg - 1); })),
          Expanded(child: _docLoading ? const Center(child: CircularProgressIndicator(color: DS.indigo)) : _docError != null ? _errorView() : _doc == null ? const SizedBox() : _pageList()),
        ])),
        if (!isWideWeb && _showThumbs && _doc != null) SizedBox(height: 80, child: ThumbnailStrip(document: _doc!, pageCount: _pageCount, currentPage: _visPage, darkMode: _darkMode, annotationCounts: _annCounts, onPageSelected: (pg) { setState(() => _visPage = pg); _scrollToPage(pg-1); })),
        _BottomBar(
          current: _currentTab, currentTool: _tool, isSaving: _isSaving, darkMode: _darkMode, showThumbs: _showThumbs, inkColor: _inkColor,
          onTabChange: _switchTab, onToolChange: _onToolChanged, onColorChange: (c) => setState(() => _inkColor = c),
          onUndo: _undo, onSave: _save, onShare: _share, onPrint: _print,
          onSearch: () => setState(() => _showSearch = !_showSearch),
          onDark: () => setState(() => _darkMode = !_darkMode),
          onThumbs: () => setState(() => _showThumbs = !_showThumbs),
          onProfile: () => SignerProfileDialog.show(context).then((_) => _loadProfile()),
          onSlots: () => SignatureSlotsPanel.show(context: context, slots: _slots, activeSlotId: _activeSlotId, onChanged: (s, a) => setState(() { _slots = s; _activeSlotId = a; })),
          onClauses: () => ClausePanel.show(context: context, bookmarks: _clauses, onNavigate: _scrollToPage, onDelete: (id) => setState(() { for (final l in _clauses.values) l.removeWhere((b) => b.id == id); })),
          onSummary: () => AnnotationSummaryPanel.show(context: context, rects: _rects, ink: _ink, notes: _notes, sigs: _sigs, stamps: _stamps, redactions: _redacts, bookmarks: _clauses, onNavigate: (pg) { setState(() => _visPage = pg+1); _scrollToPage(pg); }),
          onCompare: () => DocumentCompareScreen.show(context, widget.filePath),
          onAudit: () => AuditTrailSheet.show(context: context, documentName: p.basename(widget.filePath), events: [AuditEvent.created(p.basename(widget.filePath)), ...(_sigs.values.expand((l) => l).map((s) => s.isInitials ? AuditEvent.initialled(s.signerName ?? 'Unknown', s.pageIndex+1) : AuditEvent.signed(s.signerName ?? 'Unknown', s.pageIndex+1)))]),
          onTools: _openTools,
        ),
      ]),
    );
  }

  Widget _errorView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline_rounded, color: DS.red, size: 44), const SizedBox(height: 10), Text('Cannot open file', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 6), Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Text(_docError!, style: DS.caption(), textAlign: TextAlign.center)), const SizedBox(height: 16), FilledButton.icon(onPressed: () => _openDoc(), icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Retry'), style: FilledButton.styleFrom(backgroundColor: DS.indigo))]));

  Widget _pageList() {
    return ListView.builder(
      controller: _scroll,
      physics: _isIOS 
          ? const BouncingScrollPhysics()  // ✅ iOS native feel
          : (_annotating ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics()),
      padding: EdgeInsets.symmetric(vertical: _isIOS ? 12 : 24),  // ✅ Tighter on iOS
      itemCount: _pageCount,
      itemBuilder: (_, i) {
        final sw = MediaQuery.of(context).size.width;
        final isWide = kIsWeb && sw > 700;
        final isMobile = sw < 500;  // ✅ Works on both web and mobile
        final maxW = isMobile ? sw : (isWide ? 900.0 : sw - 4);
        final sideW = (isWide && _showThumbs) ? 88.0 : 0;
        final availW = maxW - sideW;
        
        return Center(child: Container(
          width: availW,
          margin: EdgeInsets.only(bottom: _isIOS ? 8 : 16),  // ✅ Less gap on iOS
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_isIOS ? 0 : 4),  // ✅ Full-width on iOS
            boxShadow: _isIOS ? null : [  // ✅ No shadow on iOS (saves GPU)
              BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_isIOS ? 0 : 4),
            child: _readMode || _annotating
                ? _buildPageWidget(i, availW)
                : InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: _buildPageWidget(i, availW),
                  ),
          ),
        ));
      },
    );
  }

  Widget _buildPageWidget(int pageIndex, double width) {
    return PdfPageWidget(
      key: ValueKey('pg_$pageIndex'), document: _doc!, pageIndex: pageIndex, displayWidth: width, darkMode: _darkMode,
      rects: _rects[pageIndex] ?? [], ink: _ink[pageIndex], notes: _notes[pageIndex] ?? [], signatures: _sigs[pageIndex] ?? [],
      textStamps: _stamps[pageIndex] ?? [], redactions: _redacts[pageIndex] ?? [], clauseBookmarks: _clauses[pageIndex] ?? [], textEdits: _textEdits[pageIndex] ?? [],
      tool: _tool, annotationColor: _inkColor, inkStrokeWidth: 0.006,
      pendingSignature: (_tool == AnnotationTool.signature || _tool == AnnotationTool.initials) ? _pendingSig : null, isInitialMode: _initialsMode,
      onRectAdded: _addRect, onInkStrokeAdded: (s) => _addInk(pageIndex, s), onNoteAdded: _addNote, onNoteToggled: _toggleNote,
      onSignaturePlaced: _placeSig, onSignatureMoved: _moveSig, onSignatureResized: _resizeSig, onSignatureDeleted: _deleteSig,
      onTextStampAdded: _addStamp, onRedactionAdded: _addRedact, onBookmarkAdded: _addBookmark, onTextEditAdded: _addTextEdit);
  }
}

enum _TabMode { edit, annotate, fillSign, all }

class _SidebarThumbs extends StatefulWidget {
  final PdfDocument doc; final int pageCount, currentPage; final bool darkMode; final Map<int, int> annotationCounts; final ValueChanged<int> onPageSelected;
  const _SidebarThumbs({required this.doc, required this.pageCount, required this.currentPage, required this.darkMode, required this.annotationCounts, required this.onPageSelected});
  @override State<_SidebarThumbs> createState() => _SidebarThumbsState();
}
class _SidebarThumbsState extends State<_SidebarThumbs> {
  @override Widget build(BuildContext context) => ThumbnailStrip(document: widget.doc, pageCount: widget.pageCount, currentPage: widget.currentPage, darkMode: widget.darkMode, annotationCounts: widget.annotationCounts, onPageSelected: widget.onPageSelected);
}

class _BottomBar extends StatelessWidget {
  final _TabMode current; final AnnotationTool currentTool; final bool isSaving, darkMode, showThumbs; final Color inkColor;
  final ValueChanged<_TabMode> onTabChange; final ValueChanged<AnnotationTool> onToolChange; final ValueChanged<Color> onColorChange;
  final VoidCallback onUndo, onSave, onShare, onPrint, onSearch, onDark, onThumbs, onProfile, onSlots, onClauses, onSummary, onCompare, onAudit, onTools;
  const _BottomBar({required this.current, required this.currentTool, required this.isSaving, required this.darkMode, required this.showThumbs, required this.inkColor, required this.onTabChange, required this.onToolChange, required this.onColorChange, required this.onUndo, required this.onSave, required this.onShare, required this.onPrint, required this.onSearch, required this.onDark, required this.onThumbs, required this.onProfile, required this.onSlots, required this.onClauses, required this.onSummary, required this.onCompare, required this.onAudit, required this.onTools});

  @override Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: DS.bgCard, border: Border(top: BorderSide(color: DS.separator, width: 0.5))),
    child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Wrap(alignment: WrapAlignment.start, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, runSpacing: 2, children: _toolsForTab())),
      Container(decoration: const BoxDecoration(border: Border(top: BorderSide(color: DS.separator, width: 0.3))), child: Row(children: [_tab(_TabMode.edit, 'Edit', Icons.edit_rounded), _tab(_TabMode.annotate, 'Annotate', Icons.rate_review_rounded), _tab(_TabMode.fillSign, 'Fill & Sign', Icons.draw_rounded), _tab(_TabMode.all, 'All', Icons.apps_rounded)])),
    ])));

  List<Widget> _toolsForTab() {
    switch (current) {
      case _TabMode.edit: return [_tb(Icons.text_fields_rounded, 'Text', AnnotationTool.textStamp, DS.indigo), _tb(Icons.sticky_note_2_rounded, 'Note', AnnotationTool.stickyNote, DS.orange), _ab(Icons.undo_rounded, 'Undo', onUndo)];
      case _TabMode.annotate: return [_tb(Icons.highlight_rounded, 'Highlight', AnnotationTool.highlight, const Color(0xFFFFD600)), _tb(Icons.format_underline_rounded, 'Underline', AnnotationTool.underline, const Color(0xFF38BDF8)), _tb(Icons.strikethrough_s_rounded, 'Strike', AnnotationTool.strikethrough, const Color(0xFFF87171)), _tb(Icons.brush_rounded, 'Draw', AnnotationTool.ink, inkColor), if (currentTool == AnnotationTool.ink) _colorPalette(), _tb(Icons.sticky_note_2_rounded, 'Note', AnnotationTool.stickyNote, const Color(0xFFFB923C)), _tb(Icons.hide_source_rounded, 'Redact', AnnotationTool.redaction, DS.red), _tb(Icons.bookmark_add_rounded, 'Clause', AnnotationTool.clauseBookmark, DS.green), _ab(Icons.undo_rounded, 'Undo', onUndo), _ab(Icons.build_rounded, 'Tools', onTools, color: DS.cyan)];
      case _TabMode.fillSign: return [_tb(Icons.draw_rounded, 'Sign', AnnotationTool.signature, DS.purple), _tb(Icons.fingerprint_rounded, 'Initials', AnnotationTool.initials, const Color(0xFFA78BFA)), _tb(Icons.text_fields_rounded, 'Text', AnnotationTool.textStamp, DS.indigo), _ab(Icons.people_rounded, 'Slots', onSlots), _ab(Icons.verified_rounded, 'Audit', onAudit), _ab(Icons.person_rounded, 'Profile', onProfile), isSaving ? const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo))) : _ab(Icons.save_rounded, kIsWeb ? 'Download' : 'Save', onSave, color: DS.indigo), _ab(kIsWeb ? Icons.download_rounded : Icons.ios_share_rounded, kIsWeb ? 'Export' : 'Share', onShare, color: DS.indigo)];
      case _TabMode.all: return [_tb(Icons.highlight_rounded, 'Highlight', AnnotationTool.highlight, const Color(0xFFFFD600)), _tb(Icons.brush_rounded, 'Draw', AnnotationTool.ink, inkColor), _tb(Icons.draw_rounded, 'Sign', AnnotationTool.signature, DS.purple), _tb(Icons.text_fields_rounded, 'Text', AnnotationTool.textStamp, DS.indigo), _tb(Icons.hide_source_rounded, 'Redact', AnnotationTool.redaction, DS.red), _ab(darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded, 'Dark', onDark, color: darkMode ? Colors.amber : Colors.white38), _ab(showThumbs ? Icons.grid_on_rounded : Icons.grid_off_rounded, 'Pages', onThumbs, color: showThumbs ? DS.indigo : Colors.white38), _ab(Icons.compare_rounded, 'Compare', onCompare), _ab(Icons.print_rounded, 'Print', onPrint), _ab(Icons.search_rounded, 'Search', onSearch), _ab(Icons.undo_rounded, 'Undo', onUndo)];
    }
  }

  Widget _colorPalette() {
    const colors = [Colors.black, Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple, Color(0xFF6366F1), Colors.white];
    return Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 1, height: 24, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 4)), ...colors.map((c) => GestureDetector(onTap: () => onColorChange(c), child: Container(width: 22, height: 22, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: inkColor == c ? Colors.white : c == Colors.white ? Colors.grey : Colors.transparent, width: 2.5), boxShadow: inkColor == c ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 6)] : null)))), Container(width: 1, height: 24, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 4))]);
  }

  Widget _tab(_TabMode mode, String label, IconData icon) { final active = current == mode; return Expanded(child: GestureDetector(onTap: () => onTabChange(mode), behavior: HitTestBehavior.opaque, child: Container(padding: const EdgeInsets.symmetric(vertical: 7), decoration: BoxDecoration(border: Border(top: BorderSide(color: active ? DS.indigo : Colors.transparent, width: 2.5))), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18, color: active ? DS.indigo : DS.textSecondary), const SizedBox(height: 1), Text(label, style: TextStyle(color: active ? DS.indigo : DS.textSecondary, fontSize: 9, fontWeight: active ? FontWeight.w700 : FontWeight.w500))])))); }
  Widget _tb(IconData icon, String label, AnnotationTool tool, Color tint) { final active = currentTool == tool; return Tooltip(message: label, child: GestureDetector(onTap: () => onToolChange(tool), child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: active ? tint.withOpacity(0.18) : Colors.transparent, borderRadius: BorderRadius.circular(10), border: active ? Border.all(color: tint.withOpacity(0.5)) : null), child: Icon(icon, size: 22, color: active ? tint : Colors.white54)))); }
  Widget _ab(IconData icon, String tip, VoidCallback t, {Color color = Colors.white54}) => Tooltip(message: tip, child: GestureDetector(onTap: t, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Icon(icon, size: 22, color: color))));
}