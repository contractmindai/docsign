import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/ds.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static void show(BuildContext context) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        surfaceTintColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('Privacy Policy', style: GoogleFonts.inter(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _header('DocSign Privacy Policy'),
          _meta('Last updated: April 2026'),
          const SizedBox(height: 24),

          _section('1. Overview',
              'DocSign is a 100% offline document annotation, signing, and scanning app. '
              'We do not collect, store, or transmit any personal data to external servers. '
              'All your documents, signatures, and annotations remain on your device.'),

          _section('2. Data We Collect',
              'DocSign does NOT collect:\n'
              '• Personal information (name, email, address)\n'
              '• Document content or metadata\n'
              '• Usage analytics or crash reports\n'
              '• Location data\n'
              '• Contacts or calendar data\n\n'
              'All app data (documents, annotations, signatures) is stored locally '
              'on your device in the app\'s private storage directory.'),

          _section('3. Camera & Photo Library',
              'DocSign requests camera and photo library access only when you use the '
              'Scanner feature to scan physical documents. Photos taken or imported '
              'are processed entirely on your device and are never uploaded anywhere.'),

          _section('4. File Access',
              'DocSign reads PDF and document files only when you explicitly open them '
              'using the "Open PDF" or "Open Document" features. Files are never '
              'transmitted off your device.'),

          _section('5. Internet',
              'DocSign may use internet access to download Google Fonts on first launch '
              'for the document editor. No document data is involved in this request. '
              'After fonts are cached, the app works fully offline.'),

          _section('6. Third-Party Services',
              'DocSign uses the following open-source packages, all of which operate '
              'entirely offline:\n'
              '• pdfx — PDF rendering\n'
              '• pdf — PDF generation\n'
              '• image — Image processing\n'
              '• flutter_quill — Rich text editing\n'
              '• google_fonts — Typography\n\n'
              'None of these packages transmit data externally.'),

          _section('7. Data Retention',
              'Documents and annotations are stored in your device\'s app storage. '
              'You can delete all app data at any time by uninstalling DocSign or '
              'clearing app data in your device settings.'),

          _section('8. Children\'s Privacy',
              'DocSign does not knowingly collect any information from children under 13. '
              'The app contains no advertising, in-app purchases, or data collection.'),

          _section('9. Changes to This Policy',
              'If we update this policy, changes will be reflected in the app with an '
              'updated "Last updated" date.'),

          _section('10. Contact',
              'If you have questions about this privacy policy, please contact us at:\n'
              'support@docsign.app'),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _header(String text) => Text(text, style: GoogleFonts.inter(
      color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700));

  Widget _meta(String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: DS.caption().copyWith(fontSize: 13)));

  Widget _section(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: GoogleFonts.inter(
          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(body, style: DS.body(size: 14).copyWith(
          color: const Color(0xFFAEAEB2), height: 1.55)),
    ]),
  );
}
