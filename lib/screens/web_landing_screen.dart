// lib/screens/web_landing_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pdf_loader.dart';
import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import 'home_screen.dart';
import 'pdf_viewer_screen.dart';
import 'privacy_policy_screen.dart';

class WebLandingScreen extends StatefulWidget {
  const WebLandingScreen({super.key});
  @override
  State<WebLandingScreen> createState() => _WebLandingState();
}

class _WebLandingState extends State<WebLandingScreen> with SingleTickerProviderStateMixin {
  bool _dragging = false;
  int _activeFeature = 0;
  final _scrollController = ScrollController();

  Future<void> _openPdf() async {
    try {
      final result = await PdfLoader.pick();
      if (result == null || !mounted) return;
      if (result.bytes != null) {
        PlatformFileService.cache(result.displayPath, result.bytes!);
      }
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => PdfViewerScreen(filePath: result.displayPath, preloadedBytes: result.bytes)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: DS.red));
    }
  }

  void _openApp() => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
    }
  }

  final _heroKey = GlobalKey();
  final _featuresKey = GlobalKey();
  final _complianceKey = GlobalKey();
  final _templatesKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 900;
    final isMid = w > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Navbar
                    _Navbar(
                      isWide: isWide,
                      onOpenPdf: _openPdf,
                      onOpenApp: _openApp,
                      onLaunch: _launch,
                      onScrollTo: _scrollToSection,
                      heroKey: _heroKey,
                      featuresKey: _featuresKey,
                      complianceKey: _complianceKey,
                      templatesKey: _templatesKey,
                    ),
                    // Hero Section (now accepts key)
                    _HeroSection(
                      key: _heroKey,
                      isWide: isWide,
                      onOpenPdf: _openPdf,
                      onOpenApp: _openApp,
                      dragging: _dragging,
                      onDragEnter: () => setState(() => _dragging = true),
                      onDragLeave: () => setState(() => _dragging = false),
                    ),
                    // How It Works
                    _HowItWorks(isWide: isWide),
                    // Feature Deep Dive
                    _FeatureDeepDive(
                      key: _featuresKey,
                      isWide: isWide,
                      active: _activeFeature,
                      onSelect: (i) => setState(() => _activeFeature = i),
                    ),
                    // eSign Compliance
                    _ESignSection(key: _complianceKey, isWide: isWide),
                    // Templates Showcase
                    _TemplatesSection(key: _templatesKey, isWide: isWide, onOpenApp: _openApp),
                    // ContractMind CTA
                    _ContractMindCta(onLaunch: _launch, onOpenApp: _openApp),
                    // Footer
                    _Footer(onLaunch: _launch),
                  ],
                ),
              ),
            ),
          ),
          // Sticky CTA (floating buttons)
          Positioned(
            bottom: 24,
            right: 24,
            child: _StickyCta(onOpenPdf: _openPdf, onOpenApp: _openApp),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Navbar
// ============================================================
class _Navbar extends StatelessWidget {
  final bool isWide;
  final VoidCallback onOpenPdf, onOpenApp;
  final Future<void> Function(String) onLaunch;
  final void Function(GlobalKey) onScrollTo;
  final GlobalKey heroKey, featuresKey, complianceKey, templatesKey;

  const _Navbar({required this.isWide, required this.onOpenPdf, required this.onOpenApp, required this.onLaunch,
    required this.onScrollTo, required this.heroKey, required this.featuresKey, required this.complianceKey,
    required this.templatesKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [DS.indigo, Color(0xFF8B5CF6)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.description_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('DocSign', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const Spacer(),
          if (isWide) ...[
            _navLink('Features', () => onScrollTo(featuresKey)),
            const SizedBox(width: 16),
            _navLink('Legal', () => onScrollTo(complianceKey)),
            const SizedBox(width: 16),
            _navLink('Templates', () => onScrollTo(templatesKey)),
            const SizedBox(width: 24),
          ],
          OutlinedButton(
            onPressed: () => onLaunch('https://www.contractmind.ai'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withOpacity(0.15)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('ContractMind', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onOpenApp,
            style: FilledButton.styleFrom(
              backgroundColor: DS.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Open App', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _navLink(String label, VoidCallback onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(foregroundColor: Colors.white70, padding: const EdgeInsets.symmetric(horizontal: 8)),
    child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
  );
}

// ============================================================
// Hero Section (now accepts key)
// ============================================================
class _HeroSection extends StatelessWidget {
  final bool isWide, dragging;
  final VoidCallback onOpenPdf, onOpenApp, onDragEnter, onDragLeave;

  const _HeroSection({
    super.key,
    required this.isWide,
    required this.onOpenPdf,
    required this.onOpenApp,
    required this.dragging,
    required this.onDragEnter,
    required this.onDragLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 24, vertical: isWide ? 80 : 48),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [DS.indigo.withOpacity(0.12), Colors.transparent],
        ),
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _heroText()),
                const SizedBox(width: 48),
                Expanded(child: _dropZone()),
              ],
            )
          : Column(
              children: [
                _heroText(),
                const SizedBox(height: 48),
                _dropZone(),
              ],
            ),
    );
  }

  Widget _heroText() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Trust badge
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: DS.green.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DS.green.withOpacity(0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 12, color: DS.green),
            SizedBox(width: 6),
            Text('100% Offline · No Uploads · Zero Tracking',
                style: TextStyle(color: DS.green, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'Sign, Annotate\n& Edit PDFs\nOffline.',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: isWide ? 52 : 38,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.8,
          height: 1.08,
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'Professional PDF tools that never send your files to the cloud.\n'
        'Open, annotate, sign with legal compliance, scan, and create documents — all on your device.',
        style: GoogleFonts.inter(color: const Color(0xFF8E8E93), fontSize: 16, height: 1.6),
      ),
      const SizedBox(height: 32),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: onOpenPdf,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Open a PDF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: DS.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onOpenApp,
            icon: const Icon(Icons.apps_rounded, size: 18),
            label: const Text('All Tools', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF3A3A3C)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 32),
      Row(
        children: [
          ...List.generate(5, (_) => const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFD600))),
          const SizedBox(width: 8),
          Text('Legal, HR & Finance ready — no account required',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12)),
        ],
      ),
    ],
  );

  Widget _dropZone() => DragTarget<Object>(
    onWillAcceptWithDetails: (_) { onDragEnter(); return true; },
    onLeave: (_) => onDragLeave(),
    onAcceptWithDetails: (_) { onDragLeave(); onOpenPdf(); },
    builder: (_, __, ___) => GestureDetector(
      onTap: onOpenPdf,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 320,
        decoration: BoxDecoration(
          color: dragging ? DS.indigo.withOpacity(0.08) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: dragging ? DS.indigo : const Color(0xFF3A3A3C), width: dragging ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: dragging ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: DS.indigo.withOpacity(dragging ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.upload_file_rounded, size: 36, color: DS.indigo),
              ),
            ),
            const SizedBox(height: 18),
            Text(dragging ? 'Drop to open!' : 'Click or drag a PDF here',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(dragging ? 'Release to open' : 'Regular and password-protected PDFs supported',
                style: const TextStyle(color: Color(0xFF636366), fontSize: 13)),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onOpenPdf,
              style: OutlinedButton.styleFrom(
                foregroundColor: DS.indigo,
                side: BorderSide(color: DS.indigo.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Browse files', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================================
// How It Works
// ============================================================
class _HowItWorks extends StatelessWidget {
  final bool isWide;
  const _HowItWorks({required this.isWide});

  static const _steps = [
    ('Open PDF', 'Drag, click, or browse – your file stays local.', Icons.upload_file_rounded, DS.indigo),
    ('Annotate & Sign', 'Highlight, draw, add notes, and place e-signatures.', Icons.edit_rounded, DS.green),
    ('Save or Share', 'Export PDF, share, or print – all offline.', Icons.save_rounded, DS.purple),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 24, vertical: 72),
      child: Column(
        children: [
          _sectionLabel('HOW IT WORKS'),
          const SizedBox(height: 12),
          Text('Three steps to a signed PDF',
              style: GoogleFonts.inter(color: Colors.white, fontSize: isWide ? 32 : 24, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
          const SizedBox(height: 48),
          isWide
              ? Row(
                  children: _steps.asMap().entries.map((e) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: e.key < 2 ? 24 : 0),
                      child: _StepCard(step: e.key + 1, title: e.value.$1, desc: e.value.$2, icon: e.value.$3, color: e.value.$4),
                    ),
                  )).toList(),
                )
              : Column(
                  children: _steps.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _StepCard(step: _steps.indexOf(s) + 1, title: s.$1, desc: s.$2, icon: s.$3, color: s.$4),
                  )).toList(),
                ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int step; final String title, desc; final IconData icon; final Color color;
  const _StepCard({required this.step, required this.title, required this.desc, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF2C2C2E)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 24),
            ),
            const Spacer(),
            Text('0$step', style: TextStyle(color: color.withOpacity(0.3), fontSize: 28, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(desc, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13, height: 1.55)),
      ],
    ),
  );
}

// ============================================================
// Feature Deep Dive (accepts key)
// ============================================================
class _FeatureDeepDive extends StatelessWidget {
  final bool isWide;
  final int active;
  final ValueChanged<int> onSelect;
  const _FeatureDeepDive({super.key, required this.isWide, required this.active, required this.onSelect});

  static const _features = [
    ('eSignature', Icons.draw_rounded, DS.purple,
     'Legally binding signatures with full audit trail. Draw, type, or reuse saved signatures – place anywhere, drag to move, pinch to resize. Supports sequential signing and role-based approval.',
     ['ESIGN Act & eIDAS compliant', 'Role-based: Manager, Legal, Client', 'Full audit trail exported with PDF']),
    ('Annotation', Icons.highlight_rounded, Color(0xFFFFD600),
     'Mark up PDFs with highlight, underline, strikethrough, freehand ink, and sticky notes. Auto-save to sidecar file, undo stack, all offline.',
     ['Highlight, underline, strikethrough', 'Freehand drawing with custom colors', 'Expandable sticky notes']),
    ('Redaction', Icons.hide_source_rounded, DS.red,
     'Permanently remove sensitive text and images. True redaction – the page is rasterized before black box is applied, so underlying data is destroyed.',
     ['Text data permanently removed', 'Cannot be undone after save', 'Multiple boxes per page']),
    ('Scanner', Icons.document_scanner_rounded, DS.green,
     'Scan physical documents to PDF. Camera capture with manual crop, multi-page support, B&W mode, and direct open in viewer.',
     ['Crop with free/A4/wide/square modes', 'Multi-page scanning', 'Opens directly in PDF viewer']),
    ('Templates', Icons.auto_awesome_rounded, DS.orange,
     'Fill ready-to-use templates: Invoice, NDA, Offer Letter, Purchase Order, Service Agreement, Receipt. Custom logo support.',
     ['6 professional templates', 'Fill and generate PDF instantly', 'Company logo upload for invoices']),
    ('Compare', Icons.compare_rounded, const Color(0xFF06B6D4),
     'Side-by-side document diff with synchronised scrolling. Pixel diff percentage shows how much changed between two PDFs.',
     ['Synchronised scroll', 'Percentage diff badge', 'Ideal for contract reviews']),
  ];

  @override
  Widget build(BuildContext context) {
    final feature = _features[active];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 24, vertical: 72),
      color: const Color(0xFF0D0D0F),
      child: Column(
        children: [
          _sectionLabel('FEATURES'),
          const SizedBox(height: 12),
          Text('Everything in one place',
              style: GoogleFonts.inter(color: Colors.white, fontSize: isWide ? 32 : 24, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
          const SizedBox(height: 40),
          // Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _features.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FeatureTab(
                  label: e.value.$1,
                  icon: e.value.$2,
                  color: e.value.$3,
                  active: active == e.key,
                  onTap: () => onSelect(e.key),
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 32),
          // Detail panel
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2C2C2E)),
            ),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: _FeatureDetail(feature: feature)),
                      const SizedBox(width: 40),
                      Expanded(flex: 4, child: _FeatureMock(feature: feature.$1, color: feature.$3)),
                    ],
                  )
                : Column(
                    children: [
                      _FeatureDetail(feature: feature),
                      const SizedBox(height: 28),
                      _FeatureMock(feature: feature.$1, color: feature.$3),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTab extends StatelessWidget {
  final String label; final IconData icon; final Color color; final bool active; final VoidCallback onTap;
  const _FeatureTab({required this.label, required this.icon, required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.12) : const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: active ? color.withOpacity(0.5) : const Color(0xFF2C2C2E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: active ? color : const Color(0xFF636366)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: active ? color : const Color(0xFF636366), fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    ),
  );
}

class _FeatureDetail extends StatelessWidget {
  final (String, IconData, Color, String, List<String>) feature;
  const _FeatureDetail({required this.feature});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(feature.$1, style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
      const SizedBox(height: 16),
      Text(feature.$4, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, height: 1.65)),
      const SizedBox(height: 24),
      ...feature.$5.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 16, color: feature.$3.withOpacity(0.7)),
            const SizedBox(width: 10),
            Expanded(child: Text(b, style: const TextStyle(color: Colors.white, fontSize: 13))),
          ],
        ),
      )),
    ],
  );
}

class _FeatureMock extends StatelessWidget {
  final String feature; final Color color;
  const _FeatureMock({required this.feature, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    height: 240,
    decoration: BoxDecoration(
      color: const Color(0xFF0D0D0F),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF2C2C2E)),
    ),
    child: Column(
      children: [
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            border: Border(bottom: BorderSide(color: Color(0xFF2C2C2E))),
          ),
          child: Row(
            children: List.generate(3, (i) => Container(
              width: 10, height: 10, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: [Colors.red, Colors.amber, DS.green][i], shape: BoxShape.circle),
            )),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _mockContent(feature, color),
          ),
        ),
      ],
    ),
  );

  Widget _mockContent(String feature, Color color) {
    switch (feature) {
      case 'eSignature':
        return Column(
          children: [
            Container(height: 4, width: 180, color: Colors.white.withOpacity(0.08)),
            const SizedBox(height: 8),
            Container(height: 4, width: 120, color: Colors.white.withOpacity(0.05)),
            const SizedBox(height: 20),
            Container(
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(color: color.withOpacity(0.5), width: 1.5),
                borderRadius: BorderRadius.circular(8),
                color: color.withOpacity(0.04),
              ),
              child: Center(child: Text('John Smith', style: TextStyle(color: color, fontSize: 22, fontStyle: FontStyle.italic))),
            ),
          ],
        );
      case 'Annotation':
        return Column(
          children: [
            Text('This is a highlighted text', style: TextStyle(backgroundColor: color.withOpacity(0.4), color: Colors.white)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFB923C).withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
              child: const Text('Review with legal team', style: TextStyle(color: Color(0xFFFB923C), fontSize: 10)),
            ),
          ],
        );
      case 'Redaction':
        return Column(
          children: [
            const Text('Employee Details:', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('SSN: ', style: TextStyle(color: Color(0xFF8E8E93))),
                Container(width: 80, height: 14, color: Colors.black),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: DS.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_user_rounded, color: DS.red, size: 11),
                SizedBox(width: 4),
                Text('Data permanently destroyed', style: TextStyle(color: DS.red, fontSize: 9)),
              ]),
            ),
          ],
        );
      default:
        return Center(child: Icon(Icons.image, color: color.withOpacity(0.4)));
    }
  }
}

// ============================================================
// eSign Compliance (accepts key)
// ============================================================
class _ESignSection extends StatelessWidget {
  final bool isWide;
  const _ESignSection({super.key, required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 24, vertical: 72),
      child: Column(
        children: [
          _sectionLabel('LEGAL COMPLIANCE'),
          const SizedBox(height: 12),
          Text('Enterprise-grade eSignature compliance',
              style: GoogleFonts.inter(color: Colors.white, fontSize: isWide ? 32 : 24, fontWeight: FontWeight.w700, letterSpacing: -0.6),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text('Every signature is backed by a cryptographic audit trail',
              style: const TextStyle(color: Color(0xFF636366), fontSize: 15), textAlign: TextAlign.center),
          const SizedBox(height: 48),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: const [
              _ComplianceCard(icon: Icons.gavel_rounded, color: DS.indigo, title: 'ESIGN Act (US)', desc: '15 U.S.C. § 7001\nElectronic Signatures in Global\nand National Commerce'),
              _ComplianceCard(icon: Icons.euro_rounded, color: DS.purple, title: 'eIDAS (EU)', desc: 'Regulation (EU) No 910/2014\nAdvanced Electronic\nSignature (AdES)'),
              _ComplianceCard(icon: Icons.fingerprint_rounded, color: DS.green, title: 'SHA-256 Hashing', desc: 'Document hash computed\nbefore and after signing\nfor tamper detection'),
              _ComplianceCard(icon: Icons.timeline_rounded, color: DS.orange, title: 'Full Audit Trail', desc: 'Signer name · Email\nTimestamp · Device · IP\nexported with every PDF'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComplianceCard extends StatelessWidget {
  final IconData icon; final Color color; final String title, desc;
  const _ComplianceCard({required this.icon, required this.color, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) => Container(
    width: 260,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2C2C2E)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(desc, style: const TextStyle(color: Color(0xFF636366), fontSize: 11, height: 1.5)),
      ],
    ),
  );
}

// ============================================================
// Templates Showcase (accepts key)
// ============================================================
class _TemplatesSection extends StatelessWidget {
  final bool isWide;
  final VoidCallback onOpenApp;
  const _TemplatesSection({super.key, required this.isWide, required this.onOpenApp});

  static const _templates = [
    ('Invoice', Icons.receipt_long_rounded, DS.indigo, 'Company logo · Line items · Tax'),
    ('NDA', Icons.gavel_rounded, DS.orange, 'Mutual · Duration · Governing law'),
    ('Offer Letter', Icons.mail_rounded, DS.purple, 'Salary · Start date · Benefits'),
    ('Purchase Order', Icons.shopping_cart_rounded, DS.green, 'Vendor · PO number · Delivery'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 24, vertical: 72),
      color: const Color(0xFF0D0D0F),
      child: Column(
        children: [
          _sectionLabel('TEMPLATES'),
          const SizedBox(height: 12),
          Text('Fill a form. Get a PDF.',
              style: GoogleFonts.inter(color: Colors.white, fontSize: isWide ? 32 : 24, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
          const SizedBox(height: 40),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: _templates.map((t) => _TemplateCard(
              title: t.$1, icon: t.$2, color: t.$3, desc: t.$4,
            )).toList(),
          ),
          const SizedBox(height: 48),
          FilledButton.icon(
            onPressed: onOpenApp,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Open Templates', style: TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: DS.orange,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final String title, desc; final IconData icon; final Color color;
  const _TemplateCard({required this.title, required this.desc, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 240,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF2C2C2E)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(desc, style: const TextStyle(color: Color(0xFF636366), fontSize: 11, height: 1.45)),
      ],
    ),
  );
}

// ============================================================
// ContractMind CTA
// ============================================================
class _ContractMindCta extends StatelessWidget {
  final Future<void> Function(String) onLaunch;
  final VoidCallback onOpenApp;
  const _ContractMindCta({required this.onLaunch, required this.onOpenApp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [DS.indigo.withOpacity(0.12), DS.purple.withOpacity(0.08)]),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: DS.indigo.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DS.indigo.withOpacity(0.4)),
            ),
            child: const Text('Powered by ContractMind', style: TextStyle(color: DS.indigo, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          Text('Need AI-powered contract management?',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const Text('ContractMind adds AI intelligence on top of DocSign — automated workflows, team collaboration, and analytics.',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => onLaunch('https://www.contractmind.ai'),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Visit contractmind.ai →', style: TextStyle(fontSize: 14)),
                style: FilledButton.styleFrom(
                  backgroundColor: DS.indigo,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              OutlinedButton(
                onPressed: onOpenApp,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF3A3A3C)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Use DocSign Free →', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Footer
// ============================================================
class _Footer extends StatelessWidget {
  final Future<void> Function(String) onLaunch;
  const _Footer({required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06)))),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description_rounded, color: Colors.white54, size: 24),
              SizedBox(width: 8),
              Text('DocSign', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Text('© 2026 DocSign by ContractMind. 100% offline PDF tools.',
              style: const TextStyle(color: Color(0xFF48484A), fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _footerLink('Privacy Policy', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()))),
              const SizedBox(width: 20),
              _footerLink('contractmind.ai', () => onLaunch('https://www.contractmind.ai')),
              const SizedBox(width: 20),
              _footerLink('pdf.contractmind.ai', () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footerLink(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Text(label, style: const TextStyle(color: Color(0xFF636366), fontSize: 12, fontWeight: FontWeight.w500)),
  );
}

// ============================================================
// Sticky CTA
// ============================================================
class _StickyCta extends StatelessWidget {
  final VoidCallback onOpenPdf, onOpenApp;
  const _StickyCta({required this.onOpenPdf, required this.onOpenApp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DS.bgCard,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: DS.separatorLight),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stickyButton('Open PDF', Icons.upload_file_rounded, onOpenPdf),
          const SizedBox(width: 8),
          _stickyButton('Open App', Icons.apps_rounded, onOpenApp, primary: true),
        ],
      ),
    );
  }

  Widget _stickyButton(String label, IconData icon, VoidCallback onTap, {bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: primary ? DS.indigo : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: primary ? null : Border.all(color: DS.separatorLight),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: primary ? Colors.white : DS.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: primary ? Colors.white : DS.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Helpers
// ============================================================
Widget _sectionLabel(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
  decoration: BoxDecoration(
    color: DS.indigo.withOpacity(0.1),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: DS.indigo.withOpacity(0.3)),
  ),
  child: Text(text, style: const TextStyle(color: DS.indigo, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
);