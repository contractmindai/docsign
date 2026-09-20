import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
import '../utils/app_localizations.dart';
import '../services/text_rank_summarizer.dart';
import '../services/offline_ai.dart';

// ============================================================================
// Main viewer
// ============================================================================

class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final Uint8List? preloadedBytes;
  final AnnotationTool? initialTool;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    this.preloadedBytes,
    this.initialTool,
  });

  static Future<void> navigate(BuildContext context, String path,
      {Uint8List? bytes, AnnotationTool? initialTool}) {
    return Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, __, ___) => PdfViewerScreen(
          filePath: path, preloadedBytes: bytes, initialTool: initialTool),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
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

  final TransformationController _transformationController =
      TransformationController();

  bool get _annotating => _tool != AnnotationTool.view || _pendingSig != null;
  bool get _isIOS => Theme.of(context).platform == TargetPlatform.iOS;

  Uint8List? _currentSourceBytes;

  int _documentRevision = 0;

  int? _editingPageIndex;

  bool _isReloading = false;
  Uint8List? _pendingDocReload;

  final _summarizer = const TextRankSummarizer(maxSummarySentences: 4);
  Map<String, dynamic>? _analysisResult;
  bool _isAnalyzing = false;
  static const int _maxPagesForFullAnalysis = 10;
  static const int _maxPagesToAnalyze = 5;

  bool get _hasPendingEdits =>
      !_isSaved ||
      _rects.isNotEmpty ||
      _ink.isNotEmpty ||
      _notes.isNotEmpty ||
      _sigs.isNotEmpty ||
      _stamps.isNotEmpty ||
      _redacts.isNotEmpty ||
      _clauses.isNotEmpty ||
      _textEdits.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.initialTool != null) {
      _tool = widget.initialTool!;
      _currentTab = _tabForTool(_tool);
    }
    _bootstrap();
    _loadProfile();
    _scroll.addListener(_trackPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (MediaQuery.of(context).size.width < 600 && _showThumbs) {
        setState(() => _showThumbs = false);
      }
    });
  }

  _TabMode _tabForTool(AnnotationTool t) {
    switch (t) {
      case AnnotationTool.textEdit:
        return _TabMode.edit;
      case AnnotationTool.signature:
      case AnnotationTool.initials:
        return _TabMode.fillSign;
      case AnnotationTool.highlight:
      case AnnotationTool.underline:
      case AnnotationTool.strikethrough:
      case AnnotationTool.ink:
      case AnnotationTool.stickyNote:
      case AnnotationTool.redaction:
      case AnnotationTool.clauseBookmark:
        return _TabMode.annotate;
      case AnnotationTool.textStamp:
      case AnnotationTool.view:
        return _TabMode.annotate;
    }
  }

  Future<void> _bootstrap() async {
    await _ensureSourceBytes();
    await _openDoc();
  }

  Future<void> _ensureSourceBytes() async {
    if (_currentSourceBytes != null) return;

    if (widget.preloadedBytes != null) {
      _currentSourceBytes = widget.preloadedBytes;
      _documentRevision++;
      return;
    }

    final cached = PlatformFileService.getCached(widget.filePath);
    if (cached != null) {
      _currentSourceBytes = cached;
      _documentRevision++;
      return;
    }

    if (!kIsWeb) {
      final fromDisk = await PlatformFileService.readBytes(widget.filePath);
      if (fromDisk != null && mounted) {
        setState(() {
          _currentSourceBytes = fromDisk;
          _documentRevision++;
        });
      }
    }
  }

  @override
  void dispose() {
    _autosaveNow();
    _scroll.dispose();
    _transformationController.dispose();
    _doc?.dispose().catchError((_) {});
    super.dispose();
  }

  Future<void> _openDoc({String? password}) async {
    if (mounted) setState(() { _docLoading = true; _docError = null; });
    try {
      final doc = await PdfLoader.openForViewing(
        path: widget.filePath,
        bytes: _currentSourceBytes,
        password: password,
      );
      if (mounted) {
        setState(() {
          _doc = doc;
          _pageCount = doc.pages.length;
          _docLoading = false;
        });
      }
      await _loadSidecar();
      _detectExpiry();
      if (mounted) _loadCachedAnalysis();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password') ||
          msg.contains('encrypted') ||
          msg.contains('unknown')) {
        if (mounted) {
          setState(() => _docLoading = false);
          _showPasswordDialog();
        }
      } else {
        if (mounted) {
          setState(() {
            _docLoading = false;
            _docError = e.toString();
          });
        }
      }
    }
  }

  Future<void> _loadCachedAnalysis() async {
    final cachePath = '${widget.filePath}.analysis';
    try {
      final file = File(cachePath);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final timestamp = DateTime.parse(json['_cachedAt'] ?? '');
        if (DateTime.now().difference(timestamp).inDays < 7) {
          setState(() {
            _analysisResult = json;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _cacheAnalysis(Map<String, dynamic> result) async {
    final copy = Map<String, dynamic>.from(result)
      ..['_cachedAt'] = DateTime.now().toIso8601String();
    final file = File('${widget.filePath}.analysis');
    try {
      await file.writeAsString(jsonEncode(copy));
      setState(() {
        _analysisResult = copy;
      });
    } catch (_) {}
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
        AppleDialogAction(
            label: l10n.cancel, onPressed: () => Navigator.pop(context)),
        AppleDialogAction(
            label: l10n.open,
            onPressed: () => Navigator.pop(context, ctrl.text)),
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
    if (pg != _visPage && pg >= 1 && pg <= _pageCount) {
      setState(() => _visPage = pg);
    }
  }

  double _getPageHeight(double screenWidth, [double? screenHeight]) {
    final isMobile = screenWidth < 600;
    final sideW = (kIsWeb && screenWidth > 700 && _showThumbs) ? 88.0 : 0;
    final usableWidth = screenWidth - sideW;
    double widthFactor;
    if (isMobile) widthFactor = 0.98;
    else if (screenWidth < 1024) widthFactor = 0.92;
    else widthFactor = 0.82;
    double pageWidth = (usableWidth * widthFactor).clamp(280.0, 1200.0);
    final aspect = _getPageAspect();
    return pageWidth / aspect + 12;
  }

  double _getPageAspect() {
    if (_doc == null) return 1.414;
    final page = _doc!.pages[_visPage - 1];
    return page.width / page.height;
  }

  Future<void> _runAnalysisIfNeeded() async {
    if (_analysisResult != null || _isAnalyzing) return;
    if (_doc == null || _pageCount == 0) {
      _snack('No document loaded to analyze.', err: true);
      return;
    }

    final scope = await _showAnalysisScopeDialog();
    if (scope == null) return;

    final bool analyzeAll = scope;
    int pagesToAnalyze;
    if (analyzeAll) {
      pagesToAnalyze = _pageCount > _maxPagesToAnalyze
          ? _maxPagesToAnalyze
          : _pageCount;
      if (_pageCount > _maxPagesToAnalyze) {
        final proceed = await _showLargeDocumentWarning();
        if (!proceed) return;
      }
    } else {
      pagesToAnalyze = 1;
    }

    setState(() => _isAnalyzing = true);

    final progress = ValueNotifier<int>(1);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: DS.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Analyzing...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: DS.indigo),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: progress,
              builder: (_, v, __) => Text(
                'Page $v / $pagesToAnalyze',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );

    final buffer = StringBuffer();
    try {
      for (int i = 0; i < pagesToAnalyze; i++) {
        progress.value = i + 1;
        final page = _doc!.pages[i];
        final pageText = await page.loadText();
        if (pageText != null) {
          final text = pageText.fullText.trim();
          if (text.isNotEmpty) buffer.writeln(text);
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      progress.dispose();
      _snack('Text extraction error: $e', err: true);
      setState(() => _isAnalyzing = false);
      return;
    }

    if (mounted) Navigator.pop(context);
    progress.dispose();

    final fullText = buffer.toString().trim();
    if (fullText.isEmpty) {
      _snack('No text could be extracted from the analyzed pages.', err: true);
      setState(() => _isAnalyzing = false);
      return;
    }

    final category = OfflineAI.classifyDocument(fullText);
    final entities = OfflineAI.extractEntities(fullText);
    final summary = _summarizer.summarize(fullText);
    final tags = OfflineAI.autoTagDocument(fullText);

    final result = {
      'category': category,
      'entities': entities,
      'summary': summary,
      'tags': tags,
      'pagesAnalyzed': pagesToAnalyze,
      'totalPages': _pageCount,
    };

    await _cacheAnalysis(result);
    setState(() => _isAnalyzing = false);
    _showAnalysisResult();
  }

  void _showAnalysisResult() {
    if (_analysisResult == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DS.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PdfAnalysisSheet(analysis: _analysisResult!),
    );
  }

  Future<bool?> _showAnalysisScopeDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: DS.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Analyze Document'),
        content: Text(
          'This document has $_pageCount page(s).\n\nChoose what to analyze:',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Current Page',
                style: TextStyle(color: DS.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DS.indigo),
            child: const Text('All Pages'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showLargeDocumentWarning() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: DS.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Large Document'),
        content: Text(
          'This document has $_pageCount pages.\n'
          'For performance, we will analyze only the first $_maxPagesToAnalyze pages.\n\n'
          'Continue?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: DS.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DS.orange),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  bool get _showFab =>
      !_annotating && _currentTab != _TabMode.insights && !_docLoading;

  Widget _aiFloatingButton() {
    final hasAnalysis = _analysisResult != null;
    return Positioned(
      bottom: 110,
      right: 16,
      child: FloatingActionButton(
        heroTag: 'ai_summary',
        onPressed: _onFabPressed,
        backgroundColor: DS.indigo,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: const CircleBorder(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 28),
            if (hasAnalysis)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (_isAnalyzing)
              const Positioned(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onFabPressed() {
    if (_isAnalyzing) return;
    if (_analysisResult != null) {
      _showAnalysisResult();
    } else {
      _runAnalysisIfNeeded();
    }
  }

  void _switchTab(_TabMode tab) {
    setState(() {
      _currentTab = tab;
      _editingPageIndex = null;
      if (tab == _TabMode.insights) {
        _tool = AnnotationTool.view;
        if (_analysisResult == null && !_isAnalyzing) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _runAnalysisIfNeeded());
        }
      } else {
        _tool = AnnotationTool.view;
      }
    });
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
      _rects
        ..clear()
        ..addAll(snap.rects);
      _notes
        ..clear()
        ..addAll(snap.notes);
      _stamps
        ..clear()
        ..addAll(snap.stamps);
      _redacts
        ..clear()
        ..addAll(snap.redactions);
      _clauses
        ..clear()
        ..addAll(snap.bookmarks);
      _textEdits
        ..clear()
        ..addAll(snap.textEdits);
      snap.ink.forEach((k, v) {
        if (v != null) _ink[k] = v as InkAnnotation;
      });
    });
  }

  Future<void> _loadProfile() async {
    final pr = await SignerProfileService.loadProfile();
    if (mounted) setState(() => _profile = pr);
  }

  Future<void> _detectExpiry() async {
    try {
      final bytes = _currentSourceBytes ??
          await PlatformFileService.readBytes(widget.filePath) ??
          Uint8List(0);
      if (bytes.isEmpty) return;
      final raw = String.fromCharCodes(
          bytes.where((b) => b >= 32 && b < 127).take(60000));
      final found = ExpiryDetector.detect(raw, 0);
      if (found.isNotEmpty && mounted) {
        setState(() {
          _expiries = found;
          _showExpiryBanner = true;
        });
      }
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
        pdfPath: widget.filePath,
        rects: _rects,
        ink: _ink,
        notes: _notes,
        stamps: _stamps,
        redactions: _redacts,
        bookmarks: _clauses,
        textEdits: _textEdits,
      );
      if (mounted) setState(() => _isSaved = true);
    } catch (_) {}
  }

  void _onToolChanged(AnnotationTool t) {
    if (t == AnnotationTool.signature || t == AnnotationTool.initials) {
      _launchSigDialog(isInitials: t == AnnotationTool.initials);
      return;
    }

    if (t == AnnotationTool.textEdit) {
      _enterTextEditMode();
      return;
    }

    setState(() {
      _editingPageIndex = null;
      _tool = (_tool == t) ? AnnotationTool.view : t;
      _pendingSig = null;
      _initialsMode = false;
    });
  }

  /// Arms the Edit Text tool. If the tool is already armed, toggles it off.
  ///
  /// Works on documents of any size. The single-page editor loads exactly
  /// one page, so document length only affects the picker — the editor
  /// itself has a constant memory footprint. Commits are pure annotation
  /// objects and never trigger a document reload.
  Future<void> _enterTextEditMode() async {
    if (_tool == AnnotationTool.textEdit) {
      _exitTextEditMode();
      return;
    }

    if (_currentSourceBytes == null) {
      _snack('Document not ready yet.');
      return;
    }
    if (_pageCount <= 0) {
      _snack('Document not loaded yet.');
      return;
    }

    final picked = await _pickPageForEditing();
    if (picked == null) return;

    setState(() {
      _tool = AnnotationTool.textEdit;
      _editingPageIndex = picked;
    });
  }

  void _exitTextEditMode() {
    final lastEdited = _editingPageIndex;
    setState(() {
      _tool = AnnotationTool.view;
      _editingPageIndex = null;
    });
    if (lastEdited != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _visPage = (lastEdited + 1).clamp(1, _pageCount);
        _scrollToPage(lastEdited);
      });
    }
  }

  Future<int?> _pickPageForEditing() async {
    int selected = (_visPage - 1).clamp(0, math.max(0, _pageCount - 1));
    final ctrl = TextEditingController(text: '${selected + 1}');

    try {
      return await showDialog<int>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            backgroundColor: DS.bgCard,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Which page do you want to edit?',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        autofocus: _pageCount > 1,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Page number',
                          labelStyle:
                              const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white10,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: DS.indigo),
                          ),
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n >= 1 && n <= _pageCount) {
                            setSt(() => selected = n - 1);
                          }
                        },
                        onSubmitted: (_) {
                          final n = int.tryParse(ctrl.text);
                          if (n != null && n >= 1 && n <= _pageCount) {
                            Navigator.pop(ctx, n - 1);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'of $_pageCount',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Slider(
                  value: selected.toDouble(),
                  min: 0,
                  max: math.max(0, _pageCount - 1).toDouble(),
                  divisions: _pageCount > 1 ? _pageCount - 1 : null,
                  activeColor: DS.indigo,
                  label: 'Page ${selected + 1}',
                  onChanged: (v) {
                    setSt(() {
                      selected = v.toInt();
                      ctrl.text = '${selected + 1}';
                    });
                  },
                ),
                const SizedBox(height: 4),
                const Text(
                  'Only the page you select is loaded into the editor. '
                  'The rest of the document stays closed.',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 11, height: 1.4),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white54)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: DS.indigo),
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Edit this page'),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  double _pageAspectFor(int index) {
    try {
      final page = _doc!.pages[index];
      return page.width / page.height;
    } catch (_) {
      return 1.414;
    }
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
        _undoStack.add(() => setState(
            () => _rects[a.pageIndex]?.removeWhere((r) => r.id == a.id)));
      });

  void _addInk(int pg, InkStroke s) => _mutate(() {
        final ex = _ink[pg];
        _ink[pg] = ex == null
            ? InkAnnotation(id: _uuid.v4(), pageIndex: pg, strokes: [s])
            : ex.addStroke(s);
        _undoStack.add(() => setState(() {
              final c = _ink[pg];
              if (c == null) return;
              if (c.strokes.length == 1) {
                _ink.remove(pg);
                return;
              }
              _ink[pg] = InkAnnotation(
                  id: c.id,
                  pageIndex: pg,
                  strokes: c.strokes.sublist(0, c.strokes.length - 1));
            }));
      });

  void _addNote(StickyNote n) => _mutate(() {
        _notes.putIfAbsent(n.pageIndex, () => []).add(n);
        _undoStack.add(() => setState(
            () => _notes[n.pageIndex]?.removeWhere((x) => x.id == n.id)));
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
      _undoStack.add(() => setState(
          () => _sigs[m.pageIndex]?.removeWhere((s) => s.id == m.id)));
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
        for (final l in _sigs.values) {
          l.removeWhere((s) => s.id == id);
        }
        _signatureIps.remove(id);
        _markMutated();
      });

  void _addStamp(TextStamp s) => _mutate(() {
        _stamps.putIfAbsent(s.pageIndex, () => []).add(s);
        _undoStack.add(() => setState(
            () => _stamps[s.pageIndex]?.removeWhere((x) => x.id == s.id)));
      });

  void _addRedact(RedactionRect r) => _mutate(() {
        _redacts.putIfAbsent(r.pageIndex, () => []).add(r);
        _undoStack.add(() => setState(
            () => _redacts[r.pageIndex]?.removeWhere((x) => x.id == r.id)));
      });

  void _addBookmark(ClauseBookmark b) => _mutate(() {
        _clauses.putIfAbsent(b.pageIndex, () => []).add(b);
        _undoStack.add(() => setState(
            () => _clauses[b.pageIndex]?.removeWhere((x) => x.id == b.id)));
      });

  void _addTextEdit(TextEditAnnotation t) => _mutate(() {
        _textEdits.putIfAbsent(t.pageIndex, () => []).add(t);
        _undoStack.add(() => setState(
            () => _textEdits[t.pageIndex]?.removeWhere((x) => x.id == t.id)));
      });

  Future<void> _onEditedSourceBytes(Uint8List newBytes) async {
    _currentSourceBytes = newBytes;
    _documentRevision++;
    _markMutated();

    if (_isReloading) {
      _pendingDocReload = newBytes;
      return;
    }

    _isReloading = true;
    try {
      var reloadBytes = newBytes;
      while (true) {
        _pendingDocReload = null;

        final old = _doc;
        PdfDocument fresh;
        try {
          fresh = await PdfLoader.openForViewing(
            path: widget.filePath,
            bytes: reloadBytes,
            password: _password,
          );
        } catch (e) {
          debugPrint('Doc reload failed: $e');
          return;
        }

        if (!mounted) {
          await fresh.dispose();
          return;
        }

        setState(() {
          _doc = fresh;
          _pageCount = fresh.pages.length;
        });

        if (old != null && !identical(old, fresh)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            old.dispose().catchError((_) {});
          });
        }

        final pending = _pendingDocReload;
        if (pending == null) break;
        reloadBytes = pending;
      }
    } finally {
      _isReloading = false;
    }
  }

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

  Future<String?> _buildPdf({bool saveInPlace = true}) => PdfSaveService.save(
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
        saveInPlace: saveInPlace,
      );

  Future<String> _getDeviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'device_fingerprint';
    final existing = prefs.getString(key);
    if (existing != null) return existing;
    final newFp = _uuid.v4();
    await prefs.setString(key, newFp);
    return newFp;
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
      content:
          Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: err ? DS.red : DS.bgCard2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: Duration(seconds: duration),
    ));
  }

  // ─── Save / Share / Print ──────────────────────────────────────────────

  Future<void> _save() async {
    if (_isSaving || _docLoading || _doc == null) return;
    final l10n = AppLocalizations.of(context)!;

    if (!_hasPendingEdits) {
      _snack(l10n.savedAs);
      if (mounted) _showPostActionDialog();
      return;
    }

    setState(() => _isSaving = true);
    try {
      final tempPath = await _buildPdf(saveInPlace: false);
      if (tempPath == null) {
        throw Exception('Could not produce PDF bytes');
      }

      final bytes = PlatformFileService.getCached(tempPath) ??
          (!kIsWeb ? await File(tempPath).readAsBytes() : null);
      if (bytes == null) {
        throw Exception('Could not read built PDF');
      }

      if (!kIsWeb) {
        try {
          await File(tempPath).delete();
        } catch (_) {}
      }

      _currentSourceBytes = bytes;
      _documentRevision++;

      if (kIsWeb) {
        downloadFile(p.basename(widget.filePath), bytes);
        _isSaved = true;
        _snack(l10n.savedAs);
        if (mounted) _showPostActionDialog();
        return;
      }

      final suggestedName = p.basename(widget.filePath);
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );

      if (outputPath == null) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      _isSaved = true;
      _snack('${l10n.savedTo} ${p.basename(outputPath)}', duration: 4);
      if (mounted) _showPostActionDialog();
    } catch (e) {
      if (mounted) {
        _snack('${l10n.saveFailed}: $e', err: true, duration: 5);
      }
      debugPrint('Save error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _share() async {
    if (_isSaving || _docLoading || _doc == null) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() => _isSaving = true);
    try {
      final builtPath = await _buildPdf(saveInPlace: false);
      if (builtPath == null) throw Exception('Could not produce PDF bytes');

      final bytes = PlatformFileService.getCached(builtPath) ??
          (!kIsWeb ? await File(builtPath).readAsBytes() : null);
      if (bytes == null) throw Exception('Could not read output PDF');

      final fileName = p.basename(builtPath);

      if (kIsWeb) {
        downloadFile(fileName, bytes);
        if (mounted) _showPostActionDialog();
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(tempFile.path, mimeType: 'application/pdf')],
          subject: fileName,
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
      final builtPath = await _buildPdf(saveInPlace: false);
      if (builtPath == null) return;
      final bytes = PlatformFileService.getCached(builtPath) ??
          (!kIsWeb ? await File(builtPath).readAsBytes() : null);
      if (bytes == null) return;
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) _snack('${l10n.printError}: $e', err: true);
    }
  }

  void _showPostActionDialog([String? message]) {
    final l10n = AppLocalizations.of(context)!;
    AppleDialog.show(
      context: context,
      title: l10n.done,
      content: message ?? l10n.openAnotherDocument,
      actions: [
        AppleDialogAction(
            label: l10n.no, onPressed: () => Navigator.pop(context)),
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

  // ─── Page rendering ────────────────────────────────────────────────────

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
              : (_annotating
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics()),
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
                        color:
                            Colors.black.withOpacity(isMobile ? 0.04 : 0.08),
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
                            transformationController:
                                _transformationController,
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

  Widget _buildSinglePageEditor() {
    final idx = _editingPageIndex;
    if (idx == null || _doc == null || idx < 0 || idx >= _pageCount) {
      return const SizedBox();
    }

    return Column(
      children: [
        Container(
          color: DS.bgCard,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white70),
                  onPressed: idx > 0
                      ? () => setState(() => _editingPageIndex = idx - 1)
                      : null,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Editing page ${idx + 1} of $_pageCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Tap any box to edit that text',
                        style: TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Next page',
                  icon: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white70),
                  onPressed: idx < _pageCount - 1
                      ? () => setState(() => _editingPageIndex = idx + 1)
                      : null,
                ),
                TextButton.icon(
                  onPressed: _exitTextEditMode,
                  icon: const Icon(Icons.check_rounded,
                      size: 16, color: DS.indigo),
                  label: const Text('Done',
                      style: TextStyle(color: DS.indigo)),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final aspect = _pageAspectFor(idx);

              double pageW = constraints.maxWidth * 0.96;
              double pageH = pageW / aspect;
              final maxH = constraints.maxHeight * 0.96;
              if (pageH > maxH) {
                pageH = maxH;
                pageW = pageH * aspect;
              }
              pageW = pageW.clamp(200.0, 1200.0);

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Container(
                    width: pageW,
                    height: pageW / aspect,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: _buildPageWidget(idx, pageW),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPageWidget(int pageIndex, double width) {
    final isEditingThisPage =
        _tool == AnnotationTool.textEdit && _editingPageIndex == pageIndex;

    return PdfPageWidget(
      key: ValueKey('pg_$pageIndex'),
      document: _doc!,
      pageIndex: pageIndex,
      pageCount: _pageCount,
      revision: _documentRevision,
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
      pendingSignature: (_tool == AnnotationTool.signature ||
              _tool == AnnotationTool.initials)
          ? _pendingSig
          : null,
      isInitialMode: _initialsMode,
      currentSourceBytes: isEditingThisPage ? _currentSourceBytes : null,
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
      onSourceBytesUpdated: _onEditedSourceBytes,
      onHighlightTapped: _zoomToHighlight,
    );
  }

  Widget _errorView() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: DS.red, size: 44),
        const SizedBox(height: 10),
        Text(l10n.cannotOpenFile,
            style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
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

  Widget _buildInsightsView() {
    if (_isAnalyzing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: DS.indigo),
            SizedBox(height: 16),
            Text('Analyzing document...',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_analysisResult != null) {
      return _PdfAnalysisSheet(analysis: _analysisResult!, asScreen: true);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.analytics_rounded, size: 48, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('No analysis yet', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _runAnalysisIfNeeded,
            style: FilledButton.styleFrom(backgroundColor: DS.indigo),
            child: const Text('Run Smart Analysis'),
          ),
        ],
      ),
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
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: DS.indigo, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(widget.filePath),
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        Text(
                          '${l10n.page}$_visPage / $_pageCount',
                          style: DS.caption()
                              .copyWith(fontSize: 10, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                        _readMode
                            ? Icons.menu_book_rounded
                            : Icons.zoom_in_rounded,
                        color: Colors.white54,
                        size: 20),
                    tooltip: _readMode ? l10n.readMode : l10n.zoomMode,
                    onPressed: _toggleReadMode,
                  ),
                  if (_docLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.save_rounded,
                          color: Colors.white24, size: 22),
                    )
                  else if (_isSaving)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: DS.indigo),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.save_rounded,
                          color: DS.indigo, size: 22),
                      tooltip: kIsWeb ? l10n.download : l10n.save,
                      onPressed: _save,
                    ),
                  IconButton(
                    icon: Icon(
                        kIsWeb
                            ? Icons.download_rounded
                            : Icons.ios_share_rounded,
                        color: DS.indigo,
                        size: 20),
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

    final inSinglePageEdit =
        _tool == AnnotationTool.textEdit && _editingPageIndex != null;

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 12, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ExpiryDetector.urgencyLabel(_expiries.first),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 12, color: Colors.white54),
                        onPressed: () =>
                            setState(() => _showExpiryBanner = false),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              if (_pendingSig != null)
                Container(
                  color: DS.indigo.withOpacity(0.15),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app_rounded,
                          color: DS.indigo, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _initialsMode
                              ? l10n.tapToPlaceInitials
                              : l10n.tapToPlaceSignature,
                          style: TextStyle(color: DS.indigo, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _pendingSig = null;
                          _initialsMode = false;
                          _tool = AnnotationTool.view;
                        }),
                        child: Text(l10n.cancel,
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    if (isWideWeb &&
                        _showThumbs &&
                        _doc != null &&
                        !inSinglePageEdit)
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
                      child: _currentTab == _TabMode.insights
                          ? _buildInsightsView()
                          : _docLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: DS.indigo))
                              : _docError != null
                                  ? _errorView()
                                  : _doc == null
                                      ? const SizedBox()
                                      : inSinglePageEdit
                                          ? _buildSinglePageEditor()
                                          : _pageList(),
                    ),
                  ],
                ),
              ),
              if (!isWideWeb &&
                  _showThumbs &&
                  _doc != null &&
                  !inSinglePageEdit)
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
                onProfile: () => SignerProfileDialog.show(context)
                    .then((_) => _loadProfile()),
                onSlots: () => SignatureSlotsPanel.show(
                  context: context,
                  slots: _slots,
                  activeSlotId: _activeSlotId,
                  onChanged: (s, a) => setState(() {
                    _slots = s;
                    _activeSlotId = a;
                  }),
                ),
                onClauses: () => ClausePanel.show(
                  context: context,
                  bookmarks: _clauses,
                  onNavigate: _scrollToPage,
                  onDelete: (id) => setState(() {
                    for (final l in _clauses.values) {
                      l.removeWhere((b) => b.id == id);
                    }
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
                onCompare: () =>
                    DocumentCompareScreen.show(context, widget.filePath),
                onAudit: () => AuditTrailSheet.show(
                  context: context,
                  documentName: p.basename(widget.filePath),
                  events: [
                    AuditEvent.created(p.basename(widget.filePath)),
                    ...(_sigs.values.expand((l) => l).map((s) => s.isInitials
                        ? AuditEvent.initialled(
                            s.signerName ?? 'Unknown', s.pageIndex + 1)
                        : AuditEvent.signed(
                            s.signerName ?? 'Unknown', s.pageIndex + 1))),
                  ],
                ),
                onAnalyze: _runAnalysisIfNeeded,
              ),
            ],
          ),
          _floatingZoomButtons(),
          if (_showFab) _aiFloatingButton(),
        ],
      ),
    );
  }
}

// ─── Analysis Sheet Widget ───────────────────────────────────────────────

class _PdfAnalysisSheet extends StatelessWidget {
  final Map<String, dynamic> analysis;
  final bool asScreen;

  const _PdfAnalysisSheet({required this.analysis, this.asScreen = false});

  @override
  Widget build(BuildContext context) {
    final category = analysis['category'] ?? 'Uncategorized';
    final tags = (analysis['tags'] as List?)?.cast<String>() ?? [];
    final entities = (analysis['entities'] as Map<String, dynamic>?) ?? {};
    final summary = analysis['summary'] ?? 'No summary generated.';
    final pagesAnalyzed = analysis['pagesAnalyzed'] ?? '?';
    final totalPages = analysis['totalPages'] ?? '?';

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!asScreen) ...[
          Text('Document Insights', style: DS.title(size: 18)),
          const SizedBox(height: 4),
          Text('Pages analyzed: $pagesAnalyzed / $totalPages',
              style: TextStyle(color: DS.textSecondary, fontSize: 12)),
          const Divider(),
        ],
        _row('Category', category),
        if (tags.isNotEmpty) _row('Tags', tags.join(', ')),
        ...entities.entries
            .where((e) => (e.value as List).isNotEmpty)
            .map((e) => _row(e.key, (e.value as List).join(', '))),
        const Divider(),
        Text('📝 Summary', style: DS.title(size: 16)),
        const SizedBox(height: 4),
        Text(summary, style: DS.body(size: 13)),
        const SizedBox(height: 16),
        if (!asScreen)
          Center(
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(backgroundColor: DS.indigo),
              child: const Text('Close'),
            ),
          ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      child: content,
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text('$label:',
                  style: TextStyle(
                      color: DS.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(color: DS.textPrimary, fontSize: 12)),
            ),
          ],
        ),
      );
}

// ============================================================================
// Bottom Bar
// ============================================================================
enum _TabMode { edit, annotate, fillSign, insights, all }

class _SidebarThumbs extends StatefulWidget {
  final PdfDocument doc;
  final int pageCount, currentPage;
  final bool darkMode;
  final Map<int, int> annotationCounts;
  final ValueChanged<int> onPageSelected;
  const _SidebarThumbs({
    required this.doc,
    required this.pageCount,
    required this.currentPage,
    required this.darkMode,
    required this.annotationCounts,
    required this.onPageSelected,
  });
  @override
  State<_SidebarThumbs> createState() => _SidebarThumbsState();
}

class _SidebarThumbsState extends State<_SidebarThumbs> {
  @override
  Widget build(BuildContext context) => ThumbnailStrip(
        document: widget.doc,
        pageCount: widget.pageCount,
        currentPage: widget.currentPage,
        darkMode: widget.darkMode,
        annotationCounts: widget.annotationCounts,
        onPageSelected: widget.onPageSelected,
      );
}

class _BottomBar extends StatelessWidget {
  final _TabMode current;
  final AnnotationTool currentTool;
  final bool isSaving, docLoading, darkMode, showThumbs;
  final Color inkColor;
  final ValueChanged<_TabMode> onTabChange;
  final ValueChanged<AnnotationTool> onToolChange;
  final ValueChanged<Color> onColorChange;
  final VoidCallback onUndo,
      onSave,
      onShare,
      onPrint,
      onDark,
      onThumbs,
      onProfile,
      onSlots,
      onClauses,
      onSummary,
      onCompare,
      onAudit;
  final VoidCallback onSearch;
  final VoidCallback onAnalyze;

  const _BottomBar({
    required this.current,
    required this.currentTool,
    required this.isSaving,
    required this.docLoading,
    required this.darkMode,
    required this.showThumbs,
    required this.inkColor,
    required this.onTabChange,
    required this.onToolChange,
    required this.onColorChange,
    required this.onUndo,
    required this.onSave,
    required this.onShare,
    required this.onPrint,
    required this.onSearch,
    required this.onDark,
    required this.onThumbs,
    required this.onProfile,
    required this.onSlots,
    required this.onClauses,
    required this.onSummary,
    required this.onCompare,
    required this.onAudit,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        color: DS.bgCard,
        border: Border(top: BorderSide(color: DS.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                runSpacing: 2,
                children: _toolsForTab(l10n),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: DS.separator, width: 0.3),
                ),
              ),
              child: Row(children: [
                _tab(l10n.tabEdit, Icons.edit_rounded, _TabMode.edit),
                _tab(l10n.tabAnnotate, Icons.rate_review_rounded,
                    _TabMode.annotate),
                _tab(l10n.tabFillSign, Icons.draw_rounded, _TabMode.fillSign),
                _tab('Insights', Icons.analytics_rounded, _TabMode.insights),
                _tab(l10n.tabAll, Icons.apps_rounded, _TabMode.all),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _toolsForTab(AppLocalizations l10n) {
    switch (current) {
      case _TabMode.edit:
        return [
          _tb(Icons.edit_note_rounded, _editTextLabel(l10n),
              AnnotationTool.textEdit, DS.indigo),
          _tb(Icons.text_fields_rounded, l10n.text,
              AnnotationTool.textStamp, DS.indigo),
          _tb(Icons.sticky_note_2_rounded, l10n.note,
              AnnotationTool.stickyNote, DS.orange),
          _ab(Icons.undo_rounded, l10n.undo, onUndo),
        ];
      case _TabMode.annotate:
        return [
          _tb(Icons.highlight_rounded, l10n.highlight,
              AnnotationTool.highlight, const Color(0xFFFFD600)),
          _tb(Icons.format_underline_rounded, l10n.underline,
              AnnotationTool.underline, const Color(0xFF38BDF8)),
          _tb(Icons.strikethrough_s_rounded, l10n.strike,
              AnnotationTool.strikethrough, const Color(0xFFF87171)),
          _tb(Icons.brush_rounded, l10n.draw, AnnotationTool.ink, inkColor),
          if (currentTool == AnnotationTool.ink) _colorPalette(l10n),
          _tb(Icons.sticky_note_2_rounded, l10n.note,
              AnnotationTool.stickyNote, const Color(0xFFFB923C)),
          _tb(Icons.hide_source_rounded, l10n.redact,
              AnnotationTool.redaction, DS.red),
          _tb(Icons.bookmark_add_rounded, l10n.clause,
              AnnotationTool.clauseBookmark, DS.green),
          _ab(Icons.undo_rounded, l10n.undo, onUndo),
        ];
      case _TabMode.fillSign:
        return [
          _tb(Icons.draw_rounded, l10n.sign, AnnotationTool.signature,
              DS.purple),
          _tb(Icons.fingerprint_rounded, l10n.initials,
              AnnotationTool.initials, const Color(0xFFA78BFA)),
          _tb(Icons.text_fields_rounded, l10n.text,
              AnnotationTool.textStamp, DS.indigo),
          _ab(Icons.people_rounded, l10n.slots, onSlots),
          _ab(Icons.verified_rounded, l10n.audit, onAudit),
          _ab(Icons.person_rounded, l10n.profile, onProfile),
          if (docLoading)
            _ab(Icons.save_rounded, kIsWeb ? l10n.download : l10n.save, () {},
                color: Colors.white24)
          else if (isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: DS.indigo),
              ),
            )
          else
            _ab(Icons.save_rounded, kIsWeb ? l10n.download : l10n.save, onSave,
                color: DS.indigo),
          _ab(
              kIsWeb ? Icons.download_rounded : Icons.ios_share_rounded,
              kIsWeb ? l10n.export : l10n.share,
              onShare,
              color: DS.indigo),
        ];
      case _TabMode.insights:
        return [
          _ab(Icons.auto_awesome_rounded, 'Run Analysis', onAnalyze,
              color: DS.indigo),
          _ab(Icons.refresh_rounded, 'Refresh', onAnalyze,
              color: Colors.white54),
        ];
      case _TabMode.all:
        return [
          _tb(Icons.edit_note_rounded, _editTextLabel(l10n),
              AnnotationTool.textEdit, DS.indigo),
          _tb(Icons.highlight_rounded, l10n.highlight,
              AnnotationTool.highlight, const Color(0xFFFFD600)),
          _tb(Icons.brush_rounded, l10n.draw, AnnotationTool.ink, inkColor),
          _tb(Icons.draw_rounded, l10n.sign, AnnotationTool.signature,
              DS.purple),
          _tb(Icons.text_fields_rounded, l10n.text,
              AnnotationTool.textStamp, DS.indigo),
          _tb(Icons.hide_source_rounded, l10n.redact,
              AnnotationTool.redaction, DS.red),
          _ab(
              darkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              l10n.darkMode,
              onDark,
              color: darkMode ? Colors.amber : Colors.white38),
          _ab(
              showThumbs ? Icons.grid_on_rounded : Icons.grid_off_rounded,
              l10n.thumbnails,
              onThumbs,
              color: showThumbs ? DS.indigo : Colors.white38),
          _ab(Icons.compare_rounded, l10n.compare, onCompare),
          _ab(Icons.print_rounded, l10n.print, onPrint),
          _ab(Icons.undo_rounded, l10n.undo, onUndo),
        ];
    }
  }

  String _editTextLabel(AppLocalizations l10n) {
    try {
      final v = (l10n as dynamic).editText;
      if (v is String && v.isNotEmpty) return v;
    } catch (_) {}
    return 'Edit Text';
  }

  Widget _colorPalette(AppLocalizations l10n) {
    const colors = [
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Color(0xFF6366F1),
      Colors.white,
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 1,
          height: 24,
          color: Colors.white12,
          margin: const EdgeInsets.symmetric(horizontal: 4)),
      ...colors.map((c) => ScaleTap(
            onTap: () => onColorChange(c),
            child: Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: inkColor == c
                      ? Colors.white
                      : c == Colors.white
                          ? Colors.grey
                          : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
          )),
      Container(
          width: 1,
          height: 24,
          color: Colors.white12,
          margin: const EdgeInsets.symmetric(horizontal: 4)),
    ]);
  }

  Widget _tab(String label, IconData icon, _TabMode mode) {
    final active = current == mode;
    return Expanded(
      child: ScaleTap(
        onTap: () => onTabChange(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: active ? DS.indigo : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: active ? DS.indigo : DS.textSecondary),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: active ? DS.indigo : DS.textSecondary,
                fontSize: 9,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ]),
        ),
      ),
    );
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

  Widget _ab(IconData icon, String tip, VoidCallback t,
      {Color color = Colors.white54}) {
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