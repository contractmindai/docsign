import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image_picker/image_picker.dart';

import '../utils/platform_file_service.dart';
import '../widgets/ds.dart';
import 'pdf_viewer_screen.dart';
import '../services/pdf_save_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helper: Unicode‑safe text style (uses Noto Sans fonts)
// ─────────────────────────────────────────────────────────────────────────────
pw.TextStyle _ts({
  double fontSize = 10,
  bool bold = false,
  PdfColor? color,
}) {
  return PdfSaveService.textStyle(fontSize: fontSize, bold: bold, color: color);
}

// ─────────────────────────────────────────────────────────────────────────────
// Currency selector widget (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class CurrencySelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const CurrencySelector({super.key, required this.value, required this.onChanged});

  static const Map<String, String> currencies = {
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'INR': '₹',
    'CAD': 'C\$',
    'AUD': 'A\$',
    'CHF': 'CHF',
    'CNY': '¥',
    'SEK': 'kr',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: DS.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DS.separator),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.arrow_drop_down, color: DS.indigo),
          dropdownColor: DS.bgCard,
          style: TextStyle(color: DS.textPrimary, fontSize: 13),
          items: currencies.entries.map((e) {
            return DropdownMenuItem(
              value: e.key,
              child: Text('${e.key} (${e.value})'),
            );
          }).toList(),
          onChanged: (v) => onChanged(v!),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable form field widgets
// ─────────────────────────────────────────────────────────────────────────────
class _RequiredTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final bool isEmail;
  const _RequiredTextField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.isEmail = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: DS.textPrimary, fontSize: 14),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'This field is required';
              }
              if (isEmail && !value.contains('@')) {
                return 'Enter a valid email address';
              }
              return null;
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: DS.bgCard,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.red)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _DatePickerField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                controller.text = '${picked.day}/${picked.month}/${picked.year}';
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: DS.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DS.separator, width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(controller.text, style: TextStyle(color: DS.textPrimary))),
                  const Icon(Icons.calendar_today, size: 18, color: DS.indigo),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  const _ResponsiveRow({required this.children, this.spacing = 10});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    if (!isWide) {
      return Column(
        children: children.expand((w) => [
          w,
          if (w != children.last) SizedBox(height: spacing)
        ]).toList(),
      );
    }
    final rowChildren = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      rowChildren.add(Expanded(child: children[i]));
      if (i < children.length - 1) rowChildren.add(SizedBox(width: spacing));
    }
    return Row(children: rowChildren);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template Gallery (Responsive Grid)
// ─────────────────────────────────────────────────────────────────────────────
class TemplateGallery extends StatefulWidget {
  const TemplateGallery({super.key});
  @override
  State<TemplateGallery> createState() => _TemplateGalleryState();
}

class _TemplateGalleryState extends State<TemplateGallery> {
  String _filter = 'All';
  static const _cats = ['All', 'HR', 'Legal', 'Finance', 'Sales', 'Admin', 'Career'];
  static const _teal = Color(0xFF20B2AA);

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
    _Tpl('Resume / CV',       Icons.description_rounded,   _teal,      'Career'),
  ];

  List<_Tpl> get _filtered =>
      _filter == 'All' ? _templates : _templates.where((t) => t.category == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter chips + clear button
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _cats.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(label: cat, selected: _filter == cat, onTap: () => setState(() => _filter = cat)),
                    )).toList(),
                  ),
                ),
              ),
              if (_filter != 'All')
                TextButton(
                  onPressed: () => setState(() => _filter = 'All'),
                  style: TextButton.styleFrom(foregroundColor: DS.indigo),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        // Responsive grid
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 900 ? 3 : 4);
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => _TemplateCard(tpl: _filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final _Tpl tpl;
  const _TemplateCard({required this.tpl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openTemplateWithAnimation(context, tpl),
      child: Container(
        decoration: BoxDecoration(
          color: DS.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DS.separator),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tpl.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tpl.icon, color: tpl.color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(tpl.name, style: const TextStyle(color: DS.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tpl.category, style: TextStyle(color: tpl.color.withOpacity(0.7), fontSize: 11)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: tpl.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tpl.color.withOpacity(0.3)),
              ),
              child: Text('Fill →', style: TextStyle(color: tpl.color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

void _openTemplateWithAnimation(BuildContext context, _Tpl tpl) {
  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => _getFormForTpl(tpl),
      transitionsBuilder: (_, animation, __, child) {
        const begin = Offset(0.3, 0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var offsetAnimation = animation.drive(tween);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
    ),
  );
}

Widget _getFormForTpl(_Tpl tpl) {
  switch (tpl.name) {
    case 'Invoice':           return const InvoiceForm();
    case 'NDA':               return const NdaForm();
    case 'Offer Letter':      return const OfferLetterForm();
    case 'Purchase Order':    return const PurchaseOrderForm();
    case 'Service Agreement': return const ServiceAgreementForm();
    case 'Receipt':           return const ReceiptForm();
    case 'Quotation':         return const QuotationForm();
    case 'Bill of Sale':      return const BillOfSaleForm();
    case 'Expense Report':    return const ExpenseReportForm();
    case 'Freelance Contract':return const FreelanceContractForm();
    case 'Rental Agreement':  return const RentalAgreementForm();
    case 'Non-Compete':       return const NonCompeteForm();
    case 'Employment Contract':return const EmploymentContractForm();
    case 'Termination Letter':return const TerminationLetterForm();
    case 'Business Proposal': return const BusinessProposalForm();
    case 'Meeting Minutes':   return const MeetingMinutesForm();
    case 'Resume / CV':       return const ResumeForm();
    default:                  return const _ComingSoonForm();
  }
}

class _ComingSoonForm extends StatelessWidget {
  const _ComingSoonForm();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DS.bg,
    appBar: AppBar(
      backgroundColor: DS.bgCard,
      elevation: 0,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20), onPressed: () => Navigator.pop(context)),
      title: const Text('Coming Soon', style: TextStyle(color: DS.textPrimary)),
    ),
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.construction_rounded, size: 64, color: DS.indigo),
        const SizedBox(height: 16),
        Text('This template is coming soon!', style: DS.title()),
        const SizedBox(height: 8),
        Text('We\'re working hard to add more templates.', style: DS.body()),
      ]),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? DS.indigo : DS.bgCard,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: selected ? DS.indigo : DS.separator, width: 0.5),
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

// ─────────────────────────────────────────────────────────────────────────────
// INVOICE FORM (with validation, date pickers, two‑column layout)
// ─────────────────────────────────────────────────────────────────────────────
class InvoiceForm extends StatefulWidget {
  const InvoiceForm({super.key});
  @override
  State<InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends State<InvoiceForm> {
  final _formKey = GlobalKey<FormState>();
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _from       = TextEditingController(text: 'Your Company Name');
  final _fromAddr   = TextEditingController(text: '123 Business St, City');
  final _to         = TextEditingController(text: 'Client Name');
  final _toAddr     = TextEditingController(text: 'Client Address');
  final _invoiceNum = TextEditingController(text: 'INV-001');
  final _date       = TextEditingController(text: _today());
  final _due        = TextEditingController(text: _dueDate());
  final _notes      = TextEditingController(text: 'Thank you for your business!');
  final List<Map<String, TextEditingController>> _items = [];
  final _qrData = TextEditingController(text: '');
  String? _logoPath;
  Uint8List? _logoBytes;
  bool _building = false;

  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';
  static String _dueDate() => '${DateTime.now().add(const Duration(days: 30)).day}/${DateTime.now().month}/${DateTime.now().year}';

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
  double get _subtotal => _items.fold(0.0, (s, item) => s + (double.tryParse(item['qty']!.text) ?? 0) * (double.tryParse(item['rate']!.text) ?? 0));
  double get _tax => _subtotal * 0.10;
  double get _total => _subtotal + _tax;

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: kIsWeb);
    if (r == null || r.files.isEmpty || !mounted) return;
    final picked = r.files.first;
    final Uint8List? imgBytes = kIsWeb ? picked.bytes : await PlatformFileService.readBytes(picked.path ?? '');
    if (imgBytes == null || imgBytes.isEmpty || !mounted) return;
    final bytes = await PlatformFileService.readBytes(picked.path ?? '') ?? (picked.bytes ?? Uint8List(0));
    setState(() { _logoPath = picked.name; _logoBytes = bytes; });
  }

  @override
  Widget build(BuildContext context) => _Scaffold(
    title: 'Invoice',
    icon: Icons.receipt_long_rounded,
    color: DS.indigo,
    onGenerate: _building ? null : _generate,
    building: _building,
    child: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(children: [
          Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
          Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)), child: Row(children: [
            if (_logoBytes != null) Container(width: 60, height: 40, child: Image.memory(_logoBytes!, fit: BoxFit.contain))
            else Container(width: 60, height: 40, decoration: BoxDecoration(color: DS.bgCard2, borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.image_rounded, color: DS.textSecondary)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Company Logo', style: DS.body(size: 13).copyWith(fontWeight: FontWeight.w600)), Text('Appears top-right on invoice', style: DS.caption().copyWith(fontSize: 11))])),
            TextButton(onPressed: _pickLogo, child: Text(_logoBytes != null ? 'Change' : 'Upload', style: const TextStyle(color: DS.indigo, fontSize: 12, fontWeight: FontWeight.w600))),
          ])),
          _ResponsiveRow(children: [
            Expanded(child: _RequiredTextField(label: 'From', controller: _from)),
            Expanded(child: _RequiredTextField(label: 'To', controller: _to)),
          ]),
          _ResponsiveRow(children: [
            Expanded(child: _RequiredTextField(label: 'From Address', controller: _fromAddr)),
            Expanded(child: _RequiredTextField(label: 'Client Address', controller: _toAddr)),
          ]),
          _ResponsiveRow(children: [
            Expanded(child: _RequiredTextField(label: 'Invoice #', controller: _invoiceNum)),
            Expanded(child: _DatePickerField(label: 'Issue Date', controller: _date)),
          ]),
          _ResponsiveRow(children: [
            Expanded(child: _DatePickerField(label: 'Due Date', controller: _due)),
            const Expanded(child: SizedBox()),
          ]),
          const SectionHeader('LINE ITEMS'),
          ..._items.asMap().entries.map((e) => _ItemRow(index: e.key+1, ctrls: e.value, onDelete: _items.length>1 ? () => setState(() => _items.removeAt(e.key)) : null, onChanged: () => setState(() {}))),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add Line Item'), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
          const Divider(color: DS.separator),
          _summRow('Subtotal', '$_currencySymbol${_subtotal.toStringAsFixed(2)}'),
          _summRow('Tax (10%)', '$_currencySymbol${_tax.toStringAsFixed(2)}'),
          _summRow('TOTAL', '$_currencySymbol${_total.toStringAsFixed(2)}', big: true),
          const SectionHeader('QR CODE (Optional)'),
          _RequiredTextField(label: 'Notes / Terms', controller: _notes, maxLines: 3),
        ]),
      ),
    ),
  );

  Widget _summRow(String l, String v, {bool big=false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('$l  ', style: big ? DS.title() : DS.body()), Text(v, style: big ? DS.title(size: 20).copyWith(color: DS.indigo) : DS.body(color: DS.textSecondary))]));

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _building = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      pw.MemoryImage? logoImg = _logoBytes != null ? pw.MemoryImage(_logoBytes!) : null;
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), build: (_) => [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('INVOICE', style: _ts(fontSize: 28, bold: true, color: PdfColors.indigo900)),
            pw.SizedBox(height: 4),
            pw.Text(_from.text, style: _ts(fontSize: 13, color: PdfColors.grey700)),
            pw.Text(_fromAddr.text, style: _ts(fontSize: 10, color: PdfColors.grey500)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            if (logoImg != null) pw.Image(logoImg, width: 80, height: 40, fit: pw.BoxFit.contain),
            pw.SizedBox(height: 8),
            pw.Text(_invoiceNum.text, style: _ts(fontSize: 14, bold: true)),
            pw.Text('Date: ${_date.text}', style: _ts(fontSize: 10, color: PdfColors.grey600)),
            pw.Text('Due: ${_due.text}', style: _ts(fontSize: 10, color: PdfColors.red)),
          ]),
        ]),
        pw.Divider(color: PdfColors.indigo900, thickness: 2),
        pw.SizedBox(height: 10),
        pw.Row(children: [pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text('BILL TO', style: _ts(fontSize: 9, bold: true, color: PdfColors.grey500)), pw.Text(_to.text, style: _ts(fontSize: 13, bold: true)), pw.Text(_toAddr.text, style: _ts(fontSize: 10, color: PdfColors.grey600))]))]),
        pw.SizedBox(height: 20),
        _tableHeader(['Description', 'Qty', 'Unit Price', 'Total']),
        ..._items.asMap().entries.map((e) {
          final qty = double.tryParse(e.value['qty']!.text) ?? 0;
          final rate = double.tryParse(e.value['rate']!.text) ?? 0;
          return _tableRow([e.value['desc']!.text, qty.toInt().toString(), '$_currencySymbol${rate.toStringAsFixed(2)}', '$_currencySymbol${(qty*rate).toStringAsFixed(2)}'], even: e.key.isEven);
        }),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _totalRow('Subtotal', '$_currencySymbol${_subtotal.toStringAsFixed(2)}'),
          _totalRow('Tax (10%)', '$_currencySymbol${_tax.toStringAsFixed(2)}'),
          pw.Divider(color: PdfColors.indigo900),
          _totalRow('TOTAL', '$_currencySymbol${_total.toStringAsFixed(2)}', bold: true),
        ])]),
        if (_qrData.text.trim().isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: _qrData.text.trim(), width: 70, height: 70),
            pw.Text('Scan to pay', style: _ts(fontSize: 6, color: PdfColors.grey500)),
          ])]),
        ],
        if (_notes.text.trim().isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Notes:', style: _ts(fontSize: 10, bold: true)),
          pw.Text(_notes.text, style: _ts(fontSize: 9, color: PdfColors.grey600)),
        ],
      ]));
      final (path, bytes) = await _savePdf(doc, 'invoice_${_invoiceNum.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _building = false); }
  }

  pw.Widget _tableHeader(List<String> cols) => pw.Container(color: PdfColors.indigo900, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7), child: pw.Row(children: cols.asMap().entries.map((e) => pw.Expanded(flex: e.key==0?4:1, child: pw.Text(e.value, textAlign: e.key==0?pw.TextAlign.left:pw.TextAlign.right, style: _ts(fontSize: 9, bold: true, color: PdfColors.white)))).toList()));
  pw.Widget _tableRow(List<String> cols, {bool even=true}) => pw.Container(color: even?PdfColors.grey100:PdfColors.white, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Row(children: cols.asMap().entries.map((e) => pw.Expanded(flex: e.key==0?4:1, child: pw.Text(e.value, textAlign: e.key==0?pw.TextAlign.left:pw.TextAlign.right, style: _ts(fontSize: 9)))).toList()));
  pw.Widget _totalRow(String k, String v, {bool bold=false}) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Row(children: [pw.SizedBox(width: 100, child: pw.Text(k, textAlign: pw.TextAlign.right, style: _ts(fontSize: 10, bold: bold))), pw.SizedBox(width: 60, child: pw.Text(v, textAlign: pw.TextAlign.right, style: _ts(fontSize: bold?13:10, bold: bold, color: bold?PdfColors.indigo900:null)))]));
}

// ─────────────────────────────────────────────────────────────────────────────
// NDA FORM (simplified with validation and date picker)
// ─────────────────────────────────────────────────────────────────────────────
class NdaForm extends StatefulWidget {
  const NdaForm({super.key});
  @override
  State<NdaForm> createState() => _NdaState();
}

class _NdaState extends State<NdaForm> {
  final _formKey = GlobalKey<FormState>();
  final _p1 = TextEditingController(text: 'First Party');
  final _p2 = TextEditingController(text: 'Second Party');
  final _date = TextEditingController(text: _today());
  final _period = TextEditingController(text: '2 years');
  final _state = TextEditingController(text: 'California');
  bool _b = false;
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  Widget build(BuildContext context) => _Scaffold(
    title: 'NDA',
    icon: Icons.gavel_rounded,
    color: DS.orange,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Form(
      key: _formKey,
      child: Column(children: [
        _RequiredTextField(label: 'Disclosing Party', controller: _p1),
        _RequiredTextField(label: 'Receiving Party', controller: _p2),
        _ResponsiveRow(children: [
          Expanded(child: _DatePickerField(label: 'Effective Date', controller: _date)),
          Expanded(child: _RequiredTextField(label: 'Duration', controller: _period)),
        ]),
        _RequiredTextField(label: 'Governing State', controller: _state),
      ]),
    ),
  );

  Future<void> _gen() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(52), build: (_) => [
        pw.Text('NON-DISCLOSURE AGREEMENT', style: _ts(fontSize: 18, bold: true)),
        pw.SizedBox(height: 16),
        pw.Text('This Agreement is entered into on ${_date.text} between ${_p1.text} ("Disclosing Party") and ${_p2.text} ("Receiving Party").', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 12),
        ...['1. Confidential Information. The Receiving Party shall keep all disclosed information confidential.','2. Non-Use. Information shall only be used to evaluate a potential business relationship.','3. Duration. Obligations continue for ${_period.text} from the Effective Date.','4. Governing Law. This Agreement is governed by laws of ${_state.text}.'].map((t) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: pw.Text(t, style: _ts(fontSize: 11)))),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_p1.text}  Signature', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_p2.text}  Signature', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'nda_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
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
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(52), build: (_) => [
        pw.Text(_co.text, style: _ts(fontSize: 20, bold: true, color: PdfColors.deepPurple)),
        pw.SizedBox(height: 16),
        pw.Text('Dear ${_cand.text},', style: _ts(fontSize: 13)),
        pw.SizedBox(height: 10),
        pw.Text('We are pleased to offer you the position of ${_role.text} at ${_co.text}.', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 14),
        ...{'Position': _role.text, 'Start Date': _start.text, 'Compensation': _sal.text}.entries.map((e) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: pw.Row(children: [pw.SizedBox(width: 130, child: pw.Text(e.key, style: _ts(fontSize: 10, bold: true))), pw.Text(e.value, style: _ts(fontSize: 10))]))),
        pw.SizedBox(height: 12),
        pw.Text('Please accept this offer by ${_dl.text}.', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('Authorized Signature', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_cand.text} — Acceptance', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'offer_${_cand.text.replaceAll(' ', '_')}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
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
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
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
    _items.add({'desc': TextEditingController(text: 'Item Description'), 'qty': TextEditingController(text: '10'), 'price': TextEditingController(text: '50.00')});
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
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('Buyer', _buyer)), Expanded(child: _field('Vendor', _vendor))]),
      _row([Expanded(child: _field('PO Number', _poNum)), Expanded(child: _field('Date', _date))]),
      _row([Expanded(child: _field('Delivery', _del)), Expanded(child: _field('Payment Terms', _terms))]),
      const SectionHeader('ITEMS'),
      ..._items.asMap().entries.map((e) => _ItemRow(index: e.key+1, ctrls: Map.from({'desc': e.value['desc']!, 'qty': e.value['qty']!, 'rate': e.value['price']!}), onDelete: _items.length>1 ? () => setState(() => _items.removeAt(e.key)) : null, onChanged: () => setState(() {}))),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _items.add({'desc': TextEditingController(text: 'Item'), 'qty': TextEditingController(text: '1'), 'price': TextEditingController(text: '0.00')})), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add Item'), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
      _row([const Expanded(child: SizedBox()), Padding(padding: const EdgeInsets.only(top: 8), child: Text('Total: $_currencySymbol${_total.toStringAsFixed(2)}', style: DS.title(size: 18).copyWith(color: DS.indigo)))]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('PURCHASE ORDER', style: _ts(fontSize: 24, bold: true, color: PdfColors.indigo900)),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Buyer: ${_buyer.text}', style: _ts(fontSize: 11)), pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Text('PO: ${_poNum.text}', style: _ts(fontSize: 12, bold: true)), pw.Text('Date: ${_date.text}', style: _ts(fontSize: 10, color: PdfColors.grey600))])]),
        pw.Text('Vendor: ${_vendor.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 16),
        pw.Container(color: PdfColors.indigo900, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Row(children: [pw.Expanded(flex: 4, child: pw.Text('Item', style: _ts(fontSize: 10, bold: true, color: PdfColors.white))), pw.Expanded(child: pw.Text('Qty', style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.right)), pw.Expanded(child: pw.Text('Price', style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.right)), pw.Expanded(child: pw.Text('Total', style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.right))])),
        ..._items.asMap().entries.map((e) {
          final qty = double.tryParse(e.value['qty']!.text) ?? 0;
          final price = double.tryParse(e.value['price']!.text) ?? 0;
          return pw.Container(color: e.key.isEven ? PdfColors.grey100 : PdfColors.white, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5), child: pw.Row(children: [pw.Expanded(flex: 4, child: pw.Text(e.value['desc']!.text, style: _ts(fontSize: 9))), pw.Expanded(child: pw.Text(qty.toInt().toString(), style: _ts(fontSize: 9), textAlign: pw.TextAlign.right)), pw.Expanded(child: pw.Text('$_currencySymbol${price.toStringAsFixed(2)}', style: _ts(fontSize: 9), textAlign: pw.TextAlign.right)), pw.Expanded(child: pw.Text('$_currencySymbol${(qty*price).toStringAsFixed(2)}', style: _ts(fontSize: 9), textAlign: pw.TextAlign.right))]));
        }),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text('TOTAL  $_currencySymbol${_total.toStringAsFixed(2)}', style: _ts(fontSize: 14, bold: true, color: PdfColors.indigo900))]),
        pw.SizedBox(height: 14),
        pw.Text('Delivery: ${_del.text}  ·  Terms: ${_terms.text}', style: _ts(fontSize: 9, color: PdfColors.grey600)),
      ])));
      final (path, bytes) = await _savePdf(doc, 'po_${_poNum.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
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
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _sp = TextEditingController(text: 'Service Provider');
  final _cl = TextEditingController(text: 'Client');
  final _svc = TextEditingController(text: 'Software Development');
  final _fee = TextEditingController(text: '5,000');
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
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('Service Provider', _sp)), Expanded(child: _field('Client', _cl))]),
      _field('Services Description', _svc, maxLines: 3),
      _field('Fee (monthly)', _fee),
      _row([Expanded(child: _field('Start Date', _start)), Expanded(child: _field('End Date', _end))]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(52), build: (_) => [
        pw.Text('SERVICE AGREEMENT', style: _ts(fontSize: 20, bold: true)),
        pw.SizedBox(height: 16),
        pw.Text('This Agreement is between ${_sp.text} ("Provider") and ${_cl.text} ("Client").', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 10),
        ...{'Services': _svc.text, 'Fee': '$_currencySymbol${_fee.text}/month', 'Term': '${_start.text} to ${_end.text}'}.entries.map((e) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: pw.Row(children: [pw.SizedBox(width: 120, child: pw.Text(e.key, style: _ts(fontSize: 11, bold: true))), pw.Expanded(child: pw.Text(e.value, style: _ts(fontSize: 11)))]))),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_sp.text}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_cl.text}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'service_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
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
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _from = TextEditingController(text: 'Business Name');
  final _to = TextEditingController(text: 'Customer');
  final _num = TextEditingController(text: 'RCP-001');
  final _date = TextEditingController(text: _today());
  final List<Map<String, TextEditingController>> _items = [];
  bool _b = false;
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  void initState() {
    super.initState();
    _items.add({'desc': TextEditingController(text: 'Item'), 'qty': TextEditingController(text: '1'), 'price': TextEditingController(text: '100.00')});
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
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('From', _from)), Expanded(child: _field('To', _to))]),
      _row([Expanded(child: _field('Receipt #', _num)), Expanded(child: _field('Date', _date))]),
      const SectionHeader('ITEMS'),
      ..._items.asMap().entries.map((e) => _ItemRow(index: e.key+1, ctrls: Map.from({'desc': e.value['desc']!, 'qty': e.value['qty']!, 'rate': e.value['price']!}), onDelete: _items.length>1 ? () => setState(() => _items.removeAt(e.key)) : null, onChanged: () => setState(() {}))),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _items.add({'desc': TextEditingController(text: 'Item'), 'qty': TextEditingController(text: '1'), 'price': TextEditingController(text: '0.00')})), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add Item'), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
      Padding(padding: const EdgeInsets.only(top: 8), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('TOTAL: $_currencySymbol${_total.toStringAsFixed(2)}', style: DS.title(size: 18).copyWith(color: DS.orange))])),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.Page(pageFormat: PdfPageFormat(226.77, double.infinity), margin: const pw.EdgeInsets.all(16), build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Text(_from.text, style: _ts(fontSize: 14, bold: true)),
        pw.SizedBox(height: 4),
        pw.Text('RECEIPT', style: _ts(fontSize: 18, bold: true, color: PdfColors.orange)),
        pw.SizedBox(height: 4),
        pw.Text('${_num.text}  ·  ${_date.text}', style: _ts(fontSize: 8, color: PdfColors.grey600)),
        pw.Divider(),
        pw.Text('To: ${_to.text}', style: _ts(fontSize: 9)),
        pw.Divider(),
        ..._items.map((i) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('${i['desc']!.text} ×${i['qty']!.text}', style: _ts(fontSize: 9)), pw.Text('$_currencySymbol${((double.tryParse(i['qty']!.text)??0)*(double.tryParse(i['price']!.text)??0)).toStringAsFixed(2)}', style: _ts(fontSize: 9))])),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('TOTAL', style: _ts(fontSize: 11, bold: true)), pw.Text('$_currencySymbol${_total.toStringAsFixed(2)}', style: _ts(fontSize: 11, bold: true))]),
        pw.SizedBox(height: 8),
        pw.Text('Thank you!', style: _ts(fontSize: 8, color: PdfColors.grey500)),
      ])));
      final (path, bytes) = await _savePdf(doc, 'receipt_${_num.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUOTATION
// ─────────────────────────────────────────────────────────────────────────────

class QuotationForm extends StatefulWidget {
  const QuotationForm({super.key});
  @override
  State<QuotationForm> createState() => _QuotationFormState();
}

class _QuotationFormState extends State<QuotationForm> {
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _from = TextEditingController(text: 'Your Company');
  final _to = TextEditingController(text: 'Client Name');
  final _quoteNum = TextEditingController(text: 'QT-001');
  final _date = TextEditingController(text: _today());
  final _valid = TextEditingController(text: _dueDate());
  final _notes = TextEditingController(text: 'Valid for 30 days');
  final List<Map<String, TextEditingController>> _items = [];
  bool _building = false;

  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';
  static String _dueDate() => '${DateTime.now().add(const Duration(days: 30)).day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  void initState() {
    super.initState();
    _addItem();
  }
  void _addItem() => setState(() => _items.add({'desc': TextEditingController(text: 'Service/Product'), 'qty': TextEditingController(text: '1'), 'rate': TextEditingController(text: '0.00')}));
  double get _subtotal => _items.fold(0.0, (s, i) => s + (double.tryParse(i['qty']!.text) ?? 0) * (double.tryParse(i['rate']!.text) ?? 0));
  double get _tax => _subtotal * 0.10;
  double get _total => _subtotal + _tax;

  @override
  Widget build(BuildContext context) => _Scaffold(
    title: 'Quotation',
    icon: Icons.request_quote_rounded,
    color: DS.indigo,
    onGenerate: _building ? null : _generate,
    building: _building,
    child: Column(children: [
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('From', _from)), Expanded(child: _field('To', _to))]),
      _row([Expanded(child: _field('Quote #', _quoteNum)), Expanded(child: _field('Date', _date))]),
      _field('Valid Until', _valid),
      const SectionHeader('LINE ITEMS'),
      ..._items.asMap().entries.map((e) => _ItemRow(index: e.key+1, ctrls: e.value, onDelete: _items.length>1 ? () => setState(() => _items.removeAt(e.key)) : null, onChanged: () => setState(() {}))),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add Line Item'), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
      const Divider(),
      _summRow('Subtotal', '$_currencySymbol${_subtotal.toStringAsFixed(2)}'),
      _summRow('Tax (10%)', '$_currencySymbol${_tax.toStringAsFixed(2)}'),
      _summRow('TOTAL', '$_currencySymbol${_total.toStringAsFixed(2)}', big: true),
      _field('Notes', _notes, maxLines: 2),
    ]),
  );

  Widget _summRow(String l, String v, {bool big=false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('$l  ', style: big?DS.title():DS.body()), Text(v, style: big?DS.title(size:20).copyWith(color:DS.indigo):DS.body(color:DS.textSecondary))]));

  Future<void> _generate() async {
    setState(() => _building = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), build: (_) => [
        pw.Text('QUOTATION', style: _ts(fontSize: 28, bold: true, color: PdfColors.indigo900)),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(_from.text, style: _ts(fontSize: 13)), pw.Text('Quote #: ${_quoteNum.text}', style: _ts(fontSize: 10))]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Text('Date: ${_date.text}', style: _ts(fontSize: 10)), pw.Text('Valid until: ${_valid.text}', style: _ts(fontSize: 10, color: PdfColors.red))]),
        ]),
        pw.SizedBox(height: 20),
        pw.Text('Bill To: ${_to.text}', style: _ts(fontSize: 12, bold: true)),
        pw.SizedBox(height: 10),
        _tableHeader(['Description', 'Qty', 'Unit Price', 'Total']),
        ..._items.asMap().entries.map((e) {
          final qty = double.tryParse(e.value['qty']!.text) ?? 0;
          final rate = double.tryParse(e.value['rate']!.text) ?? 0;
          return _tableRow([e.value['desc']!.text, qty.toString(), '$_currencySymbol${rate.toStringAsFixed(2)}', '$_currencySymbol${(qty*rate).toStringAsFixed(2)}'], even: e.key.isEven);
        }),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _totalRow('Subtotal', '$_currencySymbol${_subtotal.toStringAsFixed(2)}'),
          _totalRow('Tax (10%)', '$_currencySymbol${_tax.toStringAsFixed(2)}'),
          pw.Divider(),
          _totalRow('TOTAL', '$_currencySymbol${_total.toStringAsFixed(2)}', bold: true),
        ])]),
        if (_notes.text.trim().isNotEmpty) ...[pw.SizedBox(height: 16), pw.Text('Notes:', style: _ts(fontSize: 10, bold: true)), pw.Text(_notes.text, style: _ts(fontSize: 9, color: PdfColors.grey600))],
      ]));
      final (path, bytes) = await _savePdf(doc, 'quotation_${_quoteNum.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _building = false); }
  }

  pw.Widget _tableHeader(List<String> cols) => pw.Container(color: PdfColors.indigo900, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7), child: pw.Row(children: cols.asMap().entries.map((e) => pw.Expanded(flex: e.key==0?4:1, child: pw.Text(e.value, textAlign: e.key==0?pw.TextAlign.left:pw.TextAlign.right, style: _ts(fontSize: 9, bold: true, color: PdfColors.white)))).toList()));
  pw.Widget _tableRow(List<String> cols, {bool even=true}) => pw.Container(color: even?PdfColors.grey100:PdfColors.white, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Row(children: cols.asMap().entries.map((e) => pw.Expanded(flex: e.key==0?4:1, child: pw.Text(e.value, textAlign: e.key==0?pw.TextAlign.left:pw.TextAlign.right, style: _ts(fontSize: 9)))).toList()));
  pw.Widget _totalRow(String k, String v, {bool bold=false}) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Row(children: [pw.SizedBox(width: 100, child: pw.Text(k, textAlign: pw.TextAlign.right, style: _ts(fontSize: 10, bold: bold))), pw.SizedBox(width: 60, child: pw.Text(v, textAlign: pw.TextAlign.right, style: _ts(fontSize: bold?13:10, bold: bold, color: bold?PdfColors.indigo900:null)))]));
}

// ─────────────────────────────────────────────────────────────────────────────
// BILL OF SALE
// ─────────────────────────────────────────────────────────────────────────────

class BillOfSaleForm extends StatefulWidget {
  const BillOfSaleForm({super.key});
  @override
  State<BillOfSaleForm> createState() => _BillOfSaleState();
}

class _BillOfSaleState extends State<BillOfSaleForm> {
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _seller = TextEditingController(text: 'Seller Name');
  final _buyer = TextEditingController(text: 'Buyer Name');
  final _item = TextEditingController(text: 'Item Description');
  final _price = TextEditingController(text: '1000.00');
  final _date = TextEditingController(text: _today());
  bool _b = false;
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Bill of Sale',
    icon: Icons.description_rounded,
    color: DS.orange,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('Seller', _seller)), Expanded(child: _field('Buyer', _buyer))]),
      _field('Item/Asset Description', _item, maxLines: 2),
      _row([Expanded(child: _field('Sale Price', _price)), Expanded(child: _field('Date of Sale', _date))]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => pw.Column(children: [
        pw.Text('BILL OF SALE', style: _ts(fontSize: 24, bold: true)),
        pw.SizedBox(height: 20),
        pw.Text('This Bill of Sale is made on ${_date.text} between ${_seller.text} ("Seller") and ${_buyer.text} ("Buyer").', style: _ts(fontSize: 12)),
        pw.SizedBox(height: 16),
        pw.Text('For the sum of $_currencySymbol${_price.text}, the Seller sells and transfers to the Buyer the following property:', style: _ts(fontSize: 12)),
        pw.SizedBox(height: 8),
        pw.Container(padding: const pw.EdgeInsets.all(12), decoration: pw.BoxDecoration(border: pw.Border.all()), child: pw.Text(_item.text, style: _ts(fontSize: 11))),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('Seller Signature', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('Buyer Signature', style: _ts(fontSize: 9))]))]),
      ])));
      final (path, bytes) = await _savePdf(doc, 'bill_of_sale_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPENSE REPORT
// ─────────────────────────────────────────────────────────────────────────────

class ExpenseReportForm extends StatefulWidget {
  const ExpenseReportForm({super.key});
  @override
  State<ExpenseReportForm> createState() => _ExpenseReportState();
}

class _ExpenseReportState extends State<ExpenseReportForm> {
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _employee = TextEditingController(text: 'Employee Name');
  final _dept = TextEditingController(text: 'Department');
  final _date = TextEditingController(text: _today());
  final List<Map<String, TextEditingController>> _items = [];
  bool _b = false;
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  void initState() {
    super.initState();
    _items.add({'desc': TextEditingController(text: 'Expense description'), 'amount': TextEditingController(text: '50.00')});
  }
  double get _total => _items.fold(0.0, (s, i) => s + (double.tryParse(i['amount']!.text) ?? 0));

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Expense Report',
    icon: Icons.assessment_rounded,
    color: DS.green,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('Employee', _employee)), Expanded(child: _field('Department', _dept))]),
      _field('Date', _date),
      const SectionHeader('EXPENSES'),
      ..._items.asMap().entries.map((e) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)), child: Column(children: [
        Row(children: [Text('#${e.key+1}', style: DS.caption()), const Spacer(), if(_items.length>1) GestureDetector(onTap: () => setState(() => _items.removeAt(e.key)), child: const Icon(Icons.close_rounded, color: DS.red, size: 18))]),
        const SizedBox(height: 8),
        _field('Description', e.value['desc']!),
        _field('Amount', e.value['amount']!),
      ]))),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _items.add({'desc': TextEditingController(text: ''), 'amount': TextEditingController(text: '0.00')})), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add Expense'), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
      _row([const Expanded(child: SizedBox()), Padding(padding: const EdgeInsets.only(top: 8), child: Text('Total: $_currencySymbol${_total.toStringAsFixed(2)}', style: DS.title(size: 18).copyWith(color: DS.green)))]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), build: (_) => pw.Column(children: [
        pw.Text('EXPENSE REPORT', style: _ts(fontSize: 22, bold: true, color: PdfColors.green700)),
        pw.SizedBox(height: 10),
        pw.Row(children: [pw.Text('Employee: ${_employee.text}', style: _ts(fontSize: 11)), pw.Spacer(), pw.Text('Date: ${_date.text}', style: _ts(fontSize: 11))]),
        pw.Text('Department: ${_dept.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 16),
        pw.Container(color: PdfColors.green700, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Row(children: [pw.Expanded(flex: 3, child: pw.Text('Description', style: _ts(fontSize: 10, bold: true, color: PdfColors.white))), pw.Expanded(child: pw.Text('Amount', style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.right))])),
        ..._items.asMap().entries.map((e) {
          final amt = double.tryParse(e.value['amount']!.text) ?? 0;
          return pw.Container(color: e.key.isEven ? PdfColors.grey100 : PdfColors.white, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5), child: pw.Row(children: [pw.Expanded(flex: 3, child: pw.Text(e.value['desc']!.text, style: _ts(fontSize: 9))), pw.Expanded(child: pw.Text('$_currencySymbol${amt.toStringAsFixed(2)}', style: _ts(fontSize: 9), textAlign: pw.TextAlign.right))]));
        }),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text('TOTAL  $_currencySymbol${_total.toStringAsFixed(2)}', style: _ts(fontSize: 14, bold: true, color: PdfColors.green700))]),
      ])));
      final (path, bytes) = await _savePdf(doc, 'expense_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FREELANCE CONTRACT
// ─────────────────────────────────────────────────────────────────────────────

class FreelanceContractForm extends StatefulWidget {
  const FreelanceContractForm({super.key});
  @override
  State<FreelanceContractForm> createState() => _FreelanceContractState();
}

class _FreelanceContractState extends State<FreelanceContractForm> {
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _freelancer = TextEditingController(text: 'Freelancer Name');
  final _client = TextEditingController(text: 'Client Name');
  final _scope = TextEditingController(text: 'Project scope description');
  final _rate = TextEditingController(text: '50');
  final _deadline = TextEditingController(text: 'Dec 31, 2026');
  bool _b = false;

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Freelance Contract',
    icon: Icons.person_rounded,
    color: DS.purple,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('Freelancer', _freelancer)), Expanded(child: _field('Client', _client))]),
      _field('Scope of Work', _scope, maxLines: 3),
      _row([Expanded(child: _field('Hourly Rate / Fixed Fee', _rate)), Expanded(child: _field('Deadline', _deadline))]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text('FREELANCE CONTRACT', style: _ts(fontSize: 20, bold: true)),
        pw.SizedBox(height: 16),
        pw.Text('This Agreement is between ${_freelancer.text} ("Freelancer") and ${_client.text} ("Client").', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text('Scope of Work:', style: _ts(fontSize: 11, bold: true)),
        pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(border: pw.Border.all()), child: pw.Text(_scope.text, style: _ts(fontSize: 10))),
        pw.SizedBox(height: 8),
        pw.Row(children: [pw.Text('Compensation: $_currencySymbol${_rate.text}', style: _ts(fontSize: 11)), pw.Spacer(), pw.Text('Deadline: ${_deadline.text}', style: _ts(fontSize: 11))]),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_freelancer.text}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_client.text}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'freelance_contract_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RENTAL AGREEMENT
// ─────────────────────────────────────────────────────────────────────────────

class RentalAgreementForm extends StatefulWidget {
  const RentalAgreementForm({super.key});
  @override
  State<RentalAgreementForm> createState() => _RentalAgreementState();
}

class _RentalAgreementState extends State<RentalAgreementForm> {
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _landlord = TextEditingController(text: 'Landlord Name');
  final _tenant = TextEditingController(text: 'Tenant Name');
  final _property = TextEditingController(text: 'Property Address');
  final _rent = TextEditingController(text: '1200');
  final _start = TextEditingController(text: 'June 1, 2026');
  final _end = TextEditingController(text: 'May 31, 2027');
  bool _b = false;

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Rental Agreement',
    icon: Icons.home_rounded,
    color: DS.orange,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('Landlord', _landlord)), Expanded(child: _field('Tenant', _tenant))]),
      _field('Property Address', _property),
      _row([Expanded(child: _field('Monthly Rent', _rent)), Expanded(child: _field('Start Date', _start)), Expanded(child: _field('End Date', _end))]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text('RESIDENTIAL RENTAL AGREEMENT', style: _ts(fontSize: 18, bold: true)),
        pw.SizedBox(height: 16),
        pw.Text('This Agreement is made between ${_landlord.text} ("Landlord") and ${_tenant.text} ("Tenant") for the property at ${_property.text}.', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text('Term: From ${_start.text} to ${_end.text}.', style: _ts(fontSize: 11)),
        pw.Text('Monthly Rent: $_currencySymbol${_rent.text}.', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 20),
        pw.Text('Additional terms: Tenant agrees to maintain the property and pay utilities.', style: _ts(fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_landlord.text}  Signature', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_tenant.text}  Signature', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'rental_agreement_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NON-COMPETE
// ─────────────────────────────────────────────────────────────────────────────

class NonCompeteForm extends StatefulWidget {
  const NonCompeteForm({super.key});
  @override
  State<NonCompeteForm> createState() => _NonCompeteState();
}

class _NonCompeteState extends State<NonCompeteForm> {
  final _employee = TextEditingController(text: 'Employee Name');
  final _company = TextEditingController(text: 'Company Name');
  final _duration = TextEditingController(text: '12 months');
  final _radius = TextEditingController(text: '50 miles');
  bool _b = false;

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Non-Compete',
    icon: Icons.block_rounded,
    color: DS.red,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      _row([Expanded(child: _field('Employee', _employee)), Expanded(child: _field('Company', _company))]),
      _row([Expanded(child: _field('Duration', _duration)), Expanded(child: _field('Geographic Radius', _radius))]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text('NON-COMPETE AGREEMENT', style: _ts(fontSize: 18, bold: true, color: PdfColors.red900)),
        pw.SizedBox(height: 16),
        pw.Text('This Non-Compete Agreement is between ${_company.text} ("Company") and ${_employee.text} ("Employee").', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text('For a period of ${_duration.text} within ${_radius.text} of the Company\'s business, Employee agrees not to engage in any competing business.', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_company.text}  Representative', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_employee.text}  Signature', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'non_compete_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPLOYMENT CONTRACT
// ─────────────────────────────────────────────────────────────────────────────

class EmploymentContractForm extends StatefulWidget {
  const EmploymentContractForm({super.key});
  @override
  State<EmploymentContractForm> createState() => _EmploymentContractState();
}

class _EmploymentContractState extends State<EmploymentContractForm> {
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _employee = TextEditingController(text: 'Employee Name');
  final _employer = TextEditingController(text: 'Employer Name');
  final _position = TextEditingController(text: 'Job Title');
  final _salary = TextEditingController(text: '60000');
  final _start = TextEditingController(text: 'June 1, 2026');
  bool _b = false;

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Employment Contract',
    icon: Icons.work_rounded,
    color: DS.indigo,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('Employee', _employee)), Expanded(child: _field('Employer', _employer))]),
      _row([Expanded(child: _field('Position', _position)), Expanded(child: _field('Start Date', _start))]),
      _field('Annual Salary', _salary),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text('EMPLOYMENT CONTRACT', style: _ts(fontSize: 20, bold: true, color: PdfColors.indigo900)),
        pw.SizedBox(height: 16),
        pw.Text('This Employment Contract is entered into between ${_employer.text} ("Employer") and ${_employee.text} ("Employee").', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text('Position: ${_position.text}', style: _ts(fontSize: 11)),
        pw.Text('Start Date: ${_start.text}', style: _ts(fontSize: 11)),
        pw.Text('Annual Salary: $_currencySymbol${_salary.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 20),
        pw.Text('Standard terms: 40 hours/week, 15 days paid leave.', style: _ts(fontSize: 9, color: PdfColors.grey600)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_employer.text}  Signature', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_employee.text}  Signature', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'employment_contract_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TERMINATION LETTER
// ─────────────────────────────────────────────────────────────────────────────

class TerminationLetterForm extends StatefulWidget {
  const TerminationLetterForm({super.key});
  @override
  State<TerminationLetterForm> createState() => _TerminationLetterState();
}

class _TerminationLetterState extends State<TerminationLetterForm> {
  final _employee = TextEditingController(text: 'Employee Name');
  final _company = TextEditingController(text: 'Company Name');
  final _reason = TextEditingController(text: 'Reason for termination');
  final _effective = TextEditingController(text: _today());
  bool _b = false;
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Termination Letter',
    icon: Icons.exit_to_app_rounded,
    color: DS.red,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      _row([Expanded(child: _field('Employee', _employee)), Expanded(child: _field('Company', _company))]),
      _field('Reason for Termination', _reason, maxLines: 3),
      _field('Effective Date', _effective),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
     // Inside TerminationLetterForm._gen()
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(50),
        build: (_) => [
          pw.Text('TERMINATION LETTER', style: _ts(fontSize: 20, bold: true, color: PdfColors.red900)),
          pw.SizedBox(height: 16),
          pw.Text('Dear ${_employee.text},', style: _ts(fontSize: 12)),
          pw.SizedBox(height: 10),
          pw.Text('This letter confirms the termination of your employment with ${_company.text}, effective ${_effective.text}.', style: _ts(fontSize: 11)),
          pw.Text('Reason: ${_reason.text}', style: _ts(fontSize: 11).copyWith(fontStyle: pw.FontStyle.italic)), // ✅ fixed
          pw.SizedBox(height: 20),
          pw.Text('Please return all company property. Your final paycheck will be processed.', style: _ts(fontSize: 10)),
          pw.SizedBox(height: 40),
          pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_company.text}  Representative', style: _ts(fontSize: 9))]))]),
        ],
      ));
      final (path, bytes) = await _savePdf(doc, 'termination_${_employee.text.replaceAll(' ', '_')}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS PROPOSAL
// ─────────────────────────────────────────────────────────────────────────────

class BusinessProposalForm extends StatefulWidget {
  const BusinessProposalForm({super.key});
  @override
  State<BusinessProposalForm> createState() => _BusinessProposalState();
}

class _BusinessProposalState extends State<BusinessProposalForm> {
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _from = TextEditingController(text: 'Your Company');
  final _to = TextEditingController(text: 'Client Company');
  final _project = TextEditingController(text: 'Project Title');
  final _budget = TextEditingController(text: '10000');
  final _timeline = TextEditingController(text: '3 months');
  bool _b = false;

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Business Proposal',
    icon: Icons.lightbulb_rounded,
    color: DS.orange,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      Row(children: [const Text('Currency: ', style: TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
      _row([Expanded(child: _field('From', _from)), Expanded(child: _field('To', _to))]),
      _field('Project / Proposal Title', _project),
      _row([Expanded(child: _field('Estimated Budget', _budget)), Expanded(child: _field('Timeline', _timeline))]),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text('BUSINESS PROPOSAL', style: _ts(fontSize: 22, bold: true, color: PdfColors.orange700)),
        pw.SizedBox(height: 8),
        pw.Text('Prepared for: ${_to.text}', style: _ts(fontSize: 12)),
        pw.Text('Prepared by: ${_from.text}', style: _ts(fontSize: 12)),
        pw.SizedBox(height: 16),
        pw.Text('Project: ${_project.text}', style: _ts(fontSize: 14, bold: true)),
        pw.SizedBox(height: 8),
        pw.Text('Budget: $_currencySymbol${_budget.text}', style: _ts(fontSize: 11)),
        pw.Text('Timeline: ${_timeline.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 16),
        pw.Text('We are excited to present this proposal. Our team will deliver high-quality results within the agreed timeline.', style: _ts(fontSize: 10)),
      ]));
      final (path, bytes) = await _savePdf(doc, 'proposal_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEETING MINUTES
// ─────────────────────────────────────────────────────────────────────────────

class MeetingMinutesForm extends StatefulWidget {
  const MeetingMinutesForm({super.key});
  @override
  State<MeetingMinutesForm> createState() => _MeetingMinutesState();
}

class _MeetingMinutesState extends State<MeetingMinutesForm> {
  final _project = TextEditingController(text: 'Project Name');
  final _date = TextEditingController(text: _today());
  final _attendees = TextEditingController(text: 'List of attendees');
  final _notes = TextEditingController(text: 'Meeting notes and decisions');
  bool _b = false;
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  Widget build(BuildContext c) => _Scaffold(
    title: 'Meeting Minutes',
    icon: Icons.event_note_rounded,
    color: DS.cyan,
    onGenerate: _b ? null : _gen,
    building: _b,
    child: Column(children: [
      _row([Expanded(child: _field('Project', _project)), Expanded(child: _field('Date', _date))]),
      _field('Attendees', _attendees, maxLines: 2),
      _field('Minutes / Decisions', _notes, maxLines: 5),
    ]),
  );

  Future<void> _gen() async {
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text('MEETING MINUTES', style: _ts(fontSize: 20, bold: true, color: PdfColors.cyan900)),
        pw.SizedBox(height: 8),
        pw.Text('Project: ${_project.text}   |   Date: ${_date.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 8),
        pw.Text('Attendees: ${_attendees.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text('Minutes:', style: _ts(fontSize: 12, bold: true)),
        pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(border: pw.Border.all()), child: pw.Text(_notes.text, style: _ts(fontSize: 10))),
      ]));
      final (path, bytes) = await _savePdf(doc, 'meeting_minutes_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESUME / CV (with Fresher/Experienced toggle, photo optional, dynamic sections)
// ─────────────────────────────────────────────────────────────────────────────

enum ProfileType { fresher, experienced }

class ResumeForm extends StatefulWidget {
  const ResumeForm({super.key});
  @override
  State<ResumeForm> createState() => _ResumeFormState();
}

class _ResumeFormState extends State<ResumeForm> {
  ProfileType _profileType = ProfileType.fresher;
  static const _teal = Color(0xFF20B2AA);

  // Personal
  final _fullName = TextEditingController(text: 'John Doe');
  final _jobTitle = TextEditingController(text: 'Software Engineer');
  final _email = TextEditingController(text: 'john@example.com');
  final _phone = TextEditingController(text: '+1234567890');
  final _location = TextEditingController(text: 'New York, NY');
  final _linkedin = TextEditingController(text: 'linkedin.com/in/johndoe');
  final _summary = TextEditingController(text: 'Motivated developer with...');

  // Education
  final _degree = TextEditingController(text: 'B.Sc. Computer Science');
  final _institution = TextEditingController(text: 'University Name');
  final _eduYear = TextEditingController(text: '2020-2024');
  final _gpa = TextEditingController(text: '3.8/4.0');

  // Dynamic sections
  List<Map<String, TextEditingController>> _workExperiences = [];
  List<Map<String, TextEditingController>> _projects = [];
  List<TextEditingController> _skills = [];
  List<Map<String, TextEditingController>> _certifications = [];
  List<TextEditingController> _achievements = [];

  // Photo
  Uint8List? _photoBytes;
  bool _building = false;

  @override
  void initState() {
    super.initState();
    _addWorkExperience();
    _addProject();
    _addSkill();
    _addCertification();
    _addAchievement();
  }

  void _addWorkExperience() {
    if (_workExperiences.length < 4) {
      setState(() {
        _workExperiences.add({
          'title': TextEditingController(text: _profileType == ProfileType.fresher ? 'Intern' : 'Position Title'),
          'company': TextEditingController(text: 'Company Name'),
          'date': TextEditingController(text: 'Jan 2025 - Present'),
          'desc': TextEditingController(text: '• Achieved X\n• Led Y'),
        });
      });
    }
  }
  void _addProject() {
    if (_projects.length < 4) {
      setState(() {
        _projects.add({
          'name': TextEditingController(text: 'Project Name'),
          'tech': TextEditingController(text: 'Flutter, Firebase'),
          'desc': TextEditingController(text: 'Description of project'),
        });
      });
    }
  }
  void _addSkill() {
    if (_skills.length < 20) {
      setState(() => _skills.add(TextEditingController(text: 'Skill')));
    }
  }
  void _addCertification() {
    if (_certifications.length < 4) {
      setState(() {
        _certifications.add({
          'name': TextEditingController(text: 'Certification Name'),
          'org': TextEditingController(text: 'Issuing Organization'),
          'year': TextEditingController(text: '2025'),
        });
      });
    }
  }
  void _addAchievement() {
    if (_achievements.length < 4) {
      setState(() => _achievements.add(TextEditingController(text: 'Achievement description')));
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _photoBytes = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Scaffold(
      title: 'Resume / CV',
      icon: Icons.description_rounded,
      color: _teal,
      onGenerate: _building ? null : _generate,
      building: _building,
      child: Column(children: [
        // Profile type toggle
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(30)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _profileToggle('Fresher', ProfileType.fresher),
            const SizedBox(width: 8),
            _profileToggle('Experienced', ProfileType.experienced),
          ]),
        ),
        // Photo upload
        Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)), child: Row(children: [
          if (_photoBytes != null) CircleAvatar(radius: 30, backgroundImage: MemoryImage(_photoBytes!))
          else CircleAvatar(radius: 30, backgroundColor: DS.bgCard2, child: const Icon(Icons.person, color: DS.textSecondary)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Photo (optional)', style: DS.body(size:13).copyWith(fontWeight: FontWeight.w600)), Text('Appears on resume', style: DS.caption().copyWith(fontSize: 11))])),
          TextButton(onPressed: _pickPhoto, child: Text(_photoBytes != null ? 'Change' : 'Upload', style: const TextStyle(color: DS.indigo, fontSize: 12, fontWeight: FontWeight.w600))),
        ])),
        const SectionHeader('PERSONAL DETAILS'),
        _field('Full Name', _fullName),
        _field('Job Title (optional)', _jobTitle),
        _row([Expanded(child: _field('Email', _email)), Expanded(child: _field('Phone', _phone))]),
        _row([Expanded(child: _field('Location', _location)), Expanded(child: _field('LinkedIn / Portfolio', _linkedin))]),
        if (_profileType == ProfileType.experienced) _field('Professional Summary', _summary, maxLines: 3),
        const SectionHeader('EDUCATION'),
        _row([Expanded(child: _field('Degree', _degree)), Expanded(child: _field('Institution', _institution))]),
        _row([Expanded(child: _field('Year / Duration', _eduYear)), Expanded(child: _field('GPA / Percentage', _gpa))]),
        SectionHeader(_profileType == ProfileType.fresher ? 'INTERNSHIPS' : 'WORK EXPERIENCE'),
        ..._workExperiences.asMap().entries.map((e) => _dynamicCard(
          index: e.key,
          title: _profileType == ProfileType.fresher ? 'Internship' : 'Experience',
          controllers: e.value,
          fields: const ['title', 'company', 'date', 'desc'],
          labels: const ['Title / Role', 'Company', 'Duration', 'Description (bullet points)'],
          onDelete: _workExperiences.length > 1 ? () => setState(() => _workExperiences.removeAt(e.key)) : null,
        )),
        TextButton.icon(onPressed: _addWorkExperience, icon: const Icon(Icons.add, size: 16), label: Text(_profileType == ProfileType.fresher ? 'Add Internship' : 'Add Work Experience'), style: TextButton.styleFrom(foregroundColor: _teal)),
        const SectionHeader('PROJECTS'),
        ..._projects.asMap().entries.map((e) => _dynamicCard(
          index: e.key,
          title: 'Project',
          controllers: e.value,
          fields: const ['name', 'tech', 'desc'],
          labels: const ['Project Name', 'Technologies Used', 'Description'],
          onDelete: _projects.length > 1 ? () => setState(() => _projects.removeAt(e.key)) : null,
        )),
        TextButton.icon(onPressed: _addProject, icon: const Icon(Icons.add, size: 16), label: const Text('Add Project'), style: TextButton.styleFrom(foregroundColor: _teal)),
        const SectionHeader('SKILLS'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ..._skills.asMap().entries.map((e) => Chip(
            label: Text(e.value.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
            backgroundColor: _teal.withOpacity(0.2),
            deleteIcon: const Icon(Icons.close, size: 16, color: DS.red),
            onDeleted: () => setState(() => _skills.removeAt(e.key)),
          )),
          ActionChip(
            label: const Text('+ Add Skill', style: TextStyle(color: _teal, fontSize: 12)),
            onPressed: _addSkill,
            backgroundColor: DS.bgCard,
          ),
        ]),
        const SectionHeader('CERTIFICATIONS'),
        ..._certifications.asMap().entries.map((e) => _dynamicCard(
          index: e.key,
          title: 'Certification',
          controllers: e.value,
          fields: const ['name', 'org', 'year'],
          labels: const ['Certification Name', 'Issuing Organization', 'Year'],
          onDelete: _certifications.length > 1 ? () => setState(() => _certifications.removeAt(e.key)) : null,
        )),
        TextButton.icon(onPressed: _addCertification, icon: const Icon(Icons.add, size: 16), label: const Text('Add Certification'), style: TextButton.styleFrom(foregroundColor: _teal)),
        const SectionHeader('ACHIEVEMENTS'),
        ..._achievements.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: DS.separator)),
          child: Row(children: [
            Expanded(child: TextField(controller: e.value, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: const InputDecoration(border: InputBorder.none, hintText: 'Achievement', hintStyle: TextStyle(color: DS.textSecondary)))),
            IconButton(icon: const Icon(Icons.close, size: 18, color: DS.red), onPressed: () => setState(() => _achievements.removeAt(e.key))),
          ]),
        )),
        TextButton.icon(onPressed: _addAchievement, icon: const Icon(Icons.add, size: 16), label: const Text('Add Achievement'), style: TextButton.styleFrom(foregroundColor: _teal)),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _profileToggle(String label, ProfileType type) {
    final isSelected = _profileType == type;
    return GestureDetector(
      onTap: () => setState(() => _profileType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _teal : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : DS.textSecondary, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _dynamicCard({required int index, required String title, required Map<String, TextEditingController> controllers, required List<String> fields, required List<String> labels, VoidCallback? onDelete}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)),
      child: Column(children: [
        Row(children: [Text('$title ${index+1}', style: DS.caption()), const Spacer(), if(onDelete != null) GestureDetector(onTap: onDelete, child: const Icon(Icons.close_rounded, color: DS.red, size: 18))]),
        const SizedBox(height: 8),
        for (int i=0; i<fields.length; i++) _field(labels[i], controllers[fields[i]]!),
      ]),
    );
  }

  Future<void> _generate() async {
    setState(() => _building = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      pw.MemoryImage? photoImg = _photoBytes != null ? pw.MemoryImage(_photoBytes!) : null;
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(_fullName.text, style: _ts(fontSize: 24, bold: true)),
                if (_jobTitle.text.isNotEmpty) pw.Text(_jobTitle.text, style: _ts(fontSize: 12, color: PdfColors.grey700)),
                pw.SizedBox(height: 4),
                pw.Text('${_email.text}  |  ${_phone.text}  |  ${_location.text}', style: _ts(fontSize: 9, color: PdfColors.grey600)),
                if (_linkedin.text.isNotEmpty) pw.Text(_linkedin.text, style: _ts(fontSize: 9, color: PdfColors.blue)),
              ]),
            ),
            if (photoImg != null) pw.Container(width: 60, height: 60, child: pw.Image(photoImg, fit: pw.BoxFit.cover)),
          ]),
          pw.SizedBox(height: 8),
          pw.Divider(),
          if (_profileType == ProfileType.experienced && _summary.text.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(_summary.text, style: _ts(fontSize: 10)),
            pw.SizedBox(height: 6),
            pw.Divider(),
          ],
          // Education
          _sectionHeader('EDUCATION'),
          pw.Row(children: [pw.Expanded(child: pw.Text(_degree.text, style: _ts(fontSize: 11, bold: true))), pw.Text(_eduYear.text, style: _ts(fontSize: 10, color: PdfColors.grey600))]),
          pw.Text(_institution.text, style: _ts(fontSize: 10)),
          if (_gpa.text.isNotEmpty) pw.Text('GPA: ${_gpa.text}', style: _ts(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          // Work Experience
          _sectionHeader(_profileType == ProfileType.fresher ? 'INTERNSHIPS' : 'WORK EXPERIENCE'),
          ..._workExperiences.map((exp) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [pw.Expanded(child: pw.Text(exp['title']!.text, style: _ts(fontSize: 11, bold: true))), pw.Text(exp['date']!.text, style: _ts(fontSize: 10, color: PdfColors.grey600))]),
            pw.Text(exp['company']!.text, style: _ts(fontSize: 10)),
            pw.Padding(padding: const pw.EdgeInsets.only(left: 12, top: 4), child: pw.Text(exp['desc']!.text.replaceAll('•', '\u2022'), style: _ts(fontSize: 9))),
            pw.SizedBox(height: 6),
          ])),
          // Projects
          if (_projects.isNotEmpty) ...[
            _sectionHeader('PROJECTS'),
            ..._projects.map((proj) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(proj['name']!.text, style: _ts(fontSize: 11, bold: true)),
              pw.Text('Tech: ${proj['tech']!.text}', style: _ts(fontSize: 9, color: PdfColors.grey700)),
              pw.Text(proj['desc']!.text, style: _ts(fontSize: 9)),
              pw.SizedBox(height: 6),
            ])),
          ],
          // Skills
          _sectionHeader('SKILLS'),
          pw.Text(_skills.map((s) => s.text).join(', '), style: _ts(fontSize: 9)),
          pw.SizedBox(height: 8),
          // Certifications
          if (_certifications.isNotEmpty) ...[
            _sectionHeader('CERTIFICATIONS'),
            ..._certifications.map((cert) => pw.Text('• ${cert['name']!.text} (${cert['org']!.text}, ${cert['year']!.text})', style: _ts(fontSize: 9))),
            pw.SizedBox(height: 8),
          ],
          // Achievements
          if (_achievements.isNotEmpty) ...[
            _sectionHeader('ACHIEVEMENTS'),
            ..._achievements.map((ach) => pw.Text( '• ${ach.text}', style: _ts(fontSize: 9))),
          ],
        ],
      ));
      final (path, bytes) = await _savePdf(doc, 'resume_${_fullName.text.replaceAll(' ', '_')}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _building = false); }
  }

  pw.Widget _sectionHeader(String title) => pw.Column(children: [pw.SizedBox(height: 8), pw.Text(title, style: _ts(fontSize: 11, bold: true, color: PdfColors.teal700)), pw.Divider(thickness: 0.5)]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared utilities
// ─────────────────────────────────────────────────────────────────────────────

Future<(String, Uint8List)> _savePdf(pw.Document doc, String name) async {
  final bytes = Uint8List.fromList(await doc.save());
  if (kIsWeb) return ('$name.pdf', bytes);
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
  const _Scaffold({required this.title, required this.icon, required this.color, required this.child, this.onGenerate, required this.building});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DS.bg,
    appBar: AppBar(
      backgroundColor: DS.bgCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20), onPressed: () => Navigator.pop(context)),
      title: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 18), const SizedBox(width: 8), Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))]),
      centerTitle: true,
      actions: [
        if (onGenerate != null)
          TextButton(
            onPressed: building ? null : onGenerate,
            child: building
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo))
                : Text('Generate PDF', style: GoogleFonts.inter(color: DS.indigo, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
      ],
    ),
    body: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        child,
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: building ? null : onGenerate,
            icon: building ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf_rounded, size: 20),
            label: Text(building ? 'Generating...' : 'Generate PDF', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 40),
      ]),
    ),
  );
}

Widget _field(String label, TextEditingController ctrl, {int maxLines = 1, VoidCallback? onChanged}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
    const SizedBox(height: 5),
    TextField(controller: ctrl, maxLines: maxLines, style: const TextStyle(color: Colors.white, fontSize: 14), onChanged: (_) => onChanged?.call(), decoration: InputDecoration(filled: true, fillColor: DS.bgCard, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)))),
  ]),
);

Widget _row(List<Widget> cols) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: cols.expand((w) => [w, if (w != cols.last) const SizedBox(width: 10)]).toList());

class _ItemRow extends StatelessWidget {
  final int index;
  final Map<String, TextEditingController> ctrls;
  final VoidCallback? onDelete;
  final VoidCallback onChanged;
  const _ItemRow({required this.index, required this.ctrls, this.onDelete, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)),
    child: Column(children: [
      Row(children: [Text('#$index', style: DS.caption()), const Spacer(), if (onDelete != null) GestureDetector(onTap: onDelete, child: const Icon(Icons.close_rounded, color: DS.red, size: 18))]),
      const SizedBox(height: 8),
      _field('Description', ctrls['desc']!, onChanged: onChanged),
      Row(children: [Expanded(child: _field('Qty', ctrls['qty']!, onChanged: onChanged)), const SizedBox(width: 10), Expanded(child: _field('Rate (\$)', ctrls['rate']!, onChanged: onChanged))]),
    ]),
  );
}

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(title, style: const TextStyle(color: DS.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)));
}