import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:cross_file/cross_file.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:universal_file_viewer/universal_file_viewer.dart' hide FileType;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import '../models/annotation.dart';
import '../screens/template_screen.dart';
import '../services/pdf_loader.dart';
import '../utils/platform_file_service.dart';
import '../utils/app_localizations.dart';
import '../widgets/ds.dart';
import 'create_pdf_screen.dart';
import 'document_compare_screen.dart';
import 'document_editor_screen.dart';
import 'pdf_tools_menu_screen.dart';
import 'pdf_viewer_screen.dart';
import 'scanner_screen.dart';

// ─── Global recent entry ──────────────────────────────────────────────
class RecentEntry {
  final String displayName, virtualPath;
  final Uint8List? bytes;
  final DateTime lastOpened;

  const RecentEntry({
    required this.displayName,
    required this.virtualPath,
    this.bytes,
    required this.lastOpened,
  });

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'virtualPath': virtualPath,
    'lastOpened': lastOpened.toIso8601String(),
  };

  factory RecentEntry.fromJson(Map<String, dynamic> json) => RecentEntry(
    displayName: json['displayName'],
    virtualPath: json['virtualPath'],
    lastOpened: DateTime.parse(json['lastOpened']),
    bytes: null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen – 3‑tab bottom bar (Home, My Files, Templates)
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  List<RecentEntry> _recentPdfs = [];
  static const String _kRecentFilesKey = 'recent_files_v2';

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
  }

  Future<void> _saveRecentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _recentPdfs.map((e) => e.toJson()).toList();
    await prefs.setString(_kRecentFilesKey, jsonEncode(list));
  }

  Future<void> _loadRecentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_kRecentFilesKey);
    if (data == null) return;
    try {
      final List<dynamic> list = jsonDecode(data);
      final loaded = list.map((item) => RecentEntry.fromJson(item)).toList();
      setState(() {
        _recentPdfs = loaded;
      });
    } catch (_) {}
  }

  Future<void> _pickPdf() async {
    try {
      final picked = await PlatformFileService.pickPdf();
      if (picked == null || !mounted) return;
      _addRecent(RecentEntry(
        displayName: picked.displayName,
        virtualPath: picked.virtualPath,
        bytes: picked.bytes,
        lastOpened: DateTime.now(),
      ));
      _openPdf(picked.virtualPath, bytes: picked.bytes);
    } catch (e) {
      _snack('Could not open PDF: $e', err: true);
    }
  }

  /// Opens a PDF directly into the text-edit tool. Same picker as [_pickPdf],
  /// but the viewer is launched with the Edit Text tool already armed so the
  /// user can start replacing text immediately.
  Future<void> _pickAndEditPdf() async {
    try {
      final picked = await PlatformFileService.pickPdf();
      if (picked == null || !mounted) return;
      _addRecent(RecentEntry(
        displayName: picked.displayName,
        virtualPath: picked.virtualPath,
        bytes: picked.bytes,
        lastOpened: DateTime.now(),
      ));
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: picked.virtualPath,
            preloadedBytes: picked.bytes,
            initialTool: AnnotationTool.textEdit,
          ),
        ),
      );
    } catch (e) {
      _snack('Could not open PDF: $e', err: true);
    }
  }

  void _openPdf(String path, {Uint8List? bytes}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PdfViewerScreen(filePath: path, preloadedBytes: bytes),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _openToolsFlow() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfToolsMenuScreen(
          onToolComplete: (displayName, result) {
            final String newPath = result['path'] as String;
            final Uint8List? newBytes = result['bytes'] as Uint8List?;
            _addRecent(RecentEntry(
              displayName: displayName,
              virtualPath: newPath,
              bytes: newBytes,
              lastOpened: DateTime.now(),
            ));
            Navigator.pop(context);
            _openPdf(newPath, bytes: newBytes);
          },
        ),
      ),
    );
  }

  void _addRecent(RecentEntry e) {
    setState(() {
      _recentPdfs.removeWhere((r) => r.virtualPath == e.virtualPath);
      _recentPdfs.insert(0, e);
      if (_recentPdfs.length > 50) _recentPdfs.removeLast();
    });
    _saveRecentFiles();
  }

  void _removeRecent(RecentEntry e) {
    setState(() {
      _recentPdfs.remove(e);
    });
    _saveRecentFiles();
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: DS.textPrimary, fontSize: 13)),
      backgroundColor: err ? DS.red : DS.bgCard2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  List<RecentEntry> get _filteredPdfs {
    if (_searchQuery.isEmpty) return _recentPdfs;
    return _recentPdfs.where((e) =>
        e.displayName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAnyFile() async {
    final XFile? file = await openFile();
    if (file == null || !mounted) return;
    _openFileWithViewer(File(file.path));
  }

  void _openFileWithViewer(File file) {
    final extension = file.path.split('.').last.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProImageEditor.file(
            file,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes, {bool? isChanged}) async {},
            ),
            configs: const ProImageEditorConfigs(),
          ),
        ),
      );
    } else if (extension == 'docx') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Theme(
            data: ThemeData.light(),
            child: Scaffold(
              backgroundColor: Colors.grey[200],
              appBar: AppBar(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                title: const Text('Document Viewer'),
                elevation: 0,
              ),
              body: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = constraints.maxWidth > 900 ? 900.0 : constraints.maxWidth;
                    return Container(
                      width: maxWidth,
                      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 10))
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DocxViewer(file: file),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('DocScanSign Universal Viewer'),
              backgroundColor: DS.bgCard,
            ),
            body: UniversalFileViewer(file: file),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    DS.setStatusBar();
    return kIsWeb ? _buildWebLayout() : _buildMobileLayout();
  }

  // ── Web layout ─────────────────────────────────────────────────────────
  Widget _buildWebLayout() {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: DS.bg,
      body: Row(
        children: [
          Container(
            width: 232,
            height: double.infinity,
            color: DS.bgCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.asset(
                          'icons/logo.png',
                          width: 30,
                          height: 30,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.description, size: 30),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.appName,
                        style: GoogleFonts.inter(
                          color: DS.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ScaleTap(
                    onTap: _pickPdf,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: DS.indigo.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        border: Border.all(color: DS.indigo.withOpacity(0.22)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.upload_file_rounded, color: DS.indigo, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            l10n.openPdf,
                            style: GoogleFonts.inter(
                              color: DS.indigo,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _SidebarItem(
                  icon: Icons.home_rounded,
                  label: l10n.home,
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                _SidebarItem(
                  icon: Icons.folder_rounded,
                  label: 'My Files',
                  active: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
                _SidebarItem(
                  icon: Icons.auto_awesome_rounded,
                  label: l10n.templates,
                  active: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
                const SizedBox(height: 20),
                _SidebarItem(
                  icon: Icons.edit_note_rounded,
                  label: 'Edit PDF',
                  active: false,
                  onTap: _pickAndEditPdf,
                  color: DS.indigo,
                ),
                _SidebarItem(
                  icon: Icons.document_scanner_rounded,
                  label: l10n.scanner,
                  active: false,
                  onTap: () => ScannerScreen.show(context),
                  color: DS.green,
                ),
                _SidebarItem(
                  icon: Icons.picture_as_pdf_rounded,
                  label: l10n.createPdf,
                  active: false,
                  onTap: () => CreatePdfScreen.show(context),
                  color: DS.cyan,
                ),
                const Spacer(),
                Container(height: 1, color: DS.separator),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Container(width: 1, color: DS.separator),
          Expanded(
            child: _webBody(),
          ),
        ],
      ),
    );
  }

  Widget _webBody() {
    switch (_tab) {
      case 0:
        return _WebHome(
          recentPdfs: _filteredPdfs.take(8).toList(),
          onOpenPdf: _pickPdf,
          onEditPdf: _pickAndEditPdf,
          onOpenRecent: (e) => _openPdf(e.virtualPath, bytes: e.bytes),
          onRemove: (e) => _confirmRemoveRecent(e),
        );
      case 1:
        return const _WebFileBrowser();
      case 2:
        return const _WebTemplates();
      default:
        return const SizedBox();
    }
  }

  Future<void> _confirmRemoveRecent(RecentEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DS.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        title: Text(l10n.removeFromRecents,
            style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.removeFromRecentsMessage,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.remove, style: const TextStyle(color: DS.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _removeRecent(entry);
      _snack(l10n.removedFromRecents);
    }
  }

  // ── Mobile layout ──────────────────────────────────────────────────────
  Widget _buildMobileLayout() {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: DS.bg,
      body: IndexedStack(
        index: _tab,
        children: [
          _MobileHome(
            onOpenPdf: _pickPdf,
            onEditPdf: _pickAndEditPdf,
            onScan: () => ScannerScreen.show(context),
            onNewDoc: () => DocumentEditorScreen.openNew(context),
            onCreatePdf: () => CreatePdfScreen.show(context),
            recentPdfs: _recentPdfs,
            onOpenRecent: (e) => _openPdf(e.virtualPath, bytes: e.bytes),
            onRemove: (e) => _confirmRemoveRecent(e),
          ),
          const _MobileFileBrowser(),
          const _MobileTemplates(),
        ],
      ),
      bottomNavigationBar: _CustomNavBar(
        current: _tab,
        onTap: (i) {
          HapticFeedback.lightImpact();
          if (i == 3) {
            _openToolsFlow();
            return;
          }
          setState(() => _tab = i);
        },
      ),
    );
  }
}

// ─── All private widgets ────────────────────────────────────────────────

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
  });
  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.color ??
        (widget.active ? DS.indigo : DS.textSecondary);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.shortAnim,
          margin: const EdgeInsets.fromLTRB(10, 1, 10, 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: widget.active
                ? DS.indigo.withOpacity(0.1)
                : _hover
                    ? DS.bgHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: widget.active
                  ? DS.indigo.withOpacity(0.25)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 17, color: c),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  color: c,
                  fontSize: 13.5,
                  fontWeight:
                      widget.active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Web Home ──────────────────────────────────────────────────────────────
class _WebHome extends StatelessWidget {
  final List<RecentEntry> recentPdfs;
  final VoidCallback onOpenPdf, onEditPdf;
  final ValueChanged<RecentEntry> onOpenRecent, onRemove;

  const _WebHome({
    required this.recentPdfs,
    required this.onOpenPdf,
    required this.onEditPdf,
    required this.onOpenRecent,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DSSectionHeader(
              title: l10n.dashboard, subtitle: l10n.dashboardSubtitle),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            alignment: WrapAlignment.spaceAround,
            children: [
              _stat(l10n.pdfToolsCount, l10n.pdfTools),
              _stat(l10n.templatesCount, l10n.templates),
              _stat(l10n.freeForever, l10n.freeForever),
              _stat(l10n.offlinePrivate, l10n.offlinePrivate),
            ],
          ),
          const SizedBox(height: 24),
          GestureDetector(
              onTap: onOpenPdf, child: const _AnimatedDropZone()),
          const SizedBox(height: 36),
          Text(l10n.quickActions, style: DS.title(size: 14)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _QuickAction(Icons.edit_note_rounded, 'Edit PDF', DS.indigo,
                onTap: onEditPdf),
            _QuickAction(Icons.document_scanner_rounded, l10n.scan, DS.green,
                onTap: () => ScannerScreen.show(context)),
            _QuickAction(Icons.picture_as_pdf_rounded, l10n.createPdf, DS.cyan,
                onTap: () => CreatePdfScreen.show(context)),
            _QuickAction(Icons.note_add_rounded, l10n.newDoc, DS.purple,
                onTap: () => DocumentEditorScreen.openNew(context)),
            _QuickAction(Icons.auto_awesome_rounded, l10n.templatesLabel, DS.orange,
                onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const Scaffold(
                            backgroundColor: DS.bg,
                            appBar: PreferredSize(
                              preferredSize: Size.fromHeight(56),
                              child: SafeArea(
                                child: DSTopBar(
                                    title: 'Templates', showBackButton: true),
                              ),
                            ),
                            body: TemplateGallery(),
                          )));
            }),
          ]),
          if (recentPdfs.isNotEmpty) ...[
            const SizedBox(height: 36),
            Row(
              children: [
                Text(l10n.recentFiles, style: DS.title(size: 18)),
                const Spacer(),
                Text('${recentPdfs.length}',
                    style: DS.label(color: DS.textSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            ...recentPdfs.map((e) => _FileRow(
                  entry: e,
                  onTap: () => onOpenRecent(e),
                  onRemove: () => onRemove(e),
                )),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: DS.indigo)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: DS.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      );
}

// ─── Animated Drop Zone ──────────────────────────────────────────────────
class _AnimatedDropZone extends StatefulWidget {
  const _AnimatedDropZone();
  @override
  State<_AnimatedDropZone> createState() => _AnimatedDropZoneState();
}

class _AnimatedDropZoneState extends State<_AnimatedDropZone>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _pulse.repeat(reverse: true);
  }
  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MouseRegion(
      onEnter: (_) => setState(() {
        _hover = true;
        _pulse.stop();
      }),
      onExit: (_) => setState(() {
        _hover = false;
        _pulse.repeat(reverse: true);
      }),
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Transform.scale(
            scale: _hover ? 1.0 : _pulseAnim.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          height: _hover ? 190 : 170,
          decoration: BoxDecoration(
            color: _hover ? DS.indigo.withOpacity(0.06) : DS.bgCard,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(
                color: _hover ? DS.indigo : DS.separator, width: _hover ? 2 : 1),
            boxShadow: _hover
                ? [
                    BoxShadow(
                        color: DS.indigo.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _hover ? 60 : 48,
                height: _hover ? 60 : 48,
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      DS.indigo,
                      DS.indigo.withOpacity(0.7)
                    ]),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.upload_file_rounded,
                    color: Colors.white, size: _hover ? 28 : 24)),
              const SizedBox(height: 14),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: DS.title(size: _hover ? 16 : 14)
                    .copyWith(color: _hover ? DS.indigo : DS.textPrimary),
                child: Text(l10n.dropZoneHint),
              ),
              const SizedBox(height: 4),
              Text(l10n.dropZoneSubHint,
                  style: DS.body(size: 11, color: DS.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quick Action ─────────────────────────────────────────────────────────
class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _QuickAction(this.icon, this.label, this.color, {this.onTap});
  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => ScaleTap(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: AppTheme.shortAnim,
            width: 140,
            height: 72,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hover ? DS.bgHover : DS.bgCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                  color: _hover ? widget.color.withOpacity(0.3) : DS.separator,
                  width: 0.8),
            ),
            child: Row(
              children: [
                Icon(widget.icon, color: widget.color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(widget.label,
                        style: const TextStyle(
                            color: DS.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ),
      );
}

// ─── File Row (web) ──────────────────────────────────────────────────────
class _FileRow extends StatefulWidget {
  final RecentEntry entry;
  final VoidCallback onTap, onRemove;
  const _FileRow({
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });
  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: ScaleTap(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppTheme.shortAnim,
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _hover ? DS.bgHover : DS.bgCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                  color: _hover ? DS.separatorLight : DS.separator, width: 0.5),
              boxShadow: _hover ? AppTheme.cardShadowHover : AppTheme.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: DS.indigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.picture_as_pdf_rounded,
                      color: DS.indigo, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(widget.entry.displayName,
                        style: TextStyle(
                            color: DS.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis)),
                if (_hover)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: widget.onRemove,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                        ),
                        child: Icon(Icons.close_rounded,
                            size: 20, color: DS.textTertiary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

// ─── Web File Browser (placeholder) ────────────────────────────────────
class _WebFileBrowser extends StatelessWidget {
  const _WebFileBrowser();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('File browser coming soon to web'),
    );
  }
}

// ─── Web Templates (no Pro gate) ──────────────────────────────────────
class _WebTemplates extends StatelessWidget {
  const _WebTemplates();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(40, 40, 40, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DSSectionHeader(
                  title: 'Templates',
                  subtitle: 'Fill in the form and generate a PDF instantly'),
              SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(child: TemplateGallery()),
      ],
    );
  }
}

// ─── Mobile Templates (no Pro gate) ──────────────────────────────────
class _MobileTemplates extends StatelessWidget {
  const _MobileTemplates();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      bottom: false,
      child: TemplateGallery(),
    );
  }
}

// ─── Mobile Home ──────────────────────────────────────────────────────────
class _MobileHome extends StatelessWidget {
  final VoidCallback onOpenPdf, onEditPdf, onScan, onNewDoc, onCreatePdf;
  final List<RecentEntry> recentPdfs;
  final ValueChanged<RecentEntry> onOpenRecent, onRemove;

  const _MobileHome({
    required this.onOpenPdf,
    required this.onEditPdf,
    required this.onScan,
    required this.onNewDoc,
    required this.onCreatePdf,
    required this.recentPdfs,
    required this.onOpenRecent,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GradientText(l10n.appName, style: DS.display(size: 32)),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Professional PDF tools', style: DS.body(size: 14)),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _AttractiveOpenButton(onTap: onOpenPdf, label: l10n.openPdf),
            ),
          ),
          // Feature card — Edit PDF text as a top-level action
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _EditPdfFeatureCard(onTap: onEditPdf),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: [
                  _MobileAction(Icons.document_scanner_rounded, l10n.scan,
                      DS.green, onScan),
                  _MobileAction(Icons.picture_as_pdf_rounded, l10n.createPdf,
                      DS.cyan, onCreatePdf),
                  _MobileAction(Icons.note_add_rounded, l10n.newDoc, DS.purple,
                      onNewDoc),
                  _MobileAction(
                      Icons.auto_awesome_rounded, l10n.templatesLabel, DS.orange, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          backgroundColor: DS.bg,
                          appBar: PreferredSize(
                            preferredSize: Size.fromHeight(56),
                            child: SafeArea(
                              child: DSTopBar(
                                  title: 'Templates', showBackButton: true),
                            ),
                          ),
                          body: TemplateGallery(),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          if (recentPdfs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Row(
                  children: [
                    Text(l10n.recentFiles, style: DS.title(size: 18)),
                    const Spacer(),
                    Text('${recentPdfs.length}',
                        style: DS.label(color: DS.textSecondary)),
                  ],
                ),
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = recentPdfs[index];
                return _MobileRecentFileRow(
                  entry: entry,
                  onTap: () => onOpenRecent(entry),
                  onRemove: () => onRemove(entry),
                );
              },
              childCount: recentPdfs.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ─── Edit PDF feature card ────────────────────────────────────────────────
class _EditPdfFeatureCard extends StatefulWidget {
  final VoidCallback onTap;
  const _EditPdfFeatureCard({required this.onTap});

  @override
  State<_EditPdfFeatureCard> createState() => _EditPdfFeatureCardState();
}

class _EditPdfFeatureCardState extends State<_EditPdfFeatureCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                DS.indigo.withOpacity(0.14),
                DS.indigo.withOpacity(0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: DS.indigo.withOpacity(0.3), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DS.indigo,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: DS.indigo.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.edit_note_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Edit PDF',
                      style: TextStyle(
                        color: DS.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Change any text in a PDF, keep the original look',
                      style: TextStyle(
                        color: DS.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: DS.indigo, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mobile Recent File Row ───────────────────────────────────────────────
class _MobileRecentFileRow extends StatelessWidget {
  final RecentEntry entry;
  final VoidCallback onTap, onRemove;
  const _MobileRecentFileRow({
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: DS.indigo.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.picture_as_pdf_rounded, color: DS.indigo),
        ),
        title: Text(
          entry.displayName,
          style: const TextStyle(color: DS.textPrimary, fontWeight: FontWeight.w500),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close_rounded, color: DS.textTertiary, size: 20),
          onPressed: onRemove,
        ),
        onTap: onTap,
      ),
    );
  }
}

// ─── Attractive Open PDF Button ───────────────────────────────────────────
class _AttractiveOpenButton extends StatefulWidget {
  final VoidCallback onTap;
  final String label;
  const _AttractiveOpenButton({required this.onTap, required this.label});

  @override
  State<_AttractiveOpenButton> createState() => _AttractiveOpenButtonState();
}

class _AttractiveOpenButtonState extends State<_AttractiveOpenButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmer;
  late Animation<double> _shimmerAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _shimmerAnim = Tween<double>(begin: -1.5, end: 1.5).animate(
        CurvedAnimation(parent: _shimmer, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        HapticFeedback.mediumImpact();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedBuilder(
          animation: _shimmerAnim,
          builder: (_, child) {
            return Container(
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: const [
                    Color(0xFF4F46E5),
                    Color(0xFF7C3AED),
                    Color(0xFF4F46E5),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: DS.indigo.withOpacity(_pressed ? 0.2 : 0.45),
                    blurRadius: _pressed ? 8 : 20,
                    offset: const Offset(0, 6),
                    spreadRadius: _pressed ? 0 : 1,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(
                        painter: _ShimmerPainter(_shimmerAnim.value),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.folder_open_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white70, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final double progress;
  _ShimmerPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * (progress + 1) / 2;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.08),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(x - 60, 0, 120, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.progress != progress;
}

// ─── Mobile Action ────────────────────────────────────────────────────────
class _MobileAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MobileAction(this.icon, this.label, this.color, this.onTap);
  @override
  State<_MobileAction> createState() => _MobileActionState();
}

class _MobileActionState extends State<_MobileAction>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _s;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _s = Tween(begin: 1.0, end: 0.94).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapUp: (_) {
          _c.reverse();
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onTapCancel: () => _c.reverse(),
        child: ScaleTransition(
          scale: _s,
          child: Container(
            decoration: BoxDecoration(
              color: DS.bgCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: DS.separator, width: 0.5),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(widget.icon, color: widget.color, size: 18),
                ),
                const SizedBox(width: 10),
                Text(widget.label,
                    style: DS.label(size: 13, color: DS.textPrimary)),
              ],
            ),
          ),
        ),
      );
}

// ─── Mobile File Browser ─────────────────────────────────────────────────
class _MobileFileBrowser extends StatefulWidget {
  const _MobileFileBrowser();

  @override
  State<_MobileFileBrowser> createState() => _MobileFileBrowserState();
}

class _MobileFileBrowserState extends State<_MobileFileBrowser> {
  bool _launching = false;

  Future<void> _openFilePicker() async {
    if (_launching) return;
    setState(() => _launching = true);

    try {
      final XFile? file = await openFile();
      if (!mounted) return;
      if (file != null) {
        _openFile(File(file.path));
      }
    } catch (_) {
      // user cancelled or permission denied — no-op
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  void _openFile(File file) {
    final extension = file.path.split('.').last.toLowerCase();

    if (extension == 'pdf') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(filePath: file.path),
        ),
      );
      return;
    }

    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProImageEditor.file(
            file,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes, {bool? isChanged}) async {},
            ),
            configs: const ProImageEditorConfigs(),
          ),
        ),
      );
    } else if (extension == 'docx') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Theme(
            data: ThemeData.light(),
            child: Scaffold(
              backgroundColor: Colors.grey[200],
              appBar: AppBar(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                title: const Text('Document Viewer'),
                elevation: 0,
              ),
              body: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = constraints.maxWidth > 900 ? 900.0 : constraints.maxWidth;
                    return Container(
                      width: maxWidth,
                      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 10))
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DocxViewer(file: file),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('DocScanSign Universal Viewer'),
              backgroundColor: DS.bgCard,
            ),
            body: UniversalFileViewer(file: file),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Text('My Files', style: DS.heading(size: 32)),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [DS.indigo.withOpacity(0.15), DS.indigo.withOpacity(0.05)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: DS.indigo.withOpacity(0.2)),
                      ),
                      child: Icon(Icons.folder_open_rounded, color: DS.indigo, size: 40),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Browse Device Files',
                      style: DS.title(size: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open PDFs, images, Word docs and more from your device.',
                      style: DS.body(size: 14, color: DS.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _launching ? null : _openFilePicker,
                        icon: _launching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.folder_open_rounded, size: 20),
                        label: Text(
                          _launching ? 'Opening…' : 'Choose File',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DS.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Supports PDF, DOCX, JPG, PNG and more',
                      style: DS.caption(),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Custom Navigation Bar ───────────────────────────────────────────────
class _CustomNavBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;

  const _CustomNavBar({
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const labels = ['Home', 'My Files', 'Templates', 'Tools'];
    const icons = [
      Icons.house_rounded,
      Icons.folder_rounded,
      Icons.auto_awesome_rounded,
      Icons.build_rounded,
    ];

    return Container(
      decoration: BoxDecoration(
        color: DS.bgCard,
        border: Border(top: BorderSide(color: DS.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(4, (i) {
              final active = i == current;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    color: Colors.transparent,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          scale: active ? 1.12 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            icons[i],
                            size: 26,
                            color: active ? DS.indigoLight : DS.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          labels[i],
                          style: TextStyle(
                            color: active ? DS.indigoLight : DS.textSecondary,
                            fontSize: 11,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}