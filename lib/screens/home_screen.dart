import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:universal_file_viewer/universal_file_viewer.dart' hide FileType;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_archive/flutter_archive.dart' as flutter_archive;

import '../screens/template_screen.dart';
import '../services/pdf_loader.dart';
import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import 'create_pdf_screen.dart';
import 'document_editor_screen.dart';
import 'pdf_viewer_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final List<_RecentEntry> _recentPdfs = [];

  Future<void> _pickPdf() async {
    try {
      final picked = await PlatformFileService.pickPdf();
      if (picked == null || !mounted) return;
      _addRecent(_RecentEntry(displayName: picked.displayName,
          virtualPath: picked.virtualPath, bytes: picked.bytes));
      _openPdf(picked.virtualPath, bytes: picked.bytes);
    } catch (e) { _snack('Could not open PDF: $e', err: true); }
  }

  void _openPdf(String path, {Uint8List? bytes}) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));

  void _addRecent(_RecentEntry e) => setState(() {
    _recentPdfs.removeWhere((r) => r.virtualPath == e.virtualPath);
    _recentPdfs.insert(0, e);
    if (_recentPdfs.length > 20) _recentPdfs.removeLast();
  });

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: err ? DS.red : DS.bgCard2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12)));
  }



  @override
  Widget build(BuildContext context) {
    DS.setStatusBar();
    return kIsWeb ? _buildWebLayout() : _buildMobileLayout();
  }

  // ── Web layout ──────────────────────────────────────────────────
  Widget _buildWebLayout() {
    return Scaffold(
      backgroundColor: DS.bg,
      body: Row(children: [
        Container(
          width: 232,
          color: DS.bgCard,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 24),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Container(width: 30, height: 30,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8)),
                          child: Image.asset('icons/logo.png', width: 30, height: 30)),
                const SizedBox(width: 10),
                Text('DocSign', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                const SizedBox(width: 6),
                const DSBadge(text: 'PRO', color: DS.purple),
              ])),
            const SizedBox(height: 20),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
              child: PrimaryButton(label: 'Open PDF', icon: Icons.upload_file_rounded, onTap: _pickPdf, height: 40)),
            const SizedBox(height: 6),
            _SidebarItem(icon: Icons.home_rounded, label: 'Home', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
            _SidebarItem(icon: Icons.access_time_rounded, label: 'Recent', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
            _SidebarItem(icon: Icons.auto_awesome_rounded, label: 'Templates', active: _tab == 2, onTap: () => setState(() => _tab = 2)),
            const Spacer(),
            Container(height: 1, color: DS.separator),
            const SizedBox(height: 10),
            _SidebarItem(icon: Icons.document_scanner_rounded, label: 'Scanner', active: false, onTap: () => ScannerScreen.show(context), color: DS.green),
            _SidebarItem(
              icon: Icons.picture_as_pdf_rounded,
              label: 'Create PDF',
              active: false,
              onTap: () => CreatePdfScreen.show(context),
              color: DS.cyan,
            ),



            _SidebarItem(
              icon: Icons.build_rounded,
              label: 'PDF Tools',
              active: false,
              onTap: () {},
              color: DS.purple,
            ),
            const SizedBox(height: 16),
          ])),
        Container(width: 1, color: DS.separator),
        Expanded(child: _webBody()),
      ]),
    );
  }

  Widget _webBody() {
    switch (_tab) {
      case 0: return _WebHome(
        recentPdfs: _recentPdfs,
        onOpenPdf: _pickPdf,
        onOpenRecent: (e) => _openPdf(e.virtualPath, bytes: e.bytes),
        onRemove: (e) => setState(() => _recentPdfs.remove(e)),
      );
      case 1: return _WebRecents(pdfs: _recentPdfs, onOpen: (e) => _openPdf(e.virtualPath, bytes: e.bytes), onRemove: (e) => setState(() => _recentPdfs.remove(e)));
      case 2: return const _WebTemplates();
      default: return const SizedBox();
    }
  }

  // ── Mobile layout ──────────────────────────────────────────────
  Widget _buildMobileLayout() {
    final tabs = [
      (Icons.house_rounded, 'Home'),
      (Icons.access_time_rounded, 'Recents'),
      (Icons.auto_awesome_rounded, 'Templates'),
      (Icons.folder_rounded, 'Files'),
      (Icons.settings_rounded, 'Settings')
    ];
    return Scaffold(
      backgroundColor: DS.bg,
      body: IndexedStack(index: _tab, children: [
        _MobileHome(
          onOpenPdf: _pickPdf,
          onScan: () => ScannerScreen.show(context),
          onNewDoc: () => DocumentEditorScreen.openNew(context),
          onCreatePdf: () => CreatePdfScreen.show(context),
          recentPdfs: _recentPdfs,
          onOpenRecent: (e) => _openPdf(e.virtualPath, bytes: e.bytes),
          onRemove: (e) => setState(() => _recentPdfs.remove(e)),
        ),
        _MobileRecents(pdfs: _recentPdfs, onOpen: (e) => _openPdf(e.virtualPath, bytes: e.bytes), onRemove: (e) => setState(() => _recentPdfs.remove(e))),
        Scaffold(backgroundColor: DS.bg, body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.fromLTRB(20,20,20,16), child: Text('Templates', style: DS.heading(size: 28))), const Expanded(child: TemplateGallery())]))),
        const _MobileFileManager(),
        _MobileSettings(),
      ]),
      bottomNavigationBar: _PremiumNavBar(current: _tab, tabs: tabs, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

// ========== SIDEBAR ITEM ==========
class _SidebarItem extends StatefulWidget {
  final IconData icon; final String label; final bool active; final VoidCallback onTap; final Color? color;
  const _SidebarItem({required this.icon, required this.label, required this.active, required this.onTap, this.color});
  @override State<_SidebarItem> createState() => _SidebarItemState();
}
class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? (widget.active ? DS.indigo : DS.textSecondary);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap,
        child: AnimatedContainer(duration: const Duration(milliseconds: 130), margin: const EdgeInsets.fromLTRB(10, 1, 10, 1), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(color: widget.active ? DS.indigo.withOpacity(0.1) : _hover ? DS.bgHover : Colors.transparent, borderRadius: BorderRadius.circular(9), border: Border.all(color: widget.active ? DS.indigo.withOpacity(0.25) : Colors.transparent)),
          child: Row(children: [Icon(widget.icon, size: 17, color: c), const SizedBox(width: 10), Text(widget.label, style: TextStyle(color: c, fontSize: 13.5, fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500))]))));
  }
}

// ========== WEB HOME ==========
class _WebHome extends StatelessWidget {
  final List<_RecentEntry> recentPdfs;
  final VoidCallback onOpenPdf;
  final ValueChanged<_RecentEntry> onOpenRecent, onRemove;

  const _WebHome({
    required this.recentPdfs,
    required this.onOpenPdf,
    required this.onOpenRecent,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(40),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DSSectionHeader(title: 'Dashboard', subtitle: 'Open, sign and manage documents'),
      const SizedBox(height: 16),
      Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [DS.indigo.withOpacity(0.08), DS.purple.withOpacity(0.04)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DS.indigo.withOpacity(0.1)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('60+', 'PDF Tools'),
          Container(width: 1, height: 36, color: DS.separator),
          _stat('16', 'Templates'),
          Container(width: 1, height: 36, color: DS.separator),
          _stat('100%', 'Free Forever'),
          Container(width: 1, height: 36, color: DS.separator),
          _stat('Offline', '100% Private'),
        ]),
      ),
      GestureDetector(onTap: onOpenPdf, child: const _AnimatedDropZone()),
      const SizedBox(height: 36),
      Text('Quick Actions', style: DS.title(size: 14)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        const _QuickAction(Icons.document_scanner_rounded, 'Scan', DS.green),
        const _QuickAction(Icons.picture_as_pdf_rounded, 'Create PDF', DS.cyan),
        const _QuickAction(Icons.auto_awesome_rounded, 'Templates', DS.orange),
        const _QuickAction(Icons.compare_rounded, 'Compare', DS.purple),
      ]),
      if (recentPdfs.isNotEmpty) ...[
        const SizedBox(height: 36),
        DSSectionHeader(title: 'Recent Files'),
        ...recentPdfs.take(8).map((e) => _FileRow(entry: e, onTap: () => onOpenRecent(e), onRemove: () => onRemove(e))),
      ],
    ]));

  Widget _stat(String value, String label) => Column(children: [
    Text(value, style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: DS.indigo)),
    const SizedBox(height: 2),
    Text(label, style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
  ]);
}

class _AnimatedDropZone extends StatefulWidget {
  const _AnimatedDropZone();
  @override State<_AnimatedDropZone> createState() => _AnimatedDropZoneState();
}
class _AnimatedDropZoneState extends State<_AnimatedDropZone> with SingleTickerProviderStateMixin {
  bool _hover = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _pulse.repeat(reverse: true);
  }
  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() { _hover = true; _pulse.stop(); }),
    onExit: (_) => setState(() { _hover = false; _pulse.repeat(reverse: true); }),
    child: AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) => Transform.scale(scale: _hover ? 1.0 : _pulseAnim.value, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity, height: _hover ? 190 : 170,
        decoration: BoxDecoration(
          color: _hover ? DS.indigo.withOpacity(0.06) : DS.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hover ? DS.indigo : DS.separator, width: _hover ? 2 : 1),
          boxShadow: _hover ? [BoxShadow(color: DS.indigo.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8))] : [],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(duration: const Duration(milliseconds: 300),
            width: _hover ? 60 : 48, height: _hover ? 60 : 48,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [DS.indigo, DS.indigo.withOpacity(0.7)]), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.upload_file_rounded, color: Colors.white, size: _hover ? 28 : 24)),
          const SizedBox(height: 14),
          AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 200), style: DS.title(size: _hover ? 16 : 14).copyWith(color: _hover ? DS.indigo : Colors.white), child: const Text('Drop your PDF here or click to browse')),
          const SizedBox(height: 4),
          Text('Supports password-protected PDFs', style: DS.body(size: 11, color: Colors.white38)),
        ]),
      ),
    ),
  );
}

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
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        width: 140,
        height: 72,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hover ? DS.bgHover : DS.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hover ? widget.color.withOpacity(0.3) : DS.separator, width: 0.8),
        ),
        child: Row(children: [
          Icon(widget.icon, color: widget.color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      ),
    ),
  );
}

class _FileRow extends StatefulWidget {
  final _RecentEntry entry; final VoidCallback onTap, onRemove;
  const _FileRow({required this.entry, required this.onTap, required this.onRemove});
  @override State<_FileRow> createState() => _FileRowState();
}
class _FileRowState extends State<_FileRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _hover ? DS.bgHover : DS.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _hover ? DS.separatorLight : DS.separator, width: 0.5),
        ),
        child: Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: DS.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.picture_as_pdf_rounded, color: DS.indigo, size: 16)),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.entry.displayName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
          if (_hover) DSIconBtn(icon: Icons.close_rounded, tooltip: 'Remove', onTap: widget.onRemove, color: DS.textTertiary, size: 15),
        ]),
      ),
    ),
  );
}

class _WebRecents extends StatelessWidget {
  final List<_RecentEntry> pdfs; final ValueChanged<_RecentEntry> onOpen, onRemove;
  const _WebRecents({required this.pdfs, required this.onOpen, required this.onRemove});
  @override
  Widget build(BuildContext context) => pdfs.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history_rounded, size: 44, color: DS.textMuted), const SizedBox(height: 12), Text('No recent files', style: DS.body(size: 15))]))
      : ListView.builder(padding: const EdgeInsets.all(40), itemCount: pdfs.length + 1, itemBuilder: (_, i) {
          if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 20), child: DSSectionHeader(title: 'Recent Files', subtitle: '${pdfs.length} document${pdfs.length > 1 ? "s" : ""}'));
          final e = pdfs[i - 1]; return _FileRow(entry: e, onTap: () => onOpen(e), onRemove: () => onRemove(e));
        });
}

class _WebTemplates extends StatelessWidget {
  const _WebTemplates();
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Padding(padding: EdgeInsets.fromLTRB(40, 40, 40, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [DSSectionHeader(title: 'Templates', subtitle: 'Fill in the form and generate a PDF instantly'), SizedBox(height: 8)])),
    const Expanded(child: TemplateGallery()),
  ]);
}

// ========== MOBILE HOME ==========
class _MobileHome extends StatelessWidget {
  final VoidCallback onOpenPdf, onScan, onNewDoc, onCreatePdf;
  final List<_RecentEntry> recentPdfs;
  final ValueChanged<_RecentEntry> onOpenRecent, onRemove;

  const _MobileHome({
    required this.onOpenPdf,
    required this.onScan,
    required this.onNewDoc,
    required this.onCreatePdf,
    required this.recentPdfs,
    required this.onOpenRecent,
    required this.onRemove,
  });

 @override
Widget build(BuildContext context) => SafeArea(
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
                      GradientText('DocSign', style: DS.display(size: 32)),
                      const Spacer(),
                      const DSBadge(text: 'v2.0', color: DS.indigo),
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
              child: PrimaryButton(
                label: 'Open a PDF',
                icon: Icons.folder_open_rounded,
                onTap: onOpenPdf,
                height: 52,
              ),
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
                  _MobileAction(Icons.document_scanner_rounded, 'Scanner', DS.green, onScan),
                  _MobileAction(Icons.picture_as_pdf_rounded, 'Create PDF', DS.cyan, onCreatePdf),
                  _MobileAction(Icons.note_add_rounded, 'New Doc', DS.purple, onNewDoc),
                  _MobileAction(Icons.auto_awesome_rounded, 'Templates', DS.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: DS.bg, appBar: AppBar(backgroundColor: DS.bgCard, elevation: 0, surfaceTintColor: Colors.transparent, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20), onPressed: () => Navigator.pop(context)), title: Text('Templates', style: DS.title())), body: const SafeArea(child: TemplateGallery()))))),
                ],
              ),
            ),
          ),

          if (recentPdfs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_rounded, size: 48, color: DS.textMuted),
                      const SizedBox(height: 16),
                      Text('No documents yet', style: DS.title(size: 16)),
                      const SizedBox(height: 6),
                      Text(
                        'Open a PDF to get started',
                        style: DS.body(size: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Row(
                  children: [
                    Text('Recent', style: DS.title(size: 18)),
                    const SizedBox(width: 8),
                    Text(
                      '${recentPdfs.length}',
                      style: DS.label(color: DS.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: recentPdfs.length,
              itemBuilder: (_, i) {
                final e = recentPdfs[i];
                return _MobileFileRow(
                  entry: e,
                  onTap: () => onOpenRecent(e),
                  onRemove: () => onRemove(e),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
}

class _MobileAction extends StatefulWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _MobileAction(this.icon, this.label, this.color, this.onTap);
  @override State<_MobileAction> createState() => _MobileActionState();
}
class _MobileActionState extends State<_MobileAction> with SingleTickerProviderStateMixin {
  late AnimationController _c; late Animation<double> _s;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 100)); _s = Tween(begin: 1.0, end: 0.94).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => GestureDetector(onTapDown: (_) => _c.forward(), onTapUp: (_) { _c.reverse(); widget.onTap(); }, onTapCancel: () => _c.reverse(), child: ScaleTransition(scale: _s, child: Container(decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: DS.separator, width: 0.5)), child: Row(children: [const SizedBox(width: 14), Container(width: 36, height: 36, decoration: BoxDecoration(color: widget.color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(widget.icon, color: widget.color, size: 18)), const SizedBox(width: 10), Text(widget.label, style: DS.label(size: 13, color: Colors.white))]))));
}

class _MobileFileRow extends StatelessWidget {
  final _RecentEntry entry; final VoidCallback onTap, onRemove;
  const _MobileFileRow({required this.entry, required this.onTap, required this.onRemove});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(margin: const EdgeInsets.fromLTRB(20, 0, 20, 6), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), decoration: DS.card, child: Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: DS.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.picture_as_pdf_rounded, color: DS.indigo, size: 17)), const SizedBox(width: 12), Expanded(child: Text(entry.displayName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: DS.textTertiary), const SizedBox(width: 4), GestureDetector(onTap: onRemove, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 14, color: DS.textSecondary)))])));
}

class _MobileRecents extends StatelessWidget {
  final List<_RecentEntry> pdfs; final ValueChanged<_RecentEntry> onOpen, onRemove;
  const _MobileRecents({required this.pdfs, required this.onOpen, required this.onRemove});
  @override Widget build(BuildContext context) => SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 20), child: Text('Recents', style: DS.heading(size: 32))), Expanded(child: pdfs.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history_rounded, size: 44, color: DS.textMuted), const SizedBox(height: 12), Text('No recent files', style: DS.body(size: 15))])) : ListView.builder(itemCount: pdfs.length, itemBuilder: (_, i) => _MobileFileRow(entry: pdfs[i], onTap: () => onOpen(pdfs[i]), onRemove: () => onRemove(pdfs[i]))))]));
}

class _MobileSettings extends StatelessWidget {
  const _MobileSettings();
  @override Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [Text('Settings', style: DS.heading(size: 32)), const SizedBox(height: 24), DSCard(child: Column(children: [_SettingRow(Icons.info_outline_rounded, DS.textSecondary, 'About DocSign', 'Version 2.0 · 100% Offline', () {}), Container(height: 1, color: DS.separator), _SettingRow(Icons.privacy_tip_rounded, DS.indigo, 'Privacy Policy', 'No data collected', () {})]))]));
}

class _SettingRow extends StatelessWidget {
  final IconData icon; final Color color; final String title, sub; final VoidCallback onTap;
  const _SettingRow(this.icon, this.color, this.title, this.sub, this.onTap);
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), child: Row(children: [Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 16, color: color)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)), Text(sub, style: DS.caption())])), Icon(Icons.arrow_forward_ios_rounded, size: 12, color: DS.textTertiary)])));
}

class _PremiumNavBar extends StatelessWidget {
  final int current; final List<(IconData, String)> tabs; final ValueChanged<int> onTap;
  const _PremiumNavBar({required this.current, required this.tabs, required this.onTap});
  @override Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: DS.bgCard, border: Border(top: BorderSide(color: DS.separator, width: 0.5))), child: SafeArea(top: false, child: SizedBox(height: 58, child: Row(children: tabs.asMap().entries.map((e) { final active = e.key == current; final (icon, label) = e.value; return Expanded(child: GestureDetector(onTap: () => onTap(e.key), behavior: HitTestBehavior.opaque, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [AnimatedContainer(duration: const Duration(milliseconds: 200), width: 40, height: 28, decoration: BoxDecoration(color: active ? DS.indigo.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 19, color: active ? DS.indigoLight : DS.textSecondary)), const SizedBox(height: 2), Text(label, style: TextStyle(color: active ? DS.indigoLight : DS.textSecondary, fontSize: 10, fontWeight: active ? FontWeight.w600 : FontWeight.w500))]))); }).toList()))));
}

// ========== MOBILE FILE MANAGER (FULLY RESTORED) ==========
class _MobileFileManager extends StatefulWidget {
  const _MobileFileManager();

  @override
  State<_MobileFileManager> createState() => _MobileFileManagerState();
}

class _MobileFileManagerState extends State<_MobileFileManager> {


  Future<void> _openFile(File file) async {
    final extension = file.path.split('.').last.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      final result = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (context) => ProImageEditor.file(
            file,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes, {bool? isChanged}) async {
                Navigator.pop(context, bytes);
              },
            ),
            configs: const ProImageEditorConfigs(),
          ),
        ),
      );
      if (result != null) {
        // 1. Let the user choose the folder
        String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

        if (selectedDirectory != null) {
          // 2. Create the file using the selected path
          final editedFile = File('$selectedDirectory/edited_${DateTime.now().millisecondsSinceEpoch}.png');
          
          // 3. Write the bytes
          await editedFile.writeAsBytes(result);
          
          _snack('Saved: ${editedFile.path}');
        } else {
          // User canceled the picker
          _snack('Save cancelled: No folder selected');
        }
      }
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
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 10))],
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
            appBar: AppBar(title: const Text('DocSign Universal Viewer'), backgroundColor: DS.bgCard),
            body: UniversalFileViewer(file: file),
          ),
        ),
      );
    }
  }


  Future<void> _openAnyFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || !mounted) return;
    final filePath = result.files.single.path;
    if (filePath == null) { _snack('Invalid file path', err: true); return; }
    await _openFile(File(filePath));
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: err ? DS.red : DS.bgCard2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 20), child: Text('DocSign File Manager', style: DS.heading(size: 32))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                PrimaryButton(label: 'Open Any File', icon: Icons.file_open, onTap: _openAnyFile, height: 52),
                const SizedBox(height: 12),

              ],
            ),
          ),

        ],
      ),
    );
  }
}

class _RecentEntry {
  final String displayName, virtualPath; final Uint8List? bytes;
  const _RecentEntry({required this.displayName, required this.virtualPath, this.bytes});
}