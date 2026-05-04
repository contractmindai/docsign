import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/pdf_loader.dart';
import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import 'home_screen.dart';
import 'privacy_policy_screen.dart';
import 'pdf_viewer_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppRoot — routes web → landing, mobile → home
// ─────────────────────────────────────────────────────────────────────────────

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const HomeScreen();
    return const WebLandingScreen();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WebLandingScreen
// ─────────────────────────────────────────────────────────────────────────────

class WebLandingScreen extends StatefulWidget {
  const WebLandingScreen({super.key});
  @override
  State<WebLandingScreen> createState() => _WebLandingState();
}

class _WebLandingState extends State<WebLandingScreen> {
  bool _dragging = false;
  int  _activeFeature = 0;

  Future<void> _openPdf() async {
    try {
      final result = await PdfLoader.pick();
      if (result == null || !mounted) return;
      if (result.bytes != null) {
        PlatformFileService.cache(result.displayPath, result.bytes!);
      }
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
              filePath: result.displayPath,
              preloadedBytes: result.bytes)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'), backgroundColor: DS.red));
    }
  }

  void _openApp() => Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) => const HomeScreen()));

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w       = MediaQuery.of(context).size.width;
    final isWide  = w > 900;
    final isMid   = w > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(children: [

          // ── Navbar ─────────────────────────────────────────────────────────
          _Navbar(isWide: isWide, onOpenPdf: _openPdf,
              onOpenApp: _openApp, onLaunch: _launch),

          // ── Hero ───────────────────────────────────────────────────────────
          _Hero(isWide: isWide, dragging: _dragging,
            onDragEnter: () => setState(() => _dragging = true),
            onDragLeave: () => setState(() => _dragging = false),
            onOpenPdf: _openPdf, onOpenApp: _openApp),

          // ── How it works ───────────────────────────────────────────────────
          _HowItWorks(isWide: isWide),

          // ── Features deep-dive ─────────────────────────────────────────────
          _FeatureDeepDive(
              isWide: isWide,
              active: _activeFeature,
              onSelect: (i) => setState(() => _activeFeature = i)),

          // ── eSign compliance ───────────────────────────────────────────────
          _ESignSection(isWide: isWide),

          // ── Templates showcase ─────────────────────────────────────────────
          _TemplatesSection(isWide: isWide, onOpenApp: _openApp),

          // ── ContractMind CTA ───────────────────────────────────────────────
          _ContractMindCta(onLaunch: _launch, onOpenApp: _openApp),

          // ── Footer ─────────────────────────────────────────────────────────
          _Footer(onLaunch: _launch),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navbar
// ─────────────────────────────────────────────────────────────────────────────

class _Navbar extends StatelessWidget {
  final bool isWide;
  final VoidCallback onOpenPdf, onOpenApp;
  final Future<void> Function(String) onLaunch;
  const _Navbar({required this.isWide, required this.onOpenPdf,
      required this.onOpenApp, required this.onLaunch});

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 20),
    decoration: BoxDecoration(
        color: const Color(0xFF09090B),
        border: Border(bottom: BorderSide(
            color: Colors.white.withOpacity(0.07)))),
    child: Row(children: [
      // Logo
      Row(children: [
        Container(width: 30, height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [DS.indigo, Color(0xFF8B5CF6)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.description_rounded,
              color: Colors.white, size: 17)),
        const SizedBox(width: 9),
        Text('DocSign', style: GoogleFonts.inter(
            color: Colors.white, fontSize: 17,
            fontWeight: FontWeight.w700, letterSpacing: -0.4)),
      ]),
      const Spacer(),
      if (isWide) const SizedBox(width: 8),
      OutlinedButton(
        onPressed: () => onLaunch('https://www.contractmind.ai'),
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withOpacity(0.15)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8))),
        child: const Text('ContractMind',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: onOpenApp,
        style: FilledButton.styleFrom(
            backgroundColor: DS.indigo,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8))),
        child: const Text('Open App',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
    ]),
  );

  Widget _link(String label, VoidCallback t) => TextButton(
    onPressed: t,
    style: TextButton.styleFrom(foregroundColor: Colors.white54,
        padding: const EdgeInsets.symmetric(horizontal: 10)),
    child: Text(label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)));
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero
// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final bool isWide, dragging;
  final VoidCallback onDragEnter, onDragLeave, onOpenPdf, onOpenApp;
  const _Hero({required this.isWide, required this.dragging,
      required this.onDragEnter, required this.onDragLeave,
      required this.onOpenPdf, required this.onOpenApp});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
        horizontal: isWide ? 80 : 24, vertical: isWide ? 88 : 52),
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topCenter,
        radius: 1.5,
        colors: [DS.indigo.withOpacity(0.12), Colors.transparent],
      ),
    ),
    child: isWide
        ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: _heroText()),
            const SizedBox(width: 60),
            Expanded(child: _dropZone()),
          ])
        : Column(children: [
            _heroText(),
            const SizedBox(height: 44),
            _dropZone(),
          ]),
  );

  Widget _heroText() => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    // Badge
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
          color: DS.green.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DS.green.withOpacity(0.35))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6,
            decoration: const BoxDecoration(
                color: DS.green, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        const Text('Free · 100% Offline · No Account',
            style: TextStyle(color: DS.green, fontSize: 12,
                fontWeight: FontWeight.w600)),
      ])),
    const SizedBox(height: 22),
    Text('Sign, Annotate\n& Edit PDFs\nOnline.',
        style: GoogleFonts.inter(
            color: Colors.white, fontSize: 54,
            fontWeight: FontWeight.w800,
            letterSpacing: -2.2, height: 1.08)),
    const SizedBox(height: 20),
    Text(
        'Professional PDF tools in your browser.\n'
        'Open, annotate, sign with legal compliance,\n'
        'scan, and create documents — entirely offline.',
        style: GoogleFonts.inter(
            color: const Color(0xFF8E8E93), fontSize: 17, height: 1.65)),
    const SizedBox(height: 32),
    Wrap(spacing: 12, runSpacing: 12, children: [
      FilledButton.icon(
        onPressed: onOpenPdf,
        icon: const Icon(Icons.upload_file_rounded, size: 18),
        label: Text('Open a PDF',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
            backgroundColor: DS.indigo,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11)))),
      OutlinedButton.icon(
        onPressed: onOpenApp,
        icon: const Icon(Icons.apps_rounded, size: 18),
        label: Text('All Tools',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF3A3A3C)),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11)))),
    ]),
    const SizedBox(height: 28),
    // Social proof
    Row(children: [
      ...List.generate(5, (_) =>
          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFD600))),
      const SizedBox(width: 8),
      Text('PDF · eSign · Scan · Templates',
          style: TextStyle(color: Colors.white.withOpacity(0.35),
              fontSize: 12)),
    ]),
  ]);

  Widget _dropZone() => DragTarget<Object>(
    onWillAcceptWithDetails: (_) { onDragEnter(); return true; },
    onLeave: (_) => onDragLeave(),
    onAcceptWithDetails: (_) { onDragLeave(); onOpenPdf(); },
    builder: (_, __, ___) => GestureDetector(
      onTap: onOpenPdf,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 300,
        decoration: BoxDecoration(
          color: dragging
              ? DS.indigo.withOpacity(0.1)
              : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: dragging ? DS.indigo : const Color(0xFF3A3A3C),
              width: dragging ? 2 : 1)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedScale(
            scale: dragging ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(width: 76, height: 76,
              decoration: BoxDecoration(
                color: DS.indigo.withOpacity(dragging ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.upload_file_rounded,
                  size: 38, color: DS.indigo))),
          const SizedBox(height: 18),
          Text(dragging ? 'Drop to open!' : 'Click or drag a PDF here',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 17,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(dragging
              ? 'Release to open'
              : 'Regular and password-protected PDFs supported',
              style: const TextStyle(color: Color(0xFF636366), fontSize: 13)),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: onOpenPdf,
            style: OutlinedButton.styleFrom(
                foregroundColor: DS.indigo,
                side: BorderSide(color: DS.indigo.withOpacity(0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
            child: const Text('Browse files',
                style: TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
    ),
  );

    Widget _buildPreviewMockup(bool isWide) {
    return Container(
      width: isWide ? 700 : double.infinity,
      height: 350,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: DS.indigo.withOpacity(0.08), blurRadius: 40)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: [
          // Mock browser bar
          Container(
            height: 36,
            color: const Color(0xFF1C1C1E),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              ...List.generate(3, (i) => Container(
                width: 10, height: 10, margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: [Colors.red, Colors.amber, Colors.green][i],
                  shape: BoxShape.circle,
                ),
              )),
              const Spacer(),
              Container(width: 240, height: 22, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4))),
              const Spacer(),
            ]),
          ),
          // Mock app preview
          Expanded(
            child: Row(children: [
              // Sidebar
              Container(width: 50, decoration: BoxDecoration(color: const Color(0xFF0A0A0F), border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))))),
              // Main content
              Expanded(
                child: Container(
                  color: const Color(0xFFF0F0F0),
                  padding: const EdgeInsets.all(28),
                  child: Column(children: [
                    const SizedBox(height: 20),
                    // Mock PDF page
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 2))],
                        ),
                        child: Column(children: [
                          const SizedBox(height: 50),
                          Container(height: 14, width: 180, color: Colors.grey[200], margin: const EdgeInsets.symmetric(horizontal: 40)),
                          const SizedBox(height: 8),
                          Container(height: 10, width: 120, color: Colors.grey[100], margin: const EdgeInsets.symmetric(horizontal: 40)),
                          const SizedBox(height: 24),
                          // Signature preview
                          Container(height: 40, width: 140, margin: const EdgeInsets.symmetric(horizontal: 40), decoration: BoxDecoration(
                            border: Border.all(color: DS.indigo.withOpacity(0.3), width: 1.5),
                            borderRadius: BorderRadius.circular(6),
                            color: DS.indigo.withOpacity(0.04),
                          )),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Bottom toolbar mock
                    Container(height: 40, decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(5, (_) => Container(width: 24, height: 24, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)))))),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// How It Works — 3 step guide
// ─────────────────────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  final bool isWide;
  const _HowItWorks({required this.isWide});

  static const _steps = [
    (
      icon:  Icons.upload_file_rounded,
      color: DS.indigo,
      step:  '01',
      title: 'Open Your PDF',
      desc:  'Click "Open a PDF" or drag-drop a file. Works with any PDF including password-protected files. Your document stays on your device.',
    ),
    (
      icon:  Icons.edit_rounded,
      color: DS.green,
      step:  '02',
      title: 'Annotate & Edit',
      desc:  'Switch between Edit, Annotate, Fill & Sign tabs. Highlight text, draw, add sticky notes, stamp text, or redact sensitive content.',
    ),
    (
      icon:  Icons.draw_rounded,
      color: DS.purple,
      step:  '03',
      title: 'Sign & Save',
      desc:  'Draw your signature with your finger or mouse. Tap any page to place it. Save the signed PDF or share it directly from the app.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
        horizontal: isWide ? 80 : 24, vertical: 72),
    decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.06)))),
    child: Column(children: [
      _sectionLabel('HOW IT WORKS'),
      const SizedBox(height: 12),
      Text('Three steps to a signed PDF',
          style: GoogleFonts.inter(color: Colors.white,
              fontSize: isWide ? 32 : 24,
              fontWeight: FontWeight.w700, letterSpacing: -0.6)),
      const SizedBox(height: 48),
      isWide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start,
              children: _steps.asMap().entries.map((e) =>
                  Expanded(child: Padding(
                    padding: EdgeInsets.only(right: e.key < 2 ? 24 : 0),
                    child: _StepCard(
                        icon: e.value.icon, color: e.value.color,
                        step: e.value.step, title: e.value.title,
                        desc: e.value.desc)))).toList())
          : Column(children: _steps.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _StepCard(icon: s.icon, color: s.color,
                  step: s.step, title: s.title, desc: s.desc))).toList()),
    ]),
  );
}

class _StepCard extends StatelessWidget {
  final IconData icon; final Color color;
  final String step, title, desc;
  const _StepCard({required this.icon, required this.color,
      required this.step, required this.title, required this.desc});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 24)),
        const Spacer(),
        Text(step, style: TextStyle(color: color.withOpacity(0.35),
            fontSize: 28, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 16),
      Text(title, style: GoogleFonts.inter(color: Colors.white,
          fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(desc, style: const TextStyle(
          color: Color(0xFF8E8E93), fontSize: 14, height: 1.55)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Feature Deep-Dive — interactive tab selector
// ─────────────────────────────────────────────────────────────────────────────

class _FeatureDeepDive extends StatelessWidget {
  final bool isWide;
  final int active;
  final ValueChanged<int> onSelect;
  const _FeatureDeepDive(
      {required this.isWide, required this.active, required this.onSelect});

  static const _features = [
    _FeatureDetail(
      icon: Icons.draw_rounded,
      color: DS.purple,
      label: 'eSignature',
      headline: 'Sign documents with legal validity',
      description:
          'Draw your signature with finger or mouse on the signature canvas. '
          'Choose ink colour, switch to typed signature, or reuse a saved signature. '
          'Tap anywhere on the page to place it — then drag to reposition and pinch-resize. '
          'Supports both full signatures and initials. '
          'Compliant with ESIGN Act (US) and eIDAS Regulation (EU).',
      bullets: [
        'Draw · Type · Reuse saved signatures',
        'Transparent PNG — no white sticker effect',
        'Drag to move, corner handle to resize',
        'Initials mode for quick page sign-off',
        'Multi-party sequential signing (A → B → C)',
        'Role-based: Manager · Legal · Client · Witness',
      ],
      uiPath: 'PDF Viewer → Fill & Sign tab → Sign button',
    ),
    _FeatureDetail(
      icon: Icons.highlight_rounded,
      color: Color(0xFFFFD600),
      label: 'Annotate',
      headline: 'Mark up any PDF without limits',
      description:
          'Switch to the Annotate tab to access the full annotation toolkit. '
          'Drag across text to highlight in yellow, add a blue underline, or strike through. '
          'Switch to Draw mode and sketch freehand ink strokes in any colour. '
          'Add sticky notes that expand on tap, or stamp text anywhere. '
          'All annotations auto-save to a sidecar file and reload when you reopen the PDF.',
      bullets: [
        'Highlight · Underline · Strikethrough',
        'Freehand ink drawing with custom colour',
        'Sticky notes (expandable, amber colour)',
        'Text stamps — tap to place custom text',
        'Undo stack for every annotation',
        'Auto-save sidecar (3s debounce)',
      ],
      uiPath: 'PDF Viewer → Annotate tab',
    ),
    _FeatureDetail(
      icon: Icons.hide_source_rounded,
      color: DS.red,
      label: 'Redaction',
      headline: 'Permanently remove sensitive content',
      description:
          'True black-box redaction — not just a visual overlay. '
          'Switch to the Annotate tab and select Redact. Drag a rectangle over sensitive text '
          'or images. When you save, the page is rasterised first so the underlying text '
          'data is destroyed and cannot be recovered with a PDF reader. '
          'Ideal for legal documents, financial statements, and GDPR compliance.',
      bullets: [
        'TRUE redaction — text data destroyed on save',
        'Page rasterised before black box applied',
        'Cannot be undone after save',
        'Supports multiple redaction boxes per page',
        'Works on images and text equally',
      ],
      uiPath: 'PDF Viewer → Annotate tab → Redact tool',
    ),
    _FeatureDetail(
      icon: Icons.document_scanner_rounded,
      color: DS.green,
      label: 'Scanner',
      headline: 'Scan physical documents to PDF',
      description:
          'Open the Scanner from the home screen. Tap "Scan Page" to capture with your camera. '
          'After capture, a crop tool appears automatically — adjust the corners to frame '
          'the document perfectly. Choose Free, A4, Wide, or Square aspect ratio. '
          'Tap Use to confirm. Add multiple pages, reorder them in the grid, '
          'then tap "Create PDF" to build a PDF and open it directly in the viewer.',
      bullets: [
        'Camera capture with auto-crop UI',
        'Free / A4 / Wide / Square crop modes',
        'B&W mode for cleaner document scans',
        'Multi-page support — 3-column grid preview',
        'Tap page thumbnail to delete it',
        'Opens directly in PDF viewer',
      ],
      uiPath: 'Home → Scan → Camera → Crop → Create PDF',
    ),
    _FeatureDetail(
      icon: Icons.auto_awesome_rounded,
      color: DS.orange,
      label: 'Templates',
      headline: '6 ready-to-fill professional templates',
      description:
          'Open Templates from the home screen or the Settings tab. '
          'Choose a category — All, HR, Legal, or Finance — then tap any template. '
          'Fill in the form fields, upload a company logo for the Invoice, '
          'and tap "Generate PDF". The completed PDF opens directly in the viewer '
          'where you can sign it and share.',
      bullets: [
        'Invoice — with company logo upload',
        'NDA — Non-Disclosure Agreement',
        'Offer Letter — HR onboarding',
        'Purchase Order — Finance',
        'Service Agreement — Legal',
        'Receipt — Finance',
      ],
      uiPath: 'Home → Templates → Fill form → Generate PDF',
    ),
    _FeatureDetail(
      icon: Icons.compare_rounded,
      color: Color(0xFF06B6D4),
      label: 'Compare',
      headline: 'Side-by-side document diff',
      description:
          'Open a PDF and tap the Compare icon in the toolbar (All tab). '
          'Select a second PDF to compare against. Both documents render side-by-side '
          'with synchronised scrolling. A percentage badge in the top bar shows '
          'how different the two documents are based on pixel comparison. '
          'Ideal for reviewing contract revisions.',
      bullets: [
        'Synchronised scroll — both sides move together',
        'Pixel diff percentage shown in top bar',
        'Works with any two PDFs',
        'Thumbnail view of each page',
        'Green badge < 5% diff, orange badge > 5%',
      ],
      uiPath: 'PDF Viewer → All tab → Compare icon',
    ),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
        horizontal: isWide ? 80 : 24, vertical: 72),
    color: const Color(0xFF0D0D0F),
    child: Column(children: [
      _sectionLabel('FEATURES'),
      const SizedBox(height: 12),
      Text('Everything in one place',
          style: GoogleFonts.inter(color: Colors.white,
              fontSize: isWide ? 32 : 24,
              fontWeight: FontWeight.w700, letterSpacing: -0.6)),
      const SizedBox(height: 10),
      const Text('Tap any feature to see how to use it',
          style: TextStyle(color: Color(0xFF636366), fontSize: 15)),
      const SizedBox(height: 40),

      // Tab selector
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _features.asMap().entries.map((e) =>
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: active == e.key
                        ? e.value.color.withOpacity(0.15)
                        : const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: active == e.key
                            ? e.value.color.withOpacity(0.5)
                            : const Color(0xFF2C2C2E))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(e.value.icon, size: 14,
                        color: active == e.key
                            ? e.value.color : const Color(0xFF636366)),
                    const SizedBox(width: 7),
                    Text(e.value.label,
                        style: TextStyle(
                            color: active == e.key
                                ? e.value.color : const Color(0xFF636366),
                            fontSize: 13,
                            fontWeight: active == e.key
                                ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
              ),
            )).toList()),
      ),
      const SizedBox(height: 32),

      // Detail panel
      _FeaturePanel(detail: _features[active], isWide: isWide),
    ]),
  );
}

class _FeatureDetail {
  final IconData icon; final Color color; final String label;
  final String headline, description, uiPath;
  final List<String> bullets;
  const _FeatureDetail({required this.icon, required this.color,
      required this.label, required this.headline,
      required this.description, required this.uiPath,
      required this.bullets});
}

class _FeaturePanel extends StatelessWidget {
  final _FeatureDetail detail; final bool isWide;
  const _FeaturePanel({required this.detail, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5)),
      child: isWide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: _textContent()),
              const SizedBox(width: 40),
              Expanded(flex: 4, child: _mockUI()),
            ])
          : Column(children: [_textContent(), const SizedBox(height: 28), _mockUI()]),
    );
    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(key: ValueKey(detail.label), child: content));
  }

  Widget _textContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 52, height: 52,
      decoration: BoxDecoration(
          color: detail.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14)),
      child: Icon(detail.icon, color: detail.color, size: 26)),
    const SizedBox(height: 18),
    Text(detail.headline, style: GoogleFonts.inter(
        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700,
        letterSpacing: -0.4)),
    const SizedBox(height: 12),
    Text(detail.description, style: const TextStyle(
        color: Color(0xFF8E8E93), fontSize: 14, height: 1.65)),
    const SizedBox(height: 20),
    // Bullets
    ...detail.bullets.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.check_circle_rounded, size: 15,
              color: detail.color.withOpacity(0.7)),
          const SizedBox(width: 10),
          Expanded(child: Text(b, style: const TextStyle(
              color: Colors.white, fontSize: 13, height: 1.4))),
        ]))),
    const SizedBox(height: 20),
    // UI Path
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: detail.color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: detail.color.withOpacity(0.2))),
      child: Row(children: [
        Icon(Icons.route_rounded, size: 13, color: detail.color),
        const SizedBox(width: 8),
        Flexible(child: Text(detail.uiPath, style: TextStyle(
            color: detail.color, fontSize: 12,
            fontWeight: FontWeight.w600))),
      ])),
  ]);

  // Mock UI illustration
  Widget _mockUI() => Container(
    height: 260,
    decoration: BoxDecoration(
        color: const Color(0xFF0D0D0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2E))),
    child: Column(children: [
      // Mock toolbar
      Container(
        height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            border: Border(bottom: BorderSide(color: Color(0xFF2C2C2E)))),
        child: Row(children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                  color: Color(0xFFEF4444), shape: BoxShape.circle)),
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B), shape: BoxShape.circle)),
          Container(width: 8, height: 8,
              decoration: const BoxDecoration(
                  color: DS.green, shape: BoxShape.circle)),
          const Spacer(),
          Text('DocSign — ${detail.label}',
              style: const TextStyle(color: Color(0xFF636366),
                  fontSize: 10, fontWeight: FontWeight.w500)),
          const Spacer(),
        ])),
      // Mock content
      Expanded(child: _mockContent()),
    ]),
  );

  Widget _mockContent() {
    switch (detail.label) {
      case 'eSignature':
        return _MockSignature(color: detail.color);
      case 'Annotate':
        return _MockAnnotate();
      case 'Redaction':
        return _MockRedaction();
      case 'Scanner':
        return _MockScanner(color: detail.color);
      case 'Templates':
        return _MockTemplates(color: detail.color);
      default:
        return _MockCompare();
    }
  }
}

// ── Mock UI screens ───────────────────────────────────────────────────────────

class _MockSignature extends StatelessWidget {
  final Color color;
  const _MockSignature({required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Simulated document
      Container(height: 4, color: Colors.white.withOpacity(0.08),
          margin: const EdgeInsets.only(bottom: 6)),
      Container(height: 4, width: 180, color: Colors.white.withOpacity(0.05),
          margin: const EdgeInsets.only(bottom: 6)),
      Container(height: 4, color: Colors.white.withOpacity(0.08),
          margin: const EdgeInsets.only(bottom: 6)),
      const SizedBox(height: 16),
      // Signature box
      Container(
        height: 80, width: double.infinity,
        decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
            borderRadius: BorderRadius.circular(8),
            color: color.withOpacity(0.04)),
        child: Stack(children: [
          Center(child: Text('John Smith',
              style: TextStyle(color: color, fontSize: 26,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w300))),
          Positioned(right: 6, bottom: 4,
            child: Row(children: [
              Container(width: 6, height: 6,
                  decoration: BoxDecoration(
                      color: DS.green, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('ESIGN compliant', style: TextStyle(
                  color: DS.green, fontSize: 8)),
            ])),
        ])),
      const SizedBox(height: 10),
      // Toolbar chips
      Row(children: [
        _chip('Draw', color, true),
        const SizedBox(width: 6),
        _chip('Type', Colors.white30, false),
        const SizedBox(width: 6),
        _chip('Initials', Colors.white30, false),
      ]),
    ]),
  );
  Widget _chip(String l, Color c, bool a) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: a ? c.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: a ? c.withOpacity(0.4) : Colors.white12)),
    child: Text(l, style: TextStyle(color: a ? c : Colors.white30, fontSize: 10)));
}

class _MockAnnotate extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Highlighted text
      RichText(text: const TextSpan(
          style: TextStyle(fontSize: 11, height: 1.7, color: Color(0xFF8E8E93)),
          children: [
            TextSpan(text: 'This Agreement is entered into by '),
            TextSpan(text: 'ContractMind Inc.',
                style: TextStyle(backgroundColor: Color(0x55FFD600),
                    color: Colors.white)),
            TextSpan(text: ' and the Client.\n'),
            TextSpan(text: 'Payment terms: '),
            TextSpan(text: 'Net 30 days',
                style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF38BDF8),
                    color: Colors.white)),
            TextSpan(text: ' from invoice date.\nAll fees are non-refundable.'),
          ])),
      const SizedBox(height: 12),
      // Sticky note
      Container(
        padding: const EdgeInsets.all(8), width: 110,
        decoration: BoxDecoration(
            color: const Color(0xFFFB923C).withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: const Color(0xFFFB923C).withOpacity(0.4))),
        child: const Text('Review with legal team before signing',
            style: TextStyle(color: Color(0xFFFB923C), fontSize: 9,
                height: 1.4))),
    ]),
  );
}

class _MockRedaction extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Employee Details:', style: TextStyle(
          color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 8),
      Row(children: [
        const Text('Name: ', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 11)),
        Container(width: 90, height: 14,
            decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(2))),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        const Text('SSN: ', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 11)),
        Container(width: 70, height: 14,
            decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(2))),
      ]),
      const SizedBox(height: 6),
      const Text('Salary: \$85,000/year',
          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 11)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: DS.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: DS.red.withOpacity(0.3))),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_user_rounded, color: DS.red, size: 11),
          SizedBox(width: 5),
          Text('Text data permanently destroyed',
              style: TextStyle(color: DS.red, fontSize: 9)),
        ])),
    ]),
  );
}

class _MockScanner extends StatelessWidget {
  final Color color;
  const _MockScanner({required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(children: [
      // Grid of scanned pages
      Row(children: [
        _page('p.1', color), const SizedBox(width: 8),
        _page('p.2', color), const SizedBox(width: 8),
        _page('p.3', color),
      ]),
      const SizedBox(height: 12),
      // Create PDF button
      Container(
        width: double.infinity, height: 34,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(8)),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text('Create PDF', style: TextStyle(color: Colors.white,
              fontSize: 12, fontWeight: FontWeight.w700)),
        ])),
    ]),
  );
  Widget _page(String label, Color c) => Expanded(child: Container(
    height: 90,
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.3))),
    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Container(margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: Colors.black45,
            borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 9))),
    ])));
}

class _MockTemplates extends StatelessWidget {
  final Color color;
  const _MockTemplates({required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _tpl(Icons.receipt_long_rounded, 'Invoice', DS.indigo),
        const SizedBox(width: 8),
        _tpl(Icons.gavel_rounded, 'NDA', DS.orange),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _tpl(Icons.mail_rounded, 'Offer', DS.purple),
        const SizedBox(width: 8),
        _tpl(Icons.shopping_cart_rounded, 'PO', DS.indigo),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Text('Fill form → Generate PDF → Sign',
            style: TextStyle(color: color, fontSize: 9,
                fontWeight: FontWeight.w600))),
    ]),
  );
  Widget _tpl(IconData icon, String label, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withOpacity(0.2))),
      child: Row(children: [
        Icon(icon, color: c, size: 14),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c, fontSize: 10,
            fontWeight: FontWeight.w600)),
      ])));
}

class _MockCompare extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(children: [
      Expanded(child: Column(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: DS.indigo.withOpacity(0.1),
          child: const Text('Original', style: TextStyle(
              color: DS.indigo, fontSize: 9))),
        const SizedBox(height: 6),
        ...List.generate(4, (_) => Container(
            height: 4, margin: const EdgeInsets.only(bottom: 5),
            color: Colors.white.withOpacity(0.08))),
      ])),
      Container(width: 1, color: const Color(0xFF2C2C2E)),
      Expanded(child: Column(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: DS.orange.withOpacity(0.1),
          child: const Text('Modified', style: TextStyle(
              color: DS.orange, fontSize: 9))),
        const SizedBox(height: 6),
        Container(height: 4, margin: const EdgeInsets.only(bottom: 5),
            color: Colors.white.withOpacity(0.08)),
        Container(height: 4, margin: const EdgeInsets.only(bottom: 5),
            color: DS.orange.withOpacity(0.25)),
        Container(height: 4, margin: const EdgeInsets.only(bottom: 5),
            color: Colors.white.withOpacity(0.08)),
        Container(height: 4, margin: const EdgeInsets.only(bottom: 5),
            color: Colors.white.withOpacity(0.08)),
      ])),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// eSign Compliance Section
// ─────────────────────────────────────────────────────────────────────────────

class _ESignSection extends StatelessWidget {
  final bool isWide;
  const _ESignSection({required this.isWide});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
        horizontal: isWide ? 80 : 24, vertical: 72),
    decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06)))),
    child: Column(children: [
      _sectionLabel('LEGAL COMPLIANCE'),
      const SizedBox(height: 12),
      Text('Enterprise-grade eSignature compliance',
          style: GoogleFonts.inter(color: Colors.white,
              fontSize: isWide ? 32 : 24,
              fontWeight: FontWeight.w700, letterSpacing: -0.6),
          textAlign: TextAlign.center),
      const SizedBox(height: 12),
      const Text(
          'Every signature is backed by a cryptographic audit trail',
          style: TextStyle(color: Color(0xFF636366), fontSize: 15),
          textAlign: TextAlign.center),
      const SizedBox(height: 44),
      Wrap(spacing: 16, runSpacing: 16,
          alignment: WrapAlignment.center,
          children: const [
        _ComplianceBadge(
            icon: Icons.gavel_rounded, color: DS.indigo,
            title: 'ESIGN Act (US)',
            desc: '15 U.S.C. § 7001\nElectronic Signatures in Global\nand National Commerce'),
        _ComplianceBadge(
            icon: Icons.euro_rounded, color: DS.purple,
            title: 'eIDAS (EU)',
            desc: 'Regulation (EU) No 910/2014\nAdvanced Electronic\nSignature (AdES)'),
        _ComplianceBadge(
            icon: Icons.fingerprint_rounded, color: DS.green,
            title: 'SHA-256 Hashing',
            desc: 'Document hash computed\nbefore and after signing\nfor tamper detection'),
        _ComplianceBadge(
            icon: Icons.timeline_rounded, color: DS.orange,
            title: 'Full Audit Trail',
            desc: 'Signer name · Email\nTimestamp · Device · IP\nexported with every PDF'),
        _ComplianceBadge(
            icon: Icons.people_rounded, color: DS.red,
            title: 'Sequential Signing',
            desc: 'Define A → B → C order\nNext signer unlocks only\nafter previous signs'),
        _ComplianceBadge(
            icon: Icons.badge_rounded, color: Color(0xFF06B6D4),
            title: 'Role-Based',
            desc: 'Manager · Legal · Client\nWitness · Notary\nCustom role labels'),
      ]),
    ]),
  );
}

class _ComplianceBadge extends StatelessWidget {
  final IconData icon; final Color color;
  final String title, desc;
  const _ComplianceBadge({required this.icon, required this.color,
      required this.title, required this.desc});
  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 40, height: 40,
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20)),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(color: Colors.white,
          fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(desc, style: const TextStyle(color: Color(0xFF636366),
          fontSize: 11, height: 1.5)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Templates Showcase
// ─────────────────────────────────────────────────────────────────────────────

class _TemplatesSection extends StatelessWidget {
  final bool isWide; final VoidCallback onOpenApp;
  const _TemplatesSection({required this.isWide, required this.onOpenApp});

  static const _tpls = [
    (Icons.receipt_long_rounded, 'Invoice', 'Finance', DS.indigo,
        'Company logo · Line items · Tax · Payment terms'),
    (Icons.gavel_rounded, 'NDA', 'Legal', DS.orange,
        'Mutual or one-way · Custom duration · Governing law'),
    (Icons.mail_rounded, 'Offer Letter', 'HR', DS.purple,
        'Salary · Start date · Benefits · Reporting to'),
    (Icons.shopping_cart_rounded, 'Purchase Order', 'Finance', DS.green,
        'Vendor details · Line items · Delivery · PO number'),
    (Icons.handshake_rounded, 'Service Agreement', 'Legal', DS.indigo,
        'Scope · Milestones · Payment · Termination clauses'),
    (Icons.receipt_rounded, 'Receipt', 'Finance', DS.orange,
        'Items · Subtotal · Tax · Payment method'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
        horizontal: isWide ? 80 : 24, vertical: 72),
    color: const Color(0xFF0D0D0F),
    child: Column(children: [
      _sectionLabel('TEMPLATES'),
      const SizedBox(height: 12),
      Text('Fill a form. Get a PDF.',
          style: GoogleFonts.inter(color: Colors.white,
              fontSize: isWide ? 32 : 24,
              fontWeight: FontWeight.w700, letterSpacing: -0.6)),
      const SizedBox(height: 10),
      const Text('6 professional templates ready to use',
          style: TextStyle(color: Color(0xFF636366), fontSize: 15)),
      const SizedBox(height: 40),
      Wrap(spacing: 12, runSpacing: 12,
          alignment: WrapAlignment.center,
          children: _tpls.map((t) => _TplCard(
              icon: t.$1, title: t.$2, category: t.$3,
              color: t.$4, desc: t.$5)).toList()),
      const SizedBox(height: 36),
      FilledButton.icon(
        onPressed: onOpenApp,
        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
        label: const Text('Open Templates',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        style: FilledButton.styleFrom(
            backgroundColor: DS.orange,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)))),
    ]),
  );
}

class _TplCard extends StatelessWidget {
  final IconData icon; final String title, category, desc; final Color color;
  const _TplCard({required this.icon, required this.title, required this.category,
      required this.desc, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 260,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Text(category, style: TextStyle(color: color,
              fontSize: 10, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(color: Colors.white,
          fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(desc, style: const TextStyle(color: Color(0xFF636366),
          fontSize: 11, height: 1.45)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ContractMind CTA
// ─────────────────────────────────────────────────────────────────────────────

class _ContractMindCta extends StatelessWidget {
  final Future<void> Function(String) onLaunch;
  final VoidCallback onOpenApp;
  const _ContractMindCta({required this.onLaunch, required this.onOpenApp});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
    decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [DS.indigo.withOpacity(0.18), DS.purple.withOpacity(0.10)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border(top: BorderSide(
            color: Colors.white.withOpacity(0.06)))),
    child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
            color: DS.indigo.withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DS.indigo.withOpacity(0.4))),
        child: const Text('Powered by ContractMind',
            style: TextStyle(color: DS.indigo, fontSize: 12,
                fontWeight: FontWeight.w600))),
      const SizedBox(height: 20),
      Text('Need AI-powered\ncontract management?',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 30,
              fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15),
          textAlign: TextAlign.center),
      const SizedBox(height: 14),
      const Text(
          'ContractMind adds AI intelligence on top of DocSign —\n'
          'automated workflows, team collaboration, and contract analytics.',
          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15, height: 1.6),
          textAlign: TextAlign.center),
      const SizedBox(height: 32),
      Wrap(spacing: 12, runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
        FilledButton.icon(
          onPressed: () => onLaunch('https://www.contractmind.ai'),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Visit contractmind.ai →',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
              backgroundColor: DS.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)))),
        OutlinedButton(
          onPressed: onOpenApp,
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF3A3A3C)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          child: const Text('Use DocSign Free →',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      ]),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final Future<void> Function(String) onLaunch;
  const _Footer({required this.onLaunch});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
    decoration: BoxDecoration(
        border: Border(top: BorderSide(
            color: Colors.white.withOpacity(0.06)))),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Image.asset('icons/logo.png', width: 30, height: 30),
        const SizedBox(width: 7),
        const Text('DocSign',
            style: TextStyle(color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 12),
      Text('© 2026 DocSign by ContractMind. 100% offline PDF tools.',
          style: const TextStyle(color: Color(0xFF48484A), fontSize: 12),
          textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _flink('Privacy Policy', () => Navigator.push(context as BuildContext, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()))),
        const SizedBox(width: 20),
        _flink('contractmind.ai',
            () => onLaunch('https://www.contractmind.ai')),
        const SizedBox(width: 20),
        _flink('pdf.contractmind.ai', () {}),
      ]),
    ]),
  );

  Widget _flink(String l, VoidCallback t) => GestureDetector(
    onTap: t,
    child: Text(l, style: const TextStyle(
        color: Color(0xFF636366), fontSize: 12,
        fontWeight: FontWeight.w500)));
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _sectionLabel(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
  decoration: BoxDecoration(
      color: DS.indigo.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: DS.indigo.withOpacity(0.3))),
  child: Text(text, style: const TextStyle(
      color: DS.indigo, fontSize: 11,
      fontWeight: FontWeight.w700, letterSpacing: 1.2)));
