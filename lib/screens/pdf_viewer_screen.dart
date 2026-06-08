import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
import '../widgets/signature_dialog.dart';
import '../widgets/signer_profile_dialog.dart';
import '../widgets/thumbnail_strip.dart';
import '../widgets/apple_dialog.dart';
import 'document_compare_screen.dart';
import 'pdf_tools_screen.dart';
import '../utils/app_localizations.dart'; // for AppLocalizations

class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final Uint8List? preloadedBytes;
  const PdfViewerScreen({super.key, required this.filePath, this.preloadedBytes});

  static Future<void> navigate(BuildContext context, String path, {Uint8List? bytes}) {
    return Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, __, ___) => PdfViewerScreen(filePath: path, preloadedBytes: bytes),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

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
  bool _showThumbs = true;
  bool _isSaving = false;
  bool _readMode = true;
  bool _isSaved = true;

  DateTime? _lastMutation;
  final _uuid = const Uuid();

  final TransformationController _transformationController = TransformationController();

  bool get _annotating => _tool != AnnotationTool.view || _pendingSig != null;
  bool get _isIOS => Theme.of(context).platform == TargetPlatform.iOS;

  Uint8List? _currentSourceBytes;

  Future<String> _getDeviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'device_fingerprint';
    final existing = prefs.getString(key);
    if (existing != null) return existing;
    final newFp = const Uuid().v4();
    await prefs.setString(key, newFp);
    return newFp;
  }

  @override
  void initState() {
    super.initState();
    _currentSourceBytes = widget.preloadedBytes ?? PlatformFileService.getCached(widget.filePath);
    _openDoc();
    _loadProfile();
    _scroll.addListener(_trackPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MediaQuery.of(context).size.width < 600 && _showThumbs) {
        setState(() => _showThumbs = false);
      }
    });
  }

  @override
  void dispose() {
    _autosaveNow();
    _scroll.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _openDoc({String? password}) async {
    if (mounted) setState(() { _docLoading = true; _docError = null; });
    try {
      final doc = await PdfLoader.openForViewing(path: widget.filePath, bytes: _currentSourceBytes, password: password);
      if (mounted) setState(() { _doc = doc; _pageCount = doc.pages.length; _docLoading = false; });
      await _loadSidecar();
      _detectExpiry();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password') || msg.contains('encrypted') || msg.contains('unknown')) {
        if (mounted) { setState(() => _docLoading = false); _showPasswordDialog(); }
      } else {
        if (mounted) setState(() { _docLoading = false; _docError = e.toString(); });
      }
    }
  }

  Future<void> _showPasswordDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    final pwd = await AppleDialog.show<String>(
      context: context,
      title: l10n.passwordProtected,
      child: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: true,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: l10n.enterPassword,
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: DS.bgCard2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: DS.indigo),
          ),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context)),
        AppleDialogAction(label: l10n.open, onPressed: () => Navigator.pop(context, ctrl.text)),
      ],
    );
    if (pwd != null && pwd.isNotEmpty) {
      _password = pwd;
      _openDoc(password: pwd);
    }
  }

  void _trackPage() {
    if (!_scroll.hasClients || !mounted) return;
    final sw = MediaQuery.of(context).size.width;
    final ph = _getPageHeight(sw);
    final pg = (_scroll.offset / ph).floor() + 1;
    if (pg != _visPage && pg >= 1 && pg <= _pageCount) setState(() => _visPage = pg);
  }

  double _getPageHeight(double screenWidth) {
    final isMobile = screenWidth < 600;
    final sideW = (kIsWeb && screenWidth > 700 && _showThumbs) ? 88.0 : 0;
    final usableWidth = screenWidth - sideW;
    double widthFactor;
    if (isMobile) widthFactor = 0.98;
    else if (screenWidth < 1024) widthFactor = 0.92;
    else widthFactor = 0.82;
    double pageWidth = (usableWidth * widthFactor).clamp(280.0, 1200.0);
    return pageWidth * 1.414 + 12;
  }

  void _toggleReadMode() {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _readMode = !_readMode);
    _snack(_readMode ? l10n.readModeScroll : l10n.zoomModePinch);
  }

  void _zoom(double factor) {
    final matrix = _transformationController.value;
    final center = Offset(
      MediaQuery.of(context).size.width / 2,
      MediaQuery.of(context).size.height / 2,
    );
    final newMatrix = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..scale(factor)
      ..translate(-center.dx, -center.dy)
      ..multiply(matrix);
    _transformationController.value = newMatrix;
  }

  void _zoomIn() => _zoom(1.2);
  void _zoomOut() => _zoom(1 / 1.2);
  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _zoomToHighlight(Rect normRect) {
    if (_readMode || _annotating) return;
    final screenSize = MediaQuery.of(context).size;
    final page = _doc!.pages[_visPage - 1];
    final targetRect = Rect.fromLTWH(
      normRect.left * page.width,
      normRect.top * page.height,
      normRect.width * page.width,
      normRect.height * page.height,
    );

    double scaleX = screenSize.width * 0.6 / targetRect.width;
    double scaleY = screenSize.height * 0.6 / targetRect.height;
    double scale = scaleX < scaleY ? scaleX : scaleY;
    scale = scale.clamp(1.5, 6.0);

    final targetCenter = Offset(targetRect.center.dx, targetRect.center.dy);
    final screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);

    final newMatrix = Matrix4.identity()
      ..translate(screenCenter.dx, screenCenter.dy)
      ..scale(scale)
      ..translate(-targetCenter.dx, -targetCenter.dy)
      ..multiply(_transformationController.value);

    _transformationController.value = newMatrix;
  }

  Future<void> _loadSidecar() async {
    final snap = await AnnotationPersistenceService.load(widget.filePath);
    if (snap == null || snap.isEmpty || !mounted) return;
    setState(() {
      _rects..clear()..addAll(snap.rects);
      _notes..clear()..addAll(snap.notes);
      _stamps..clear()..addAll(snap.stamps);
      _redacts..clear()..addAll(snap.redactions);
      _clauses..clear()..addAll(snap.bookmarks);
      _textEdits..clear()..addAll(snap.textEdits);
      snap.ink.forEach((k, v) { if (v != null) _ink[k] = v as InkAnnotation; });
    });
  }

  Future<void> _loadProfile() async {
    final pr = await SignerProfileService.loadProfile();
    if (mounted) setState(() => _profile = pr);
  }

  Future<void> _detectExpiry() async {
    try {
      final bytes = _currentSourceBytes ?? await PlatformFileService.readBytes(widget.filePath) ?? Uint8List(0);
      if (bytes.isEmpty) return;
      final raw = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127).take(60000));
      final found = ExpiryDetector.detect(raw, 0);
      if (found.isNotEmpty && mounted) setState(() {
        _expiries = found;
        _showExpiryBanner = true;
      });
    } catch (_) {}
  }

  void _markMutated() {
    _lastMutation = DateTime.now();
    setState(() => _isSaved = false);
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
      if (mounted) setState(() => _isSaved = true);
    } catch (_) {}
  }

  void _switchTab(_TabMode tab) {
    setState(() {
      _currentTab = tab;
      _tool = tab == _TabMode.edit ? AnnotationTool.textStamp : AnnotationTool.view;
    });
  }

  void _onToolChanged(AnnotationTool t) {
    if (t == AnnotationTool.signature || t == AnnotationTool.initials) {
      _launchSigDialog(isInitials: t == AnnotationTool.initials);
      return;
    }
    setState(() {
      if (_tool == t) {
        _tool = AnnotationTool.view;
      } else {
        _tool = t;
      }
      _pendingSig = null;
      _initialsMode = false;
    });
  }

  Future<void> _launchSigDialog({bool isInitials = false}) async {
    final bytes = await SignatureDialog.show(context);
    if (bytes == null || !mounted) return;
    setState(() {
      _pendingSig = bytes;
      _initialsMode = isInitials;
      _tool = isInitials ? AnnotationTool.initials : AnnotationTool.signature;
    });
  }

  void _addRect(RectAnnotation a) => _mutate(() {
    _rects.putIfAbsent(a.pageIndex, () => []).add(a);
    _undoStack.add(() => setState(() => _rects[a.pageIndex]?.removeWhere((r) => r.id == a.id)));
  });

  void _addInk(int pg, InkStroke s) => _mutate(() {
    final ex = _ink[pg];
    _ink[pg] = ex == null ? InkAnnotation(id: _uuid.v4(), pageIndex: pg, strokes: [s]) : ex.addStroke(s);
    _undoStack.add(() => setState(() {
      final c = _ink[pg];
      if (c == null) return;
      if (c.strokes.length == 1) { _ink.remove(pg); return; }
      _ink[pg] = InkAnnotation(id: c.id, pageIndex: pg, strokes: c.strokes.sublist(0, c.strokes.length - 1));
    }));
  });

  void _addNote(StickyNote n) => _mutate(() {
    _notes.putIfAbsent(n.pageIndex, () => []).add(n);
    _undoStack.add(() => setState(() => _notes[n.pageIndex]?.removeWhere((x) => x.id == n.id)));
  });

  void _toggleNote(String id, bool e) => setState(() {
    for (final l in _notes.values) {
      for (final n in l) {
        if (n.id == id) n.isExpanded = e;
      }
    }
  });

  void _placeSig(SignatureOverlay sig) async {
    final fp = await _getDeviceFingerprint();
    final m = SignatureOverlay(
      id: sig.id,
      imageBytes: sig.imageBytes,
      pageIndex: sig.pageIndex,
      normPosition: sig.normPosition,
      normSize: sig.normSize,
      isInitials: sig.isInitials,
      slotId: _activeSlotId,
      signerName: _profile?.fullName,
    );
    _mutate(() {
      _sigs.putIfAbsent(m.pageIndex, () => []).add(m);
      _pendingSig = null;
      _initialsMode = false;
      _tool = AnnotationTool.view;
      _undoStack.add(() => setState(() => _sigs[m.pageIndex]?.removeWhere((s) => s.id == m.id)));
    });
    _signatureIps[m.id] = fp;
  }

  void _moveSig(String id, Offset pos) => setState(() {
    for (final l in _sigs.values) {
      for (final s in l) {
        if (s.id == id) s.normPosition = pos;
      }
    }
    _markMutated();
  });

  void _resizeSig(String id, Size sz) => setState(() {
    for (final l in _sigs.values) {
      for (final s in l) {
        if (s.id == id) s.normSize = sz;
      }
    }
    _markMutated();
  });

  void _deleteSig(String id) => setState(() {
    for (final l in _sigs.values) l.removeWhere((s) => s.id == id);
    _signatureIps.remove(id);
    _markMutated();
  });

  void _addStamp(TextStamp s) => _mutate(() {
    _stamps.putIfAbsent(s.pageIndex, () => []).add(s);
    _undoStack.add(() => setState(() => _stamps[s.pageIndex]?.removeWhere((x) => x.id == s.id)));
  });

  void _addRedact(RedactionRect r) => _mutate(() {
    _redacts.putIfAbsent(r.pageIndex, () => []).add(r);
    _undoStack.add(() => setState(() => _redacts[r.pageIndex]?.removeWhere((x) => x.id == r.id)));
  });

  void _addBookmark(ClauseBookmark b) => _mutate(() {
    _clauses.putIfAbsent(b.pageIndex, () => []).add(b);
    _undoStack.add(() => setState(() => _clauses[b.pageIndex]?.removeWhere((x) => x.id == b.id)));
  });

  void _addTextEdit(TextEditAnnotation t) => _mutate(() {
    _textEdits.putIfAbsent(t.pageIndex, () => []).add(t);
    _undoStack.add(() => setState(() => _textEdits[t.pageIndex]?.removeWhere((x) => x.id == t.id)));
  });

  void _mutate(VoidCallback fn) {
    setState(fn);
    _markMutated();
  }

  Map<int, int> get _annCounts {
    final m = <int, int>{};
    for (int i = 0; i < _pageCount; i++) {
      final c = (_rects[i]?.length ?? 0) +
          (_notes[i]?.length ?? 0) +
          (_sigs[i]?.length ?? 0) +
          (_stamps[i]?.length ?? 0) +
          (_redacts[i]?.length ?? 0) +
          (_clauses[i]?.length ?? 0) +
          (_textEdits[i]?.length ?? 0) +
          (_ink[i] != null ? 1 : 0);
      if (c > 0) m[i] = c;
    }
    return m;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _undoStack.removeLast()();
    _markMutated();
  }

  Future<String?> _buildPdf() => PdfSaveService.save(
    sourcePath: widget.filePath,
    pageCount: _pageCount,
    rectAnnotations: _rects,
    inkAnnotations: _ink,
    stickyNotes: _notes,
    signatures: _sigs,
    textStamps: _stamps,
    redactions: _redacts,
    bookmarks: _clauses,
    textEdits: _textEdits,
    slots: _slots,
    signerProfile: _profile,
    signatureIps: _signatureIps,
    sourceBytes: _currentSourceBytes,
  );

  Future<void> _openTools() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => PdfToolsScreen(
          filePath: widget.filePath,
          fileBytes: _currentSourceBytes,
          document: _doc,
        ),
      ),
    );

    if (result != null && mounted) {
      final String newPath = result['path'] as String;
      final Uint8List? newBytes = result['bytes'] as Uint8List?;
      await _reloadWithNewFile(newPath, newBytes);
    }
  }

  Future<void> _reloadWithNewFile(String path, Uint8List? bytes) async {
    setState(() {
      _docLoading = true;
      _doc?.dispose();
      _doc = null;
      _pageCount = 0;
      _currentSourceBytes = bytes;
      _rects.clear();
      _ink.clear();
      _notes.clear();
      _sigs.clear();
      _stamps.clear();
      _redacts.clear();
      _clauses.clear();
      _textEdits.clear();
      _undoStack.clear();
    });

    try {
      final doc = await PdfLoader.openForViewing(path: path, bytes: bytes);
      if (mounted) setState(() {
        _doc = doc;
        _pageCount = doc.pages.length;
        _docLoading = false;
        _visPage = 1;
      });
    } catch (e) {
      if (mounted) {
        _snack('Failed to reload: $e', err: true);
        setState(() => _docLoading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving || _docLoading || _doc == null) return;
    final l10n = AppLocalizations.of(context)!;

    final defaultName = p.basenameWithoutExtension(widget.filePath);
    final desiredName = await _askFileName(defaultName: defaultName);
    if (desiredName == null || desiredName.isEmpty) return;

    final safeName = desiredName.endsWith('.pdf') ? desiredName : '$desiredName.pdf';

    String? customDir;
    if (!kIsWeb) {
      customDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.chooseSaveLocation,
      );
    }

    setState(() => _isSaving = true);
    try {
      Uint8List? bytes;

      if (_currentSourceBytes != null) {
        bytes = _currentSourceBytes;
      } else {
        final sourcePath = await _buildPdf();
        if (sourcePath != null) {
          bytes = PlatformFileService.getCached(sourcePath) ??
              (!kIsWeb ? await File(sourcePath).readAsBytes() : null);
        }
      }

      if (bytes == null) throw Exception('Could not read PDF bytes');

      if (customDir != null && !kIsWeb) {
        final dest = File('$customDir/$safeName');
        await dest.writeAsBytes(bytes);
        _snack('${l10n.savedTo} ${dest.path}', duration: 4);
      } else if (kIsWeb) {
        downloadFile(safeName, bytes);
        _snack('$l10n.downloaded $safeName');
      } else {
        final defaultDir = await getApplicationDocumentsDirectory();
        final dest = File('${defaultDir.path}/$safeName');
        await dest.writeAsBytes(bytes);
        _snack(l10n.savedAs + ' $safeName');
      }

      if (mounted) _showPostActionDialog();
    } catch (e) {
      if (mounted) _snack('${l10n.saveFailed}: $e', err: true, duration: 5);
      debugPrint('Save error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _share() async {
    if (_isSaving || _docLoading || _doc == null) return;
    final l10n = AppLocalizations.of(context)!;

    final defaultName = p.basenameWithoutExtension(widget.filePath);
    final desiredName = await _askFileName(defaultName: defaultName);
    if (desiredName == null || desiredName.isEmpty) return;

    final safeName = desiredName.endsWith('.pdf') ? desiredName : '$desiredName.pdf';

    setState(() => _isSaving = true);
    try {
      final sourcePath = await _buildPdf();
      if (sourcePath == null) throw Exception('Build failed');

      final sourceBytes = PlatformFileService.getCached(sourcePath) ??
          (!kIsWeb ? await File(sourcePath).readAsBytes() : null);

      if (sourceBytes == null) throw Exception('No bytes');

      if (kIsWeb) {
        downloadFile(safeName, sourceBytes);
        if (mounted) _showPostActionDialog();
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$safeName');
        await tempFile.writeAsBytes(sourceBytes);
        await Share.shareXFiles(
          [XFile(tempFile.path, mimeType: 'application/pdf')],
          subject: safeName,
        );
        if (mounted) _showPostActionDialog();
      }
    } catch (e) {
      if (mounted) _snack('${l10n.shareFailed}: $e', err: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _print() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final path = await _buildPdf();
      if (path == null) return;
      final bytes = await PlatformFileService.readBytes(path) ?? Uint8List(0);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) _snack('${l10n.printError}: $e', err: true);
    }
  }

  void _scrollToPage(int idx) {
    if (!_scroll.hasClients) return;
    final sw = MediaQuery.of(context).size.width;
    final ph = _getPageHeight(sw);
    final target = (idx * ph).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic);
  }

  void _snack(String msg, {bool err = false, int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: err ? DS.red : DS.bgCard2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: Duration(seconds: duration),
    ));
  }

  void _showPostActionDialog([String? message]) {
    final l10n = AppLocalizations.of(context)!;
    AppleDialog.show(
      context: context,
      title: l10n.done,
      content: message ?? l10n.openAnotherDocument,
      actions: [
        AppleDialogAction(label: l10n.no, onPressed: () => Navigator.pop(context)),
        AppleDialogAction(
          label: l10n.yes,
          onPressed: () {
            Navigator.pop(context);
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ],
    );
  }

  Future<String?> _askFileName({String? defaultName}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: defaultName ?? 'document');
    return AppleDialog.show<String>(
      context: context,
      title: l10n.saveAs,
      child: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: l10n.enterFileName,
          filled: true,
          fillColor: DS.bgCard2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        AppleDialogAction(label: l10n.cancel, onPressed: () => Navigator.pop(context)),
        AppleDialogAction(label: l10n.save, onPressed: () => Navigator.pop(context, controller.text.trim())),
      ],
    );
  }

  double _getPageAspect() {
    if (_doc == null) return 1.414;
    final page = _doc!.pages[_visPage - 1];
    return page.width / page.height;
  }

  Widget _pageList() {
    if (_docLoading) {
      return Shimmer(
        child: ListView.builder(
          itemCount: 3,
          itemBuilder: (_, i) => Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isMobile = screenWidth < 600;
        final isTablet = screenWidth >= 600 && screenWidth < 1024;
        final sideW = (kIsWeb && screenWidth > 700 && _showThumbs) ? 88.0 : 0;
        final usableWidth = screenWidth - sideW;

        double widthFactor;
        if (isMobile) widthFactor = 0.98;
        else if (isTablet) widthFactor = 0.92;
        else widthFactor = 0.82;

        double availW = (usableWidth * widthFactor).clamp(280.0, 1200.0);
        final aspect = _getPageAspect();
        final pageHeight = availW / aspect;

        return ListView.builder(
          controller: _scroll,
          addAutomaticKeepAlives: false,
          cacheExtent: MediaQuery.of(context).size.height * 2,
          physics: _isIOS
              ? const BouncingScrollPhysics()
              : (_annotating ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics()),
          padding: EdgeInsets.symmetric(vertical: isMobile ? 4 : 12),
          itemCount: _pageCount,
          itemBuilder: (_, i) {
            return RepaintBoundary(
              child: Center(
                child: Container(
                  width: availW,
                  height: pageHeight,
                  margin: EdgeInsets.only(bottom: isMobile ? 8 : 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(isMobile ? 4 : 8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isMobile ? 0.04 : 0.08),
                        blurRadius: isMobile ? 4 : 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isMobile ? 4 : 8),
                    child: _readMode || _annotating
                        ? _buildPageWidget(i, availW)
                        : InteractiveViewer(
                            transformationController: _transformationController,
                            minScale: 0.5,
                            maxScale: 5.0,
                            clipBehavior: Clip.none,
                            boundaryMargin: const EdgeInsets.all(20),
                            scaleEnabled: true,
                            panEnabled: true,
                            constrained: false,
                            child: SizedBox(
                              width: availW,
                              height: pageHeight,
                              child: _buildPageWidget(i, availW),
                            ),
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPageWidget(int pageIndex, double width) {
    return PdfPageWidget(
      key: ValueKey('pg_$pageIndex'),
      document: _doc!,
      pageIndex: pageIndex,
      displayWidth: width,
      darkMode: _darkMode,
      rects: _rects[pageIndex] ?? [],
      ink: _ink[pageIndex],
      notes: _notes[pageIndex] ?? [],
      signatures: _sigs[pageIndex] ?? [],
      textStamps: _stamps[pageIndex] ?? [],
      redactions: _redacts[pageIndex] ?? [],
      clauseBookmarks: _clauses[pageIndex] ?? [],
      textEdits: _textEdits[pageIndex] ?? [],
      tool: _tool,
      annotationColor: _inkColor,
      inkStrokeWidth: 0.006,
      pendingSignature: (_tool == AnnotationTool.signature || _tool == AnnotationTool.initials) ? _pendingSig : null,
      isInitialMode: _initialsMode,
      onRectAdded: _addRect,
      onInkStrokeAdded: (s) => _addInk(pageIndex, s),
      onNoteAdded: _addNote,
      onNoteToggled: _toggleNote,
      onSignaturePlaced: _placeSig,
      onSignatureMoved: _moveSig,
      onSignatureResized: _resizeSig,
      onSignatureDeleted: _deleteSig,
      onTextStampAdded: _addStamp,
      onRedactionAdded: _addRedact,
      onBookmarkAdded: _addBookmark,
      onTextEditAdded: _addTextEdit,
      onHighlightTapped: _zoomToHighlight,
    );
  }

  Widget _errorView() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: DS.red, size: 44),
        const SizedBox(height: 10),
        Text(l10n.cannotOpenFile, style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(_docError!, style: DS.caption(), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _openDoc(),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(l10n.retry),
          style: FilledButton.styleFrom(backgroundColor: DS.indigo),
        ),
      ]),
    );
  }

  PreferredSizeWidget _topBar() {
    final l10n = AppLocalizations.of(context)!;
    return PreferredSize(
      preferredSize: const Size.fromHeight(52),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: DS.bgCard.withOpacity(0.85),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(widget.filePath),
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        Text(
                          '${l10n.page}$_visPage / $_pageCount',
                          style: DS.caption().copyWith(fontSize: 10, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(_readMode ? Icons.menu_book_rounded : Icons.zoom_in_rounded, color: Colors.white54, size: 20),
                    tooltip: _readMode ? l10n.readMode : l10n.zoomMode,
                    onPressed: _toggleReadMode,
                  ),
                  if (_docLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.save_rounded, color: Colors.white24, size: 22),
                    )
                  else if (_isSaving)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo)),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.save_rounded, color: DS.indigo, size: 22),
                      tooltip: kIsWeb ? l10n.download : l10n.save,
                      onPressed: _save,
                    ),
                  IconButton(
                    icon: Icon(kIsWeb ? Icons.download_rounded : Icons.ios_share_rounded, color: DS.indigo, size: 20),
                    tooltip: kIsWeb ? l10n.export : l10n.share,
                    onPressed: _share,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _floatingZoomButtons() {
    final l10n = AppLocalizations.of(context)!;
    if (_readMode || _annotating) return const SizedBox();
    return Positioned(
      top: 70,
      right: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _zoomFabButton(Icons.zoom_in, l10n.zoomIn, _zoomIn),
          const SizedBox(height: 8),
          _zoomFabButton(Icons.zoom_out, l10n.zoomOut, _zoomOut),
          const SizedBox(height: 8),
          _zoomFabButton(Icons.aspect_ratio, l10n.resetZoom, _resetZoom),
        ],
      ),
    );
  }

  Widget _zoomFabButton(IconData icon, String label, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: DS.bgCard.withOpacity(0.85),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: DS.textPrimary, size: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DS.setStatusBar();
    final isWideWeb = kIsWeb && MediaQuery.of(context).size.width > 700;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: _darkMode ? Colors.black : const Color(0xFFF0F0F0),
      body: Stack(
        children: [
          Column(
            children: [
              _topBar(),
              if (_showExpiryBanner && _expiries.isNotEmpty)
                Container(
                  color: const Color(0xFFB45309).withOpacity(0.9),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(child: Text(ExpiryDetector.urgencyLabel(_expiries.first), style: const TextStyle(color: Colors.white, fontSize: 11))),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 12, color: Colors.white54),
                        onPressed: () => setState(() => _showExpiryBanner = false),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              if (_pendingSig != null)
                Container(
                  color: DS.indigo.withOpacity(0.15),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app_rounded, color: DS.indigo, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _initialsMode ? l10n.tapToPlaceInitials : l10n.tapToPlaceSignature,
                          style: TextStyle(color: DS.indigo, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() { _pendingSig = null; _tool = AnnotationTool.view; }),
                        child: Text(l10n.cancel, style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    if (isWideWeb && _showThumbs && _doc != null)
                      Container(
                        width: 88,
                        color: DS.bgCard,
                        child: _SidebarThumbs(
                          doc: _doc!,
                          pageCount: _pageCount,
                          currentPage: _visPage,
                          darkMode: _darkMode,
                          annotationCounts: _annCounts,
                          onPageSelected: (pg) {
                            setState(() => _visPage = pg);
                            _scrollToPage(pg - 1);
                          },
                        ),
                      ),
                    Expanded(
                      child: _docLoading
                          ? const Center(child: CircularProgressIndicator(color: DS.indigo))
                          : _docError != null
                              ? _errorView()
                              : _doc == null
                                  ? const SizedBox()
                                  : _pageList(),
                    ),
                  ],
                ),
              ),
              if (!isWideWeb && _showThumbs && _doc != null)
                SizedBox(
                  height: 80,
                  child: ThumbnailStrip(
                    document: _doc!,
                    pageCount: _pageCount,
                    currentPage: _visPage,
                    darkMode: _darkMode,
                    annotationCounts: _annCounts,
                    onPageSelected: (pg) {
                      setState(() => _visPage = pg);
                      _scrollToPage(pg - 1);
                    },
                  ),
                ),
              _BottomBar(
                current: _currentTab,
                currentTool: _tool,
                isSaving: _isSaving,
                docLoading: _docLoading,
                darkMode: _darkMode,
                showThumbs: _showThumbs,
                inkColor: _inkColor,
                onTabChange: _switchTab,
                onToolChange: _onToolChanged,
                onColorChange: (c) => setState(() => _inkColor = c),
                onUndo: _undo,
                onSave: _save,
                onShare: _share,
                onPrint: _print,
                onSearch: () {},
                onDark: () => setState(() => _darkMode = !_darkMode),
                onThumbs: () => setState(() => _showThumbs = !_showThumbs),
                onProfile: () => SignerProfileDialog.show(context).then((_) => _loadProfile()),
                onSlots: () => SignatureSlotsPanel.show(
                  context: context,
                  slots: _slots,
                  activeSlotId: _activeSlotId,
                  onChanged: (s, a) => setState(() { _slots = s; _activeSlotId = a; }),
                ),
                onClauses: () => ClausePanel.show(
                  context: context,
                  bookmarks: _clauses,
                  onNavigate: _scrollToPage,
                  onDelete: (id) => setState(() {
                    for (final l in _clauses.values) l.removeWhere((b) => b.id == id);
                  }),
                ),
                onSummary: () => AnnotationSummaryPanel.show(
                  context: context,
                  rects: _rects,
                  ink: _ink,
                  notes: _notes,
                  sigs: _sigs,
                  stamps: _stamps,
                  redactions: _redacts,
                  bookmarks: _clauses,
                  onNavigate: (pg) {
                    setState(() => _visPage = pg + 1);
                    _scrollToPage(pg);
                  },
                ),
                onCompare: () => DocumentCompareScreen.show(context, widget.filePath),
                onAudit: () => AuditTrailSheet.show(
                  context: context,
                  documentName: p.basename(widget.filePath),
                  events: [
                    AuditEvent.created(p.basename(widget.filePath)),
                    ...(_sigs.values.expand((l) => l).map((s) => s.isInitials
                        ? AuditEvent.initialled(s.signerName ?? 'Unknown', s.pageIndex + 1)
                        : AuditEvent.signed(s.signerName ?? 'Unknown', s.pageIndex + 1))),
                  ],
                ),
                onTools: _openTools,
              ),
            ],
          ),
          _floatingZoomButtons(),
        ],
      ),
    );
  }
}

// ============================================================================
// Bottom Bar
// ============================================================================
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
  final _TabMode current; final AnnotationTool currentTool; final bool isSaving, docLoading, darkMode, showThumbs; final Color inkColor;
  final ValueChanged<_TabMode> onTabChange; final ValueChanged<AnnotationTool> onToolChange; final ValueChanged<Color> onColorChange;
  final VoidCallback onUndo, onSave, onShare, onPrint, onDark, onThumbs, onProfile, onSlots, onClauses, onSummary, onCompare, onAudit, onTools;
  final VoidCallback onSearch;

  const _BottomBar({required this.current, required this.currentTool, required this.isSaving, required this.docLoading, required this.darkMode, required this.showThumbs, required this.inkColor, required this.onTabChange, required this.onToolChange, required this.onColorChange, required this.onUndo, required this.onSave, required this.onShare, required this.onPrint, required this.onSearch, required this.onDark, required this.onThumbs, required this.onProfile, required this.onSlots, required this.onClauses, required this.onSummary, required this.onCompare, required this.onAudit, required this.onTools});

  @override Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(color: DS.bgCard, border: Border(top: BorderSide(color: DS.separator, width: 0.5))),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Wrap(alignment: WrapAlignment.start, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, runSpacing: 2, children: _toolsForTab(l10n))),
        Container(decoration: const BoxDecoration(border: Border(top: BorderSide(color: DS.separator, width: 0.3))), child: Row(children: [
          _tab(l10n.tabEdit, Icons.edit_rounded, _TabMode.edit),
          _tab(l10n.tabAnnotate, Icons.rate_review_rounded, _TabMode.annotate),
          _tab(l10n.tabFillSign, Icons.draw_rounded, _TabMode.fillSign),
          _tab(l10n.tabAll, Icons.apps_rounded, _TabMode.all)
        ])),
      ])));
  }

  List<Widget> _toolsForTab(AppLocalizations l10n) {
    switch (current) {
      case _TabMode.edit: return [
        _tb(Icons.text_fields_rounded, l10n.text, AnnotationTool.textStamp, DS.indigo),
        _tb(Icons.sticky_note_2_rounded, l10n.note, AnnotationTool.stickyNote, DS.orange),
        _ab(Icons.undo_rounded, l10n.undo, onUndo)
      ];
      case _TabMode.annotate: return [
        _tb(Icons.highlight_rounded, l10n.highlight, AnnotationTool.highlight, const Color(0xFFFFD600)),
        _tb(Icons.format_underline_rounded, l10n.underline, AnnotationTool.underline, const Color(0xFF38BDF8)),
        _tb(Icons.strikethrough_s_rounded, l10n.strike, AnnotationTool.strikethrough, const Color(0xFFF87171)),
        _tb(Icons.brush_rounded, l10n.draw, AnnotationTool.ink, inkColor),
        if (currentTool == AnnotationTool.ink) _colorPalette(l10n),
        _tb(Icons.sticky_note_2_rounded, l10n.note, AnnotationTool.stickyNote, const Color(0xFFFB923C)),
        _tb(Icons.hide_source_rounded, l10n.redact, AnnotationTool.redaction, DS.red),
        _tb(Icons.bookmark_add_rounded, l10n.clause, AnnotationTool.clauseBookmark, DS.green),
        _ab(Icons.undo_rounded, l10n.undo, onUndo),
        _ab(Icons.build_rounded, l10n.tools, onTools, color: DS.cyan),
      ];
      case _TabMode.fillSign: return [
        _tb(Icons.draw_rounded, l10n.sign, AnnotationTool.signature, DS.purple),
        _tb(Icons.fingerprint_rounded, l10n.initials, AnnotationTool.initials, const Color(0xFFA78BFA)),
        _tb(Icons.text_fields_rounded, l10n.text, AnnotationTool.textStamp, DS.indigo),
        _ab(Icons.people_rounded, l10n.slots, onSlots),
        _ab(Icons.verified_rounded, l10n.audit, onAudit),
        _ab(Icons.person_rounded, l10n.profile, onProfile),
        if (docLoading)
          _ab(Icons.save_rounded, kIsWeb ? l10n.download : l10n.save, () {}, color: Colors.white24)
        else if (isSaving)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo)))
        else
          _ab(Icons.save_rounded, kIsWeb ? l10n.download : l10n.save, onSave, color: DS.indigo),
        _ab(kIsWeb ? Icons.download_rounded : Icons.ios_share_rounded, kIsWeb ? l10n.export : l10n.share, onShare, color: DS.indigo),
      ];
      case _TabMode.all: return [
        _tb(Icons.highlight_rounded, l10n.highlight, AnnotationTool.highlight, const Color(0xFFFFD600)),
        _tb(Icons.brush_rounded, l10n.draw, AnnotationTool.ink, inkColor),
        _tb(Icons.draw_rounded, l10n.sign, AnnotationTool.signature, DS.purple),
        _tb(Icons.text_fields_rounded, l10n.text, AnnotationTool.textStamp, DS.indigo),
        _tb(Icons.hide_source_rounded, l10n.redact, AnnotationTool.redaction, DS.red),
        _ab(darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded, l10n.darkMode, onDark, color: darkMode ? Colors.amber : Colors.white38),
        _ab(showThumbs ? Icons.grid_on_rounded : Icons.grid_off_rounded, l10n.thumbnails, onThumbs, color: showThumbs ? DS.indigo : Colors.white38),
        _ab(Icons.compare_rounded, l10n.compare, onCompare),
        _ab(Icons.print_rounded, l10n.print, onPrint),
        _ab(Icons.undo_rounded, l10n.undo, onUndo),
      ];
    }
  }

  Widget _colorPalette(AppLocalizations l10n) {
    const colors = [Colors.black, Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple, Color(0xFF6366F1), Colors.white];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 1, height: 24, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 4)),
      ...colors.map((c) => ScaleTap(
        onTap: () => onColorChange(c),
        child: Container(
          width: 22, height: 22, margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: inkColor == c ? Colors.white : c == Colors.white ? Colors.grey : Colors.transparent, width: 2.5),
          ),
        ),
      )),
      Container(width: 1, height: 24, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 4)),
    ]);
  }

  Widget _tab(String label, IconData icon, _TabMode mode) {
    final active = current == mode;
    return Expanded(child: ScaleTap(
      onTap: () => onTabChange(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: active ? DS.indigo : Colors.transparent, width: 2.5))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: active ? DS.indigo : DS.textSecondary),
          const SizedBox(height: 1),
          Text(label, style: TextStyle(color: active ? DS.indigo : DS.textSecondary, fontSize: 9, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    ));
  }

  Widget _tb(IconData icon, String label, AnnotationTool tool, Color tint) {
    final active = currentTool == tool;
    return Tooltip(
      message: label,
      child: ScaleTap(
        onTap: () => onToolChange(tool),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? tint.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: tint.withOpacity(0.5)) : null,
          ),
          child: Icon(icon, size: 22, color: active ? tint : Colors.white54),
        ),
      ),
    );
  }

  Widget _ab(IconData icon, String tip, VoidCallback t, {Color color = Colors.white54}) {
    return Tooltip(
      message: tip,
      child: ScaleTap(
        onTap: t,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}