import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import 'pdf_viewer_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TemplateGallery — 8 templates + company logo upload on Invoice
// ─────────────────────────────────────────────────────────────────────────────

class TemplateGallery extends StatefulWidget {
  const TemplateGallery({super.key});
  @override
  State<TemplateGallery> createState() => _TemplateGalleryState();
}

class _TemplateGalleryState extends State<TemplateGallery> {
  String _filter = 'All';
  static const _cats = ['All', 'HR', 'Legal', 'Finance', 'Sales', 'Admin'];

  static const _templates = [
    _Tpl('Invoice',           Icons.receipt_long_rounded,  DS.indigo,  'Finance'),
    _Tpl('Receipt',           Icons.receipt_rounded,       DS.orange,  'Finance'),
    _Tpl('Quotation',         Icons.request_quote_rounded, DS.indigo,  'Finance'),
    _Tpl('Purchase Order',    Icons.shopping_cart_rounded, DS.indigo,  'Finance'),
    _Tpl('Bill of Sale',      Icons.description_rounded,   DS.orange,  'Finance'),
    _Tpl('Expense Report',    Icons.assessment_rounded,    DS.green,   'Finance'),
    _Tpl('NDA',               Icons.gavel_rounded,         DS.orange,  'Legal'),
    _Tpl('Service Agreement', Icons.handshake_rounded,     DS.green,   'Legal'),
    _Tpl('Freelance Contract',Icons.person_rounded,        DS.purple,  'Legal'),
    _Tpl('Rental Agreement',  Icons.home_rounded,          DS.orange,  'Legal'),
    _Tpl('Non-Compete',       Icons.block_rounded,         DS.red,     'Legal'),
    _Tpl('Offer Letter',      Icons.mail_rounded,          DS.purple,  'HR'),
    _Tpl('Employment Contract',Icons.work_rounded,         DS.indigo,  'HR'),
    _Tpl('Termination Letter',Icons.exit_to_app_rounded,   DS.red,     'HR'),
    _Tpl('Business Proposal', Icons.lightbulb_rounded,     DS.orange,  'Sales'),
    _Tpl('Meeting Minutes',   Icons.event_note_rounded,    DS.cyan,    'Admin'),
  ];

  List<_Tpl> get _filtered =>
      _filter == 'All' ? _templates
          : _templates.where((t) => t.category == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category filter chips
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _cats.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: cat,
                  selected: _filter == cat,
                  onTap: () => setState(() => _filter = cat),
                ),
              )).toList(),
            ),
          ),
        ),
        // ✅ Compact list of templates
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            itemCount: _filtered.length,
            itemBuilder: (_, i) => _TemplateRow(tpl: _filtered[i]),
          ),
        ),
      ],
    );
  }
}

// ✅ Compact row instead of big card
class _TemplateRow extends StatelessWidget {
  final _Tpl tpl;
  const _TemplateRow({required this.tpl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openTemplate(context, tpl),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: DS.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DS.separator, width: 0.5),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: tpl.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(tpl.icon, color: tpl.color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tpl.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(tpl.category, style: TextStyle(color: tpl.color.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tpl.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tpl.color.withOpacity(0.2)),
            ),
            child: Text('Fill →', style: TextStyle(color: tpl.color, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

// ✅ Open template function
void _openTemplate(BuildContext context, _Tpl tpl) {
  final Widget form = switch (tpl.name) {
    'Invoice'           => const InvoiceForm(),
    'NDA'               => const NdaForm(),
    'Offer Letter'      => const OfferLetterForm(),
    'Purchase Order'    => const PurchaseOrderForm(),
    'Service Agreement' => const ServiceAgreementForm(),
    'Receipt'           => const ReceiptForm(),
    _                   => const _ComingSoonForm(),
  };
  Navigator.push(context, MaterialPageRoute(builder: (_) => form));
}

// ✅ Placeholder for templates not yet built
class _ComingSoonForm extends StatelessWidget {
  const _ComingSoonForm();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DS.bg,
    appBar: AppBar(
      backgroundColor: DS.bgCard,
      elevation: 0,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20), onPressed: () => Navigator.pop(context)),
      title: const Text('Coming Soon', style: TextStyle(color: Colors.white)),
    ),
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.construction_rounded, size: 64, color: DS.indigo),
      const SizedBox(height: 16),
      Text('This template is coming soon!', style: DS.title()),
      const SizedBox(height: 8),
      Text('We\'re working hard to add more templates.', style: DS.body()),
    ])),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? DS.indigo : DS.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? DS.indigo : DS.separator,
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : DS.textSecondary,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
  );
}

class _Tpl {
  final String name, category;
  final IconData icon;
  final Color color;
  const _Tpl(this.name, this.icon, this.color, this.category);
}

class _TemplateCard extends StatelessWidget {
  final _Tpl tpl;
  const _TemplateCard({super.key, required this.tpl});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _open(context),
    child: Container(
      decoration: BoxDecoration(
        color: DS.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DS.separator, width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: tpl.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(tpl.icon, color: tpl.color, size: 26),
          ),
          const SizedBox(height: 9),
          Text(
            tpl.name,
            style: DS.body(size: 13).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: tpl.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tpl.category,
              style: TextStyle(
                color: tpl.color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _open(BuildContext context) {
    final Widget form = switch (tpl.name) {
      'Invoice'           => const InvoiceForm(),
      'NDA'               => const NdaForm(),
      'Offer Letter'      => const OfferLetterForm(),
      'Purchase Order'    => const PurchaseOrderForm(),
      'Service Agreement' => const ServiceAgreementForm(),
      'Receipt'           => const ReceiptForm(),
      _                   => const SizedBox(),
    };
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => form),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INVOICE — with company logo upload
// ─────────────────────────────────────────────────────────────────────────────

class InvoiceForm extends StatefulWidget {
  const InvoiceForm({super.key});
  @override
  State<InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends State<InvoiceForm> {
  final _from       = TextEditingController(text: 'Your Company Name');
  final _fromAddr   = TextEditingController(text: '123 Business St, City');
  final _to         = TextEditingController(text: 'Client Name');
  final _toAddr     = TextEditingController(text: 'Client Address');
  final _invoiceNum = TextEditingController(text: 'INV-001');
  final _date       = TextEditingController(text: _today());
  final _due        = TextEditingController(text: _dueDate());
  final _notes      = TextEditingController(text: 'Thank you for your business!');
  final List<Map<String, TextEditingController>> _items = [];
  final _qrData = TextEditingController(text: '');  // Optional payment link

  String? _logoPath;
  Uint8List? _logoBytes;
  bool _building = false;

  static String _today() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static String _dueDate() {
    final d = DateTime.now().add(const Duration(days: 30));
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  void initState() {
    super.initState();
    _addItem();
  }

  void _addItem() => setState(() => _items.add({
    'desc': TextEditingController(text: 'Professional Services'),
    'qty':  TextEditingController(text: '1'),
    'rate': TextEditingController(text: '250.00'),
  }));

  double get _subtotal => _items.fold(0.0, (s, item) =>
      s + (double.tryParse(item['qty']!.text) ?? 0) * (double.tryParse(item['rate']!.text) ?? 0));
  double get _tax => _subtotal * 0.10;
  double get _total => _subtotal + _tax;

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (r == null || r.files.isEmpty || !mounted) return;
    
    final picked = r.files.first;
    final Uint8List? imgBytes = kIsWeb
        ? picked.bytes
        : await PlatformFileService.readBytes(picked.path ?? '');
    
    if (imgBytes == null || imgBytes.isEmpty || !mounted) return;
    
    final logoPath = kIsWeb ? picked.name : (picked.path ?? picked.name);
    final bytes = await PlatformFileService.readBytes(logoPath) ?? (picked.bytes ?? Uint8List(0));
    
    setState(() {
      _logoPath = logoPath;
      _logoBytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) => _Scaffold(
    title: 'Invoice',
    icon: Icons.receipt_long_rounded,
    color: DS.indigo,
    onGenerate: _building ? null : _generate,
    building: _building,
    child: Column(children: [
      // Logo upload
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DS.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DS.separator, width: 0.5),
        ),
        child: Row(children: [
          if (_logoBytes != null)
            Container(
              width: 60,
              height: 40,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
              child: Image.memory(_logoBytes!, fit: BoxFit.contain),
            )
          else
            Container(
              width: 60,
              height: 40,
              decoration: BoxDecoration(
                color: DS.bgCard2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.image_rounded, color: DS.textSecondary, size: 22),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Company Logo', style: DS.body(size: 13).copyWith(fontWeight: FontWeight.w600)),
                Text('Appears top-right on invoice', style: DS.caption().copyWith(fontSize: 11)),
              ],
            ),
          ),
          TextButton(
            onPressed: _pickLogo,
            child: Text(
              _logoBytes != null ? 'Change' : 'Upload',
              style: const TextStyle(color: DS.indigo, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    _row([Expanded(child: _field('From', _from)), Expanded(child: _field('To', _to))]),
    _row([Expanded(child: _field('From Address', _fromAddr)), Expanded(child: _field('Client Address', _toAddr))]),
    _row([Expanded(child: _field('Invoice #', _invoiceNum)), Expanded(child: _field('Issue Date', _date))]),
    _row([Expanded(child: _field('Due Date', _due)), const Expanded(child: SizedBox())]),
      const SectionHeader('LINE ITEMS'),
      ..._items.asMap().entries.map((e) => _ItemRow(
        index: e.key + 1,
        ctrls: e.value,
        onDelete: _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null,
        onChanged: () => setState(() {}),
      )),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add Line Item'),
          style: TextButton.styleFrom(foregroundColor: DS.indigo),
        ),
      ),
      const Divider(color: DS.separator),
      _summRow('Subtotal', '\$${_subtotal.toStringAsFixed(2)}'),
      _summRow('Tax (10%)', '\$${_tax.toStringAsFixed(2)}'),
      _summRow('TOTAL', '\$${_total.toStringAsFixed(2)}', big: true),
      const SizedBox(height: 12),
      const SectionHeader('QR CODE (Optional)'),
      _field('Payment Link / URL for QR', _qrData, maxLines: 1),
      const SizedBox(height: 12),
      _field('Notes / Terms', _notes, maxLines: 3),
    ]),
  );

  Widget _summRow(String l, String v, {bool big = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('$l  ', style: big ? DS.title() : DS.body()),
        Text(
          v,
          style: big
              ? DS.title(size: 20).copyWith(color: DS.indigo)
              : DS.body(color: DS.textSecondary),
        ),
      ],
    ),
  );

  Future<void> _generate() async {
    setState(() => _building = true);
    try {
      final doc = pw.Document();
      pw.MemoryImage? logoImg;
      if (_logoBytes != null) logoImg = pw.MemoryImage(_logoBytes!);

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('INVOICE', style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.indigo900,
                  )),
                  pw.SizedBox(height: 4),
                  pw.Text(_from.text, style: pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
                  pw.Text(_fromAddr.text, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (logoImg != null) ...[
                    pw.Image(logoImg, width: 80, height: 40, fit: pw.BoxFit.contain),
                    pw.SizedBox(height: 8),
                  ],
                  pw.Text(_invoiceNum.text, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${_date.text}', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  pw.Text('Due: ${_due.text}', style: pw.TextStyle(fontSize: 10, color: PdfColors.red)),
                ],
              ),
            ],
          ),
          pw.Divider(color: PdfColors.indigo900, thickness: 2),
          pw.SizedBox(height: 10),
          pw.Row(children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('BILL TO', style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey500,
                  fontWeight: pw.FontWeight.bold,
                )),
                pw.Text(_to.text, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(_toAddr.text, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              ],
            )),
          ]),
          pw.SizedBox(height: 20),
          _tableHeader(['Description', 'Qty', 'Unit Price', 'Total']),
          ..._items.asMap().entries.map((e) {
            final qty = double.tryParse(e.value['qty']!.text) ?? 0;
            final rate = double.tryParse(e.value['rate']!.text) ?? 0;
            return _tableRow(
              [
                e.value['desc']!.text,
                qty.toInt().toString(),
                '\$${rate.toStringAsFixed(2)}',
                '\$${(qty * rate).toStringAsFixed(2)}',
              ],
              even: e.key.isEven,
            );
          }),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _totalRow('Subtotal', '\$${_subtotal.toStringAsFixed(2)}'),
                  _totalRow('Tax (10%)', '\$${_tax.toStringAsFixed(2)}'),
                  pw.Divider(color: PdfColors.indigo900),
                  _totalRow('TOTAL', '\$${_total.toStringAsFixed(2)}', bold: true),
                ],
              ),
            ],
          ),
          // ✅ QR Code (if provided)
          if (_qrData.text.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: _qrData.text.trim(),
                      width: 70,
                      height: 70,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Scan to pay', 
                      style: pw.TextStyle(fontSize: 6, color: PdfColors.grey500)),
                  ],
                ),
              ],
            ),
          ],
          
          if (_notes.text.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Notes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(_notes.text, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ],
      ));
      final (path, bytes) = await _savePdf(doc, 'invoice_${_invoiceNum.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes),
      ));
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  pw.Widget _tableHeader(List<String> cols) => pw.Container(
    color: PdfColors.indigo900,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Row(
      children: cols.asMap().entries.map((e) => pw.Expanded(
        flex: e.key == 0 ? 4 : 1,
        child: pw.Text(
          e.value,
          textAlign: e.key == 0 ? pw.TextAlign.left : pw.TextAlign.right,
          style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
        ),
      )).toList(),
    ),
  );

  pw.Widget _tableRow(List<String> cols, {bool even = true}) => pw.Container(
    color: even ? PdfColors.grey100 : PdfColors.white,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Row(
      children: cols.asMap().entries.map((e) => pw.Expanded(
        flex: e.key == 0 ? 4 : 1,
        child: pw.Text(
          e.value,
          textAlign: e.key == 0 ? pw.TextAlign.left : pw.TextAlign.right,
          style: pw.TextStyle(fontSize: 9),
        ),
      )).toList(),
    ),
  );

  pw.Widget _totalRow(String k, String v, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(children: [
      pw.SizedBox(
        width: 100,
        child: pw.Text(
          k,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null),
        ),
      ),
      pw.SizedBox(
        width: 60,
        child: pw.Text(
          v,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: bold ? 13 : 10,
            fontWeight: bold ? pw.FontWeight.bold : null,
            color: bold ? PdfColors.indigo900 : null,
          ),
        ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// NDA
// ─────────────────────────────────────────────────────────────────────────────

class NdaForm extends StatefulWidget {
  const NdaForm({super.key});
  @override
  State<NdaForm> createState() => _NdaState();
}

class _NdaState extends State<NdaForm> {
  final _p1 = TextEditingController(text: 'First Party');
  final _p2 = TextEditingController(text: 'Second Party');
  final _date = TextEditingController(text: _today());
  final _period = TextEditingController(text: '2 years');
  final _state = TextEditingController(text: 'California');
  bool _b = false;

  static String _today() {
    final d = DateTime.now();
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) => _Scaffold(
    title: 'NDA',
    icon: Icons.gavel_rounded,
    color: DS.orange,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      _field('Disclosing Party', _p1),
      _field('Receiving Party', _p2),
      _row([Expanded(child: _field('Effective Date', _date)), Expanded(child: _field('Duration', _period))]),
      _field('Governing State', _state),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    try {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(52),
        build: (_) => [
          pw.Text('NON-DISCLOSURE AGREEMENT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Text(
            'This Agreement is entered into on ${_date.text} between ${_p1.text} ("Disclosing Party") and ${_p2.text} ("Receiving Party").',
            style: pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 12),
          ...[
            '1. Confidential Information. The Receiving Party shall keep all disclosed information confidential.',
            '2. Non-Use. Information shall only be used to evaluate a potential business relationship.',
            '3. Duration. Obligations continue for ${_period.text} from the Effective Date.',
            '4. Governing Law. This Agreement is governed by laws of ${_state.text}.',
          ].map((t) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(t, style: pw.TextStyle(fontSize: 11)),
          )),
          pw.SizedBox(height: 40),
          pw.Row(children: [
            pw.Expanded(child: pw.Column(children: [
              pw.Divider(),
              pw.Text('${_p1.text}  Signature', style: pw.TextStyle(fontSize: 9)),
            ])),
            pw.SizedBox(width: 40),
            pw.Expanded(child: pw.Column(children: [
              pw.Divider(),
              pw.Text('${_p2.text}  Signature', style: pw.TextStyle(fontSize: 9)),
            ])),
          ]),
        ],
      ));
      final (path, bytes) = await _savePdf(doc, 'nda_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes),
      ));
    } finally {
      if (mounted) setState(() => _b = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OFFER LETTER
// ─────────────────────────────────────────────────────────────────────────────

class OfferLetterForm extends StatefulWidget {
  const OfferLetterForm({super.key});
  @override
  State<OfferLetterForm> createState() => _OfferState();
}

class _OfferState extends State<OfferLetterForm> {
  final _co = TextEditingController(text: 'Company');
  final _cand = TextEditingController(text: 'Candidate Name');
  final _role = TextEditingController(text: 'Software Engineer');
  final _start = TextEditingController(text: 'May 1, 2026');
  final _sal = TextEditingController(text: '\$80,000 per annum');
  final _dl = TextEditingController(text: 'Apr 25, 2026');
  bool _b = false;

  @override
  Widget build(BuildContext context) => _Scaffold(
    title: 'Offer Letter',
    icon: Icons.mail_rounded,
    color: DS.purple,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      _field('Company', _co),
      _field('Candidate Name', _cand),
      _field('Job Title', _role),
      _row([Expanded(child: _field('Start Date', _start)), Expanded(child: _field('Offer Deadline', _dl))]),
      _field('Compensation', _sal),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    try {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(52),
        build: (_) => [
          pw.Text(_co.text, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
          pw.SizedBox(height: 16),
          pw.Text('Dear ${_cand.text},', style: pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 10),
          pw.Text('We are pleased to offer you the position of ${_role.text} at ${_co.text}.', style: pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 14),
          ...{
            'Position': _role.text,
            'Start Date': _start.text,
            'Compensation': _sal.text,
          }.entries.map((e) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(children: [
              pw.SizedBox(width: 130, child: pw.Text(e.key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
              pw.Text(e.value, style: pw.TextStyle(fontSize: 10)),
            ]),
          )),
          pw.SizedBox(height: 12),
          pw.Text('Please accept this offer by ${_dl.text}.', style: pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 40),
          pw.Row(children: [
            pw.Expanded(child: pw.Column(children: [
              pw.Divider(),
              pw.Text('Authorized Signature', style: pw.TextStyle(fontSize: 9)),
            ])),
            pw.SizedBox(width: 40),
            pw.Expanded(child: pw.Column(children: [
              pw.Divider(),
              pw.Text('${_cand.text} — Acceptance', style: pw.TextStyle(fontSize: 9)),
            ])),
          ]),
        ],
      ));
      await _savePdf(doc, 'offer_${_cand.text.replaceAll(' ', '_')}');
    } finally {
      if (mounted) setState(() => _b = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PURCHASE ORDER
// ─────────────────────────────────────────────────────────────────────────────

class PurchaseOrderForm extends StatefulWidget {
  const PurchaseOrderForm({super.key});
  @override
  State<PurchaseOrderForm> createState() => _POState();
}

class _POState extends State<PurchaseOrderForm> {
  final _buyer = TextEditingController(text: 'Your Company');
  final _vendor = TextEditingController(text: 'Vendor Name');
  final _poNum = TextEditingController(text: 'PO-001');
  final _date = TextEditingController(text: '12/04/2026');
  final _del = TextEditingController(text: '30 days');
  final _terms = TextEditingController(text: 'Net 30');
  final List<Map<String, TextEditingController>> _items = [];
  bool _b = false;

  @override
  void initState() {
    super.initState();
    _items.add({
      'desc': TextEditingController(text: 'Item Description'),
      'qty': TextEditingController(text: '10'),
      'price': TextEditingController(text: '50.00'),
    });
  }

  double get _total => _items.fold(0.0, (s, i) => s + (double.tryParse(i['qty']!.text) ?? 0) * (double.tryParse(i['price']!.text) ?? 0));

  @override
  Widget build(BuildContext context) => _Scaffold(
    title: 'Purchase Order',
    icon: Icons.shopping_cart_rounded,
    color: DS.indigo,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
    _row([Expanded(child: _field('Buyer', _buyer)), Expanded(child: _field('Vendor', _vendor))]),
    _row([Expanded(child: _field('PO Number', _poNum)), Expanded(child: _field('Date', _date))]),
    _row([Expanded(child: _field('Delivery', _del)), Expanded(child: _field('Payment Terms', _terms))]),
      const SectionHeader('ITEMS'),
      ..._items.asMap().entries.map((e) => _ItemRow(
        index: e.key + 1,
        ctrls: Map.from({
          'desc': e.value['desc']!,
          'qty': e.value['qty']!,
          'rate': e.value['price']!,
        }),
        onDelete: _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null,
        onChanged: () => setState(() {}),
      )),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _items.add({
            'desc': TextEditingController(text: 'Item'),
            'qty': TextEditingController(text: '1'),
            'price': TextEditingController(text: '0.00'),
          })),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add Item'),
          style: TextButton.styleFrom(foregroundColor: DS.indigo),
        ),
      ),
      _row([
        const Expanded(child: SizedBox()),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Total: \$${_total.toStringAsFixed(2)}',
            style: DS.title(size: 18).copyWith(color: DS.indigo),
          ),
        ),
      ]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    try {
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PURCHASE ORDER', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Buyer: ${_buyer.text}', style: pw.TextStyle(fontSize: 11)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('PO: ${_poNum.text}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${_date.text}', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.Text('Vendor: ${_vendor.text}', style: pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 16),
            pw.Container(
              color: PdfColors.indigo900,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: pw.Row(children: [
                pw.Expanded(flex: 4, child: pw.Text('Item', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.Expanded(child: pw.Text('Qty', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
                pw.Expanded(child: pw.Text('Price', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
                pw.Expanded(child: pw.Text('Total', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
              ]),
            ),
            ..._items.asMap().entries.map((e) {
              final qty = double.tryParse(e.value['qty']!.text) ?? 0;
              final price = double.tryParse(e.value['price']!.text) ?? 0;
              return pw.Container(
                color: e.key.isEven ? PdfColors.grey100 : PdfColors.white,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: pw.Row(children: [
                  pw.Expanded(flex: 4, child: pw.Text(e.value['desc']!.text, style: pw.TextStyle(fontSize: 9))),
                  pw.Expanded(child: pw.Text(qty.toInt().toString(), style: pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                  pw.Expanded(child: pw.Text('\$${price.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                  pw.Expanded(child: pw.Text('\$${(qty * price).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
                ]),
              );
            }),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text('TOTAL  \$${_total.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Text('Delivery: ${_del.text}  ·  Terms: ${_terms.text}', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ));
      final (path, bytes) = await _savePdf(doc, 'po_${_poNum.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes),
      ));
    } finally {
      if (mounted) setState(() => _b = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE AGREEMENT
// ─────────────────────────────────────────────────────────────────────────────

class ServiceAgreementForm extends StatefulWidget {
  const ServiceAgreementForm({super.key});
  @override
  State<ServiceAgreementForm> createState() => _SAState();
}

class _SAState extends State<ServiceAgreementForm> {
  final _sp = TextEditingController(text: 'Service Provider');
  final _cl = TextEditingController(text: 'Client');
  final _svc = TextEditingController(text: 'Software Development');
  final _fee = TextEditingController(text: '\$5,000/month');
  final _start = TextEditingController(text: 'May 1, 2026');
  final _end = TextEditingController(text: 'Oct 31, 2026');
  bool _b = false;

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Service Agreement',
    icon: Icons.handshake_rounded,
    color: DS.green,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      _row([Expanded(child: _field('Service Provider', _sp)), Expanded(child: _field('Client', _cl))]),

      _field('Services Description', _svc, maxLines: 3),
      _field('Fee', _fee),
      _row([Expanded(child: _field('Start Date', _start)), Expanded(child: _field('End Date', _end))]),

    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    try {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(52),
        build: (_) => [
          pw.Text('SERVICE AGREEMENT', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Text('This Agreement is between ${_sp.text} ("Provider") and ${_cl.text} ("Client").', style: pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 10),
          ...{
            'Services': _svc.text,
            'Fee': _fee.text,
            'Term': '${_start.text} to ${_end.text}',
          }.entries.map((e) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(children: [
              pw.SizedBox(width: 120, child: pw.Text(e.key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
              pw.Expanded(child: pw.Text(e.value, style: pw.TextStyle(fontSize: 11))),
            ]),
          )),
          pw.SizedBox(height: 40),
          pw.Row(children: [
            pw.Expanded(child: pw.Column(children: [
              pw.Divider(),
              pw.Text('${_sp.text}', style: pw.TextStyle(fontSize: 9)),
            ])),
            pw.SizedBox(width: 40),
            pw.Expanded(child: pw.Column(children: [
              pw.Divider(),
              pw.Text('${_cl.text}', style: pw.TextStyle(fontSize: 9)),
            ])),
          ]),
        ],
      ));
      final (path, bytes) = await _savePdf(doc, 'service_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes),
      ));
    } finally {
      if (mounted) setState(() => _b = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECEIPT
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptForm extends StatefulWidget {
  const ReceiptForm({super.key});
  @override
  State<ReceiptForm> createState() => _RcptState();
}

class _RcptState extends State<ReceiptForm> {
  final _from = TextEditingController(text: 'Business Name');
  final _to = TextEditingController(text: 'Customer');
  final _num = TextEditingController(text: 'RCP-001');
  final _date = TextEditingController(text: '12/04/2026');
  final _items = <Map<String, TextEditingController>>[];
  bool _b = false;

  @override
  void initState() {
    super.initState();
    _items.add({
      'desc': TextEditingController(text: 'Item'),
      'qty': TextEditingController(text: '1'),
      'price': TextEditingController(text: '100.00'),
    });
  }

  double get _total => _items.fold(0.0, (s, i) => s + (double.tryParse(i['qty']!.text) ?? 0) * (double.tryParse(i['price']!.text) ?? 0));

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Receipt',
    icon: Icons.receipt_rounded,
    color: DS.orange,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      _row([Expanded(child: _field('From', _from)), Expanded(child: _field('To', _to))]),
      _row([Expanded(child: _field('Receipt #', _num)), Expanded(child: _field('Date', _date))]),

      const SectionHeader('ITEMS'),
      ..._items.asMap().entries.map((e) => _ItemRow(
        index: e.key + 1,
        ctrls: Map.from({
          'desc': e.value['desc']!,
          'qty': e.value['qty']!,
          'rate': e.value['price']!,
        }),
        onDelete: _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null,
        onChanged: () => setState(() {}),
      )),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _items.add({
            'desc': TextEditingController(text: 'Item'),
            'qty': TextEditingController(text: '1'),
            'price': TextEditingController(text: '0.00'),
          })),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add Item'),
          style: TextButton.styleFrom(foregroundColor: DS.indigo),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('TOTAL: \$${_total.toStringAsFixed(2)}', style: DS.title(size: 18).copyWith(color: DS.orange)),
          ],
        ),
      ),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    try {
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(226.77, double.infinity),
        margin: const pw.EdgeInsets.all(16),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(_from.text, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('RECEIPT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.orange)),
            pw.SizedBox(height: 4),
            pw.Text('${_num.text}  ·  ${_date.text}', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Divider(),
            pw.Text('To: ${_to.text}', style: pw.TextStyle(fontSize: 9)),
            pw.Divider(),
            ..._items.map((i) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('${i['desc']!.text} ×${i['qty']!.text}', style: pw.TextStyle(fontSize: 9)),
                pw.Text('\$${((double.tryParse(i['qty']!.text) ?? 0) * (double.tryParse(i['price']!.text) ?? 0)).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9)),
              ],
            )),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text('\$${_total.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text('Thank you!', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
      ));
      final (path, bytes) = await _savePdf(doc, 'receipt_${_num.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes),
      ));
    } finally {
      if (mounted) setState(() => _b = false);
    }
  }
}

// ── Shared utilities ──────────────────────────────────────────────────────────

/// Save PDF and return (path, bytes).
/// On web: saves to memory only (no dart:io File).
// In template_screen.dart, find and replace:
Future<(String, Uint8List)> _savePdf(pw.Document doc, String name) async {
  final bytes = Uint8List.fromList(await doc.save());
  if (kIsWeb) {
    return ('$name.pdf', bytes);
  }
  // ✅ FIXED: Use PlatformFileService
  final path = await PlatformFileService.outputPath('$name.pdf');
  await PlatformFileService.writeBytes(path, bytes);
  return (path, bytes);
}

class _Scaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final VoidCallback? onGenerate;
  final bool building;
  
  const _Scaffold({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.onGenerate,
    required this.building,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: onGenerate,
            child: building
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo),
                  )
                : Text(
                    'Generate PDF',
                    style: GoogleFonts.inter(
                      color: DS.indigo,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          child,
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Generate PDF',
            icon: Icons.picture_as_pdf_rounded,
            color: color,
            onTap: onGenerate,
            loading: building,
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

Widget _field(String label, TextEditingController ctrl, {int maxLines = 1, VoidCallback? onChanged}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: DS.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (_) => onChanged?.call(),
          decoration: InputDecoration(
            filled: true,
            fillColor: DS.bgCard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: DS.separator, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: DS.separator, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: DS.indigo),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _row(List<Widget> cols) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: cols.expand((w) => [w, if (w != cols.last) const SizedBox(width: 10)]).toList(),
);

class _ItemRow extends StatelessWidget {
  final int index;
  final Map<String, TextEditingController> ctrls;
  final VoidCallback? onDelete;
  final VoidCallback onChanged;
  
  const _ItemRow({
    required this.index,
    required this.ctrls,
    this.onDelete,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: DS.bgCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: DS.separator, width: 0.5),
    ),
    child: Column(children: [
      Row(children: [
        Text('#$index', style: DS.caption()),
        const Spacer(),
        if (onDelete != null)
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close_rounded, color: DS.red, size: 18),
          ),
      ]),
      const SizedBox(height: 8),
      _field('Description', ctrls['desc']!, onChanged: onChanged),
      Row(children: [
        Expanded(child: _field('Qty', ctrls['qty']!, onChanged: onChanged)),
        const SizedBox(width: 10),
        Expanded(child: _field('Rate (\$)', ctrls['rate']!, onChanged: onChanged)),
      ]),
    ]),
  );
}

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: DS.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

