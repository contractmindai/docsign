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
import '../utils/app_localizations.dart';
import '../services/smart_content_engine.dart';

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
// Currency selector widget
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
    final l10n = AppLocalizations.of(context)!;
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
                return l10n.fieldRequired;
              }
              if (isEmail && !value.contains('@')) {
                return l10n.validEmail;
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
    final l10n = AppLocalizations.of(context)!;
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
  static const _cats = ['All', 'HR', 'Legal', 'Finance', 'Sales', 'Admin', 'Career', 'Food & Retail'];
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
    _Tpl('Restaurant Menu',   Icons.restaurant_rounded,    const Color(0xFFE67E22), 'Food & Retail'),
    _Tpl('Shift Schedule',    Icons.schedule_rounded,      const Color(0xFF2ECC71), 'Food & Retail'),
  ];

  List<_Tpl> get _filtered =>
      _filter == 'All' ? _templates : _templates.where((t) => t.category == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cats = ['All', l10n.hr, l10n.legal, l10n.finance, l10n.sales, l10n.admin, l10n.career, 'Food & Retail'];
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
                    children: cats.map((cat) => Padding(
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
                  child: Text(l10n.clear, style: const TextStyle(fontSize: 12)),
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
    final l10n = AppLocalizations.of(context)!;
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
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                tpl.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: DS.textSecondary, fontSize: 10.5, height: 1.25),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: tpl.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tpl.color.withOpacity(0.3)),
              ),
              child: Text(l10n.fillArrow, style: TextStyle(color: tpl.color, fontSize: 11, fontWeight: FontWeight.w600)),
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
    case 'Restaurant Menu':   return const RestaurantMenuForm();
    case 'Shift Schedule':    return const ShiftScheduleForm();
    default:                  return const _ComingSoonForm();
  }
}

class _ComingSoonForm extends StatelessWidget {
  const _ComingSoonForm();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 20), onPressed: () => Navigator.pop(context)),
        title: Text(l10n.comingSoon, style: const TextStyle(color: DS.textPrimary)),
      ),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.construction_rounded, size: 64, color: DS.indigo),
          const SizedBox(height: 16),
          Text(l10n.comingSoonTitle, style: DS.title()),
          const SizedBox(height: 8),
          Text(l10n.comingSoonMessage, style: DS.body()),
        ]),
      ),
    );
  }
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

  /// Computed description (uses the updated TemplateDescriptions from engine).
  String get description => TemplateDescriptions.describe(name, category);
}

// ─────────────────────────────────────────────────────────────────────────────
// INVOICE FORM (with Payment Terms & Late Fee dropdowns)
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
  final _taxRateController = TextEditingController(text: '10.0');
  String? _logoPath;
  Uint8List? _logoBytes;
  bool _building = false;

  // Payment Terms & Late Fee
  String _paymentTerms = 'Net 30';
  String _lateFeeOption = 'None';
  final _customLateFeePercent = TextEditingController(text: '1.5');

  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';
  static String _dueDate() => '${DateTime.now().add(const Duration(days: 30)).day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  void initState() {
    super.initState();
    _addItem();
    _updateDueDate();
  }

  void _updateDueDate() {
    int days = 30;
    switch (_paymentTerms) {
      case 'Due on receipt': days = 0; break;
      case 'Net 15': days = 15; break;
      case 'Net 30': days = 30; break;
      case 'Net 45': days = 45; break;
      default: days = 30;
    }
    final due = DateTime.now().add(Duration(days: days));
    _due.text = '${due.day}/${due.month}/${due.year}';
  }

  void _addItem() => setState(() => _items.add({
    'desc': TextEditingController(text: 'Professional Services'),
    'qty':  TextEditingController(text: '1'),
    'rate': TextEditingController(text: '250.00'),
  }));
  double get _subtotal => _items.fold(0.0, (s, item) => s + (double.tryParse(item['qty']!.text) ?? 0) * (double.tryParse(item['rate']!.text) ?? 0));
  double get _taxRate => double.tryParse(_taxRateController.text) ?? 0;
  double get _tax => _subtotal * (_taxRate / 100);
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Scaffold(
      title: l10n.invoice,
      icon: Icons.receipt_long_rounded,
      color: DS.indigo,
      onGenerate: _building ? null : _generate,
      building: _building,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(children: [
            Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
            Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)), child: Row(children: [
              if (_logoBytes != null) Container(width: 60, height: 40, child: Image.memory(_logoBytes!, fit: BoxFit.contain))
              else Container(width: 60, height: 40, decoration: BoxDecoration(color: DS.bgCard2, borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.image_rounded, color: DS.textSecondary)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l10n.companyLogo, style: DS.body(size: 13).copyWith(fontWeight: FontWeight.w600)), Text(l10n.logoHint, style: DS.caption().copyWith(fontSize: 11))])),
              TextButton(onPressed: _pickLogo, child: Text(_logoBytes != null ? l10n.change : l10n.upload, style: const TextStyle(color: DS.indigo, fontSize: 12, fontWeight: FontWeight.w600))),
            ])),
            _ResponsiveRow(children: [
              Expanded(child: _RequiredTextField(label: l10n.from, controller: _from)),
              Expanded(child: _RequiredTextField(label: l10n.to, controller: _to)),
            ]),
            _ResponsiveRow(children: [
              Expanded(child: _RequiredTextField(label: l10n.fromAddress, controller: _fromAddr)),
              Expanded(child: _RequiredTextField(label: l10n.clientAddress, controller: _toAddr)),
            ]),
            _ResponsiveRow(children: [
              Expanded(child: _RequiredTextField(label: l10n.invoiceNumber, controller: _invoiceNum)),
              Expanded(child: _field(l10n.issueDate, _date)),
            ]),
            _ResponsiveRow(children: [
              Expanded(child: _field(l10n.dueDate, _due)),
              Expanded(child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Payment Terms', style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    value: _paymentTerms,
                    dropdownColor: DS.bgCard,
                    style: const TextStyle(color: Colors.white),
                    items: ['Due on receipt', 'Net 15', 'Net 30', 'Net 45'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) { setState(() { _paymentTerms = val!; _updateDueDate(); }); },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: DS.bgCard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)),
                    ),
                  ),
                ]),
              )),
            ]),
            // Late Fee
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Late Fee', style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(
                      value: _lateFeeOption,
                      dropdownColor: DS.bgCard,
                      style: const TextStyle(color: Colors.white),
                      items: ['None', '1.5% per month', '2% per month', 'Custom %'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) => setState(() => _lateFeeOption = val!),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: DS.bgCard,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)),
                      ),
                    ),
                  ]),
                ),
                if (_lateFeeOption == 'Custom %') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Rate %', style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _customLateFeePercent,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: DS.bgCard,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)),
                        ),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
            SectionHeader(l10n.lineItems),
            ..._items.asMap().entries.map((e) => _ItemRow(index: e.key+1, ctrls: e.value, onDelete: _items.length>1 ? () => setState(() => _items.removeAt(e.key)) : null, onChanged: () => setState(() {}))),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add_rounded, size: 16), label: Text(l10n.addLineItem), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
            const Divider(color: DS.separator),
            _summRow(l10n.subtotal, '$_currencySymbol${_subtotal.toStringAsFixed(2)}'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${l10n.tax} (', style: DS.body()),
                  SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _taxRateController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                          borderSide: BorderSide(color: DS.separator),
                        ),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Text('%)  ', style: DS.body()),
                  Text('$_currencySymbol${_tax.toStringAsFixed(2)}', style: DS.body(color: DS.textSecondary)),
                ],
              ),
            ),
            _summRow(l10n.total, '$_currencySymbol${_total.toStringAsFixed(2)}', big: true),
            SectionHeader(l10n.qrOptional),
            _RequiredTextField(label: l10n.notesTerms, controller: _notes, maxLines: 3),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => setState(() => _notes.text = SmartWriter.invoiceNotes(clientName: _to.text, dueDate: _due.text)),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: DS.indigo.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, size: 13, color: DS.indigo),
                    SizedBox(width: 5),
                    Text('Auto-write notes', style: TextStyle(color: DS.indigo, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _summRow(String l, String v, {bool big=false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('$l  ', style: big?DS.title():DS.body()), Text(v, style: big?DS.title(size: 20).copyWith(color: DS.indigo):DS.body(color: DS.textSecondary))]));

  Future<void> _generate() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _building = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      pw.MemoryImage? logoImg = _logoBytes != null ? pw.MemoryImage(_logoBytes!) : null;

      // Build late fee text if selected
      String lateFeeText = '';
      if (_lateFeeOption == '1.5% per month') lateFeeText = 'A late charge of 1.5% per month may apply to overdue balances.';
      else if (_lateFeeOption == '2% per month') lateFeeText = 'A late charge of 2% per month may apply to overdue balances.';
      else if (_lateFeeOption == 'Custom %') {
        final rate = double.tryParse(_customLateFeePercent.text) ?? 0;
        if (rate > 0) lateFeeText = 'A late charge of ${rate}% per month may apply to overdue balances.';
      }

      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), build: (_) => [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(l10n.invoice.toUpperCase(), style: _ts(fontSize: 28, bold: true, color: PdfColors.indigo900)),
            pw.SizedBox(height: 4),
            pw.Text(_from.text, style: _ts(fontSize: 13, color: PdfColors.grey700)),
            pw.Text(_fromAddr.text, style: _ts(fontSize: 10, color: PdfColors.grey500)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            if (logoImg != null) pw.Image(logoImg, width: 80, height: 40, fit: pw.BoxFit.contain),
            pw.SizedBox(height: 8),
            pw.Text(_invoiceNum.text, style: _ts(fontSize: 14, bold: true)),
            pw.Text('${l10n.date}: ${_date.text}', style: _ts(fontSize: 10, color: PdfColors.grey600)),
            pw.Text('${l10n.due}: ${_due.text}', style: _ts(fontSize: 10, color: PdfColors.red)),
            pw.Text('Payment Terms: $_paymentTerms', style: _ts(fontSize: 9, color: PdfColors.grey600)),
          ]),
        ]),
        pw.Divider(color: PdfColors.indigo900, thickness: 2),
        pw.SizedBox(height: 10),
        pw.Row(children: [pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(l10n.billTo.toUpperCase(), style: _ts(fontSize: 9, bold: true, color: PdfColors.grey500)), pw.Text(_to.text, style: _ts(fontSize: 13, bold: true)), pw.Text(_toAddr.text, style: _ts(fontSize: 10, color: PdfColors.grey600))]))]),
        pw.SizedBox(height: 20),
        _tableHeader([l10n.description, l10n.qty, l10n.unitPrice, l10n.total]),
        ..._items.asMap().entries.map((e) {
          final qty = double.tryParse(e.value['qty']!.text) ?? 0;
          final rate = double.tryParse(e.value['rate']!.text) ?? 0;
          return _tableRow([e.value['desc']!.text, qty.toInt().toString(), '$_currencySymbol${rate.toStringAsFixed(2)}', '$_currencySymbol${(qty*rate).toStringAsFixed(2)}'], even: e.key.isEven);
        }),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _totalRow(l10n.subtotal, '$_currencySymbol${_subtotal.toStringAsFixed(2)}'),
          _totalRow(l10n.tax, '$_currencySymbol${_tax.toStringAsFixed(2)}'),
          pw.Divider(color: PdfColors.indigo900),
          _totalRow(l10n.total, '$_currencySymbol${_total.toStringAsFixed(2)}', bold: true),
        ])]),
        if (lateFeeText.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(lateFeeText, style: _ts(fontSize: 9, color: PdfColors.red)),
        ],
        if (_qrData.text.trim().isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: _qrData.text.trim(), width: 70, height: 70),
            pw.Text(l10n.scanToPay, style: _ts(fontSize: 6, color: PdfColors.grey500)),
          ])]),
        ],
        if (_notes.text.trim().isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text(l10n.notes, style: _ts(fontSize: 10, bold: true)),
          pw.Text(_notes.text, style: _ts(fontSize: 9, color: PdfColors.grey600)),
        ],
      ]));
      final (path, bytes) = await _savePdf(doc, '${l10n.invoice}_${_invoiceNum.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _building = false); }
  }

  pw.Widget _tableHeader(List<String> cols) => pw.Container(color: PdfColors.indigo900, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7), child: pw.Row(children: cols.asMap().entries.map((e) => pw.Expanded(flex: e.key==0?4:1, child: pw.Text(e.value, textAlign: e.key==0?pw.TextAlign.left:pw.TextAlign.right, style: _ts(fontSize: 9, bold: true, color: PdfColors.white)))).toList()));
  pw.Widget _tableRow(List<String> cols, {bool even=true}) => pw.Container(color: even?PdfColors.grey100:PdfColors.white, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Row(children: cols.asMap().entries.map((e) => pw.Expanded(flex: e.key==0?4:1, child: pw.Text(e.value, textAlign: e.key==0?pw.TextAlign.left:pw.TextAlign.right, style: _ts(fontSize: 9)))).toList()));
  pw.Widget _totalRow(String k, String v, {bool bold=false}) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Row(children: [pw.SizedBox(width: 100, child: pw.Text(k, textAlign: pw.TextAlign.right, style: _ts(fontSize: 10, bold: bold))), pw.SizedBox(width: 60, child: pw.Text(v, textAlign: pw.TextAlign.right, style: _ts(fontSize: bold?13:10, bold: bold, color: bold?PdfColors.indigo900:null)))]));
}

// ─────────────────────────────────────────────────────────────────────────────
// NDA FORM (improved with duration, jurisdiction, and using engine)
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
  final _duration = TextEditingController(text: '2 years');
  final _state = TextEditingController(text: 'California');
  bool _b = false;
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Scaffold(
      title: l10n.nda,
      icon: Icons.gavel_rounded,
      color: DS.orange,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Form(
        key: _formKey,
        child: Column(children: [
          _RequiredTextField(label: l10n.disclosingParty, controller: _p1),
          _RequiredTextField(label: l10n.receivingParty, controller: _p2),
          _ResponsiveRow(children: [
            Expanded(child: _DatePickerField(label: l10n.effectiveDate, controller: _date)),
            Expanded(child: _RequiredTextField(label: 'Duration of Confidentiality', controller: _duration)),
          ]),
          _RequiredTextField(label: 'Governing State/Country', controller: _state),
        ]),
      ),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final ndaText = SmartWriter.nonDisclosureAgreement(
        disclosingParty: _p1.text,
        receivingParty: _p2.text,
      );
      final fullText = 'Effective Date: ${_date.text}\nDuration: ${_duration.text}\n\n$ndaText';
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(52), build: (_) => [
        pw.Text(l10n.ndaTitle, style: _ts(fontSize: 18, bold: true)),
        pw.SizedBox(height: 16),
        pw.Text(fullText, style: _ts(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_p1.text}  ${l10n.signature}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_p2.text}  ${l10n.signature}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'nda_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OFFER LETTER (unchanged, but uses engine)
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
  final _notes = TextEditingController(text: 'Additional terms or conditions...');
  Uint8List? _logoBytes;
  bool _b = false;

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: kIsWeb);
    if (r == null || r.files.isEmpty || !mounted) return;
    final picked = r.files.first;
    final Uint8List? imgBytes = kIsWeb ? picked.bytes : await PlatformFileService.readBytes(picked.path ?? '');
    if (imgBytes == null || imgBytes.isEmpty || !mounted) return;
    final bytes = await PlatformFileService.readBytes(picked.path ?? '') ?? (picked.bytes ?? Uint8List(0));
    setState(() => _logoBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Scaffold(
      title: l10n.offerLetter,
      icon: Icons.mail_rounded,
      color: DS.purple,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        _field(l10n.company, _co),
        _field(l10n.candidateName, _cand),
        _field(l10n.jobTitle, _role, suggestKey: 'jobTitle'),
        _row([Expanded(child: _field(l10n.startDate, _start)), Expanded(child: _field(l10n.offerDeadline, _dl))]),
        _field(l10n.compensation, _sal),
        _LogoPicker(logoBytes: _logoBytes, onPick: _pickLogo),
        _field('Additional Notes / Custom Terms', _notes, maxLines: 4, onSmartWrite: () => SmartWriter.offerNotes(role: _role.text)),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final offerText = SmartWriter.offerLetter(
        company: _co.text,
        candidate: _cand.text,
        position: _role.text,
        startDate: _start.text,
        salary: _sal.text,
      );
      final doc = pw.Document(compress: true);
      pw.MemoryImage? logoImg = _logoBytes != null ? pw.MemoryImage(_logoBytes!) : null;
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(52), build: (_) => [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(_co.text, style: _ts(fontSize: 20, bold: true, color: PdfColors.deepPurple)),
          ]),
          if (logoImg != null) pw.Image(logoImg, width: 80, height: 40, fit: pw.BoxFit.contain),
        ]),
        pw.SizedBox(height: 16),
        pw.Text(offerText, style: _ts(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text(l10n.authorizedSignature, style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_cand.text} — ${l10n.acceptance}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'offer_${_cand.text.replaceAll(' ', '_')}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PURCHASE ORDER (with warranty checkbox)
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
  final _instructions = TextEditingController(text: '');
  final List<Map<String, TextEditingController>> _items = [];
  bool _additionalWarranty = false;
  bool _b = false;

  @override
  void initState() {
    super.initState();
    _items.add({'desc': TextEditingController(text: 'Item Description'), 'qty': TextEditingController(text: '10'), 'price': TextEditingController(text: '50.00')});
  }
  double get _total => _items.fold(0.0, (s, i) => s + (double.tryParse(i['qty']!.text) ?? 0) * (double.tryParse(i['price']!.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Scaffold(
      title: l10n.purchaseOrder,
      icon: Icons.shopping_cart_rounded,
      color: DS.indigo,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.buyer, _buyer)), Expanded(child: _field(l10n.vendor, _vendor))]),
        _row([Expanded(child: _field(l10n.poNumber, _poNum)), Expanded(child: _field(l10n.date, _date))]),
        _row([Expanded(child: _field(l10n.delivery, _del)), Expanded(child: _field(l10n.paymentTerms, _terms))]),
        SectionHeader(l10n.items),
        ..._items.asMap().entries.map((e) => _ItemRow(index: e.key+1, ctrls: Map.from({'desc': e.value['desc']!, 'qty': e.value['qty']!, 'rate': e.value['price']!}), onDelete: _items.length>1 ? () => setState(() => _items.removeAt(e.key)) : null, onChanged: () => setState(() {}))),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _items.add({'desc': TextEditingController(text: l10n.item), 'qty': TextEditingController(text: '1'), 'price': TextEditingController(text: '0.00')})), icon: const Icon(Icons.add_rounded, size: 16), label: Text(l10n.addItem), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
        _row([const Expanded(child: SizedBox()), Padding(padding: const EdgeInsets.only(top: 8), child: Text('${l10n.total}: $_currencySymbol${_total.toStringAsFixed(2)}', style: DS.title(size: 18).copyWith(color: DS.indigo)))]),
        // Warranty checkbox
        Row(children: [
          Checkbox(value: _additionalWarranty, onChanged: (v) => setState(() => _additionalWarranty = v!), activeColor: DS.indigo),
          Text('Additional supplier warranty applies', style: DS.body()),
        ]),
        _field('Special Instructions', _instructions, maxLines: 3, onSmartWrite: () => SmartWriter.purchaseOrderNotes(vendor: _vendor.text, deliveryTerms: _del.text)),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(l10n.purchaseOrderTitle, style: _ts(fontSize: 24, bold: true, color: PdfColors.indigo900)),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('${l10n.buyer}: ${_buyer.text}', style: _ts(fontSize: 11)), pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Text('${l10n.poNumber}: ${_poNum.text}', style: _ts(fontSize: 12, bold: true)), pw.Text('${l10n.date}: ${_date.text}', style: _ts(fontSize: 10, color: PdfColors.grey600))])]),
        pw.Text('${l10n.vendor}: ${_vendor.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 16),
        pw.Container(color: PdfColors.indigo900, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Row(children: [pw.Expanded(flex: 4, child: pw.Text(l10n.item, style: _ts(fontSize: 10, bold: true, color: PdfColors.white))), pw.Expanded(child: pw.Text(l10n.qty, style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.right)), pw.Expanded(child: pw.Text(l10n.price, style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.right)), pw.Expanded(child: pw.Text(l10n.total, style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.right))])),
        ..._items.asMap().entries.map((e) {
          final qty = double.tryParse(e.value['qty']!.text) ?? 0;
          final price = double.tryParse(e.value['price']!.text) ?? 0;
          return pw.Container(color: e.key.isEven ? PdfColors.grey100 : PdfColors.white, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5), child: pw.Row(children: [pw.Expanded(flex: 4, child: pw.Text(e.value['desc']!.text, style: _ts(fontSize: 9))), pw.Expanded(child: pw.Text(qty.toInt().toString(), style: _ts(fontSize: 9), textAlign: pw.TextAlign.right)), pw.Expanded(child: pw.Text('$_currencySymbol${price.toStringAsFixed(2)}', style: _ts(fontSize: 9), textAlign: pw.TextAlign.right)), pw.Expanded(child: pw.Text('$_currencySymbol${(qty*price).toStringAsFixed(2)}', style: _ts(fontSize: 9), textAlign: pw.TextAlign.right))]));
        }),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text('${l10n.total.toUpperCase()}  $_currencySymbol${_total.toStringAsFixed(2)}', style: _ts(fontSize: 14, bold: true, color: PdfColors.indigo900))]),
        pw.SizedBox(height: 14),
        pw.Text('${l10n.delivery}: ${_del.text}  ·  ${l10n.terms}: ${_terms.text}', style: _ts(fontSize: 9, color: PdfColors.grey600)),
        if (_additionalWarranty) pw.Text('Additional supplier warranty applies as per manufacturer\'s terms.', style: _ts(fontSize: 9, color: PdfColors.grey700)),
        if (_instructions.text.trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('Special Instructions:', style: _ts(fontSize: 9, bold: true)),
          pw.Text(_instructions.text, style: _ts(fontSize: 9, color: PdfColors.grey700)),
        ],
      ])));
      final (path, bytes) = await _savePdf(doc, 'po_${_poNum.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE AGREEMENT (enhanced with jurisdiction, payment terms, termination)
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
  final _paymentTerms = TextEditingController(text: 'Net 30');
  final _jurisdiction = TextEditingController(text: 'New York');
  final _terminationNotice = TextEditingController(text: '30 days');
  bool _b = false;

  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.serviceAgreement,
      icon: Icons.handshake_rounded,
      color: DS.green,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.serviceProvider, _sp)), Expanded(child: _field(l10n.client, _cl))]),
        _field(l10n.servicesDescription, _svc, maxLines: 3,
            onSmartWrite: () => SmartWriter.serviceAgreement(
              provider: _sp.text,
              client: _cl.text,
              serviceName: _svc.text,
            )
          ),
        _row([Expanded(child: _field(l10n.feeMonthly, _fee)), Expanded(child: _field('Payment Terms', _paymentTerms))]),
        _row([Expanded(child: _field(l10n.startDate, _start)), Expanded(child: _field(l10n.endDate, _end))]),
        _row([Expanded(child: _field('Jurisdiction', _jurisdiction)), Expanded(child: _field('Termination Notice', _terminationNotice))]),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final agreementText = SmartWriter.serviceAgreement(
        provider: _sp.text,
        client: _cl.text,
        serviceName: _svc.text,
      );
      final customDetails = '''
Payment Terms: ${_paymentTerms.text}
Jurisdiction: ${_jurisdiction.text}
Termination Notice: ${_terminationNotice.text}
''';
      final fullText = '$agreementText\n\nAdditional Details:\n$customDetails';

      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(52), build: (_) => [
        pw.Text(l10n.serviceAgreementTitle, style: _ts(fontSize: 20, bold: true)),
        pw.SizedBox(height: 16),
        pw.Text(fullText, style: _ts(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_sp.text}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_cl.text}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'service_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECEIPT (unchanged)
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
  final _footerNote = TextEditingController(text: '');
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
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.receipt,
      icon: Icons.receipt_rounded,
      color: DS.orange,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.from, _from)), Expanded(child: _field(l10n.to, _to))]),
        _row([Expanded(child: _field(l10n.receiptNumber, _num)), Expanded(child: _field(l10n.date, _date))]),
        SectionHeader(l10n.items),
        ..._items.asMap().entries.map((e) => _ItemRow(index: e.key+1, ctrls: Map.from({'desc': e.value['desc']!, 'qty': e.value['qty']!, 'rate': e.value['price']!}), onDelete: _items.length>1 ? () => setState(() => _items.removeAt(e.key)) : null, onChanged: () => setState(() {}))),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _items.add({'desc': TextEditingController(text: l10n.item), 'qty': TextEditingController(text: '1'), 'price': TextEditingController(text: '0.00')})), icon: const Icon(Icons.add_rounded, size: 16), label: Text(l10n.addItem), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
        Padding(padding: const EdgeInsets.only(top: 8), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('${l10n.total}: $_currencySymbol${_total.toStringAsFixed(2)}', style: DS.title(size: 18).copyWith(color: DS.orange))])),
        _field('Footer Message', _footerNote, maxLines: 2, onSmartWrite: () => SmartWriter.receiptFooterNote(businessName: _from.text)),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.Page(pageFormat: PdfPageFormat(226.77, double.infinity), margin: const pw.EdgeInsets.all(16), build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Text(_from.text, style: _ts(fontSize: 14, bold: true)),
        pw.SizedBox(height: 4),
        pw.Text(l10n.receiptTitle, style: _ts(fontSize: 18, bold: true, color: PdfColors.orange)),
        pw.SizedBox(height: 4),
        pw.Text('${_num.text}  ·  ${_date.text}', style: _ts(fontSize: 8, color: PdfColors.grey600)),
        pw.Divider(),
        pw.Text('${l10n.to}: ${_to.text}', style: _ts(fontSize: 9)),
        pw.Divider(),
        ..._items.map((i) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('${i['desc']!.text} ×${i['qty']!.text}', style: _ts(fontSize: 9)), pw.Text('$_currencySymbol${((double.tryParse(i['qty']!.text)??0)*(double.tryParse(i['price']!.text)??0)).toStringAsFixed(2)}', style: _ts(fontSize: 9))])),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(l10n.total, style: _ts(fontSize: 11, bold: true)), pw.Text('$_currencySymbol${_total.toStringAsFixed(2)}', style: _ts(fontSize: 11, bold: true))]),
        pw.SizedBox(height: 8),
        pw.Text(_footerNote.text.trim().isNotEmpty ? _footerNote.text : l10n.thankYou, style: _ts(fontSize: 8, color: PdfColors.grey500), textAlign: pw.TextAlign.center),
      ])));
      final (path, bytes) = await _savePdf(doc, '${l10n.receipt}_${_num.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUOTATION (with payment terms and late fee)
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
  final _taxRateController = TextEditingController(text: '10.0');
  String _paymentTerms = 'Net 30';
  String _lateFeeOption = 'None';
  final _customLateFeePercent = TextEditingController(text: '1.5');

  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';
  static String _dueDate() => '${DateTime.now().add(const Duration(days: 30)).day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  void initState() {
    super.initState();
    _addItem();
  }
  void _addItem() => setState(() => _items.add({'desc': TextEditingController(text: 'Service/Product'), 'qty': TextEditingController(text: '1'), 'rate': TextEditingController(text: '0.00')}));
  double get _subtotal => _items.fold(0.0, (s, i) => s + (double.tryParse(i['qty']!.text) ?? 0) * (double.tryParse(i['rate']!.text) ?? 0));
  double get _taxRate => double.tryParse(_taxRateController.text) ?? 0;
  double get _tax => _subtotal * (_taxRate / 100);
  double get _total => _subtotal + _tax;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Scaffold(
      title: l10n.quotation,
      icon: Icons.request_quote_rounded,
      color: DS.indigo,
      onGenerate: _building ? null : _generate,
      building: _building,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.from, _from)), Expanded(child: _field(l10n.to, _to))]),
        _row([Expanded(child: _field(l10n.quotationNumber, _quoteNum)), Expanded(child: _field(l10n.date, _date))]),
        _field(l10n.validUntil, _valid),
        // Payment Terms dropdown
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Payment Terms', style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            DropdownButtonFormField<String>(
              value: _paymentTerms,
              dropdownColor: DS.bgCard,
              style: const TextStyle(color: Colors.white),
              items: ['Due on receipt', 'Net 15', 'Net 30', 'Net 45'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) => setState(() => _paymentTerms = val!),
              decoration: InputDecoration(
                filled: true,
                fillColor: DS.bgCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)),
              ),
            ),
          ]),
        ),
        SectionHeader(l10n.lineItems),
        ..._items.asMap().entries.map((e) => _ItemRow(index: e.key+1, ctrls: e.value, onDelete: _items.length>1 ? () => setState(() => _items.removeAt(e.key)) : null, onChanged: () => setState(() {}))),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add_rounded, size: 16), label: Text(l10n.addLineItem), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
        const Divider(),
        _summRow(l10n.subtotal, '$_currencySymbol${_subtotal.toStringAsFixed(2)}'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('${l10n.tax} (', style: DS.body()),
              SizedBox(
                width: 50,
                child: TextField(
                  controller: _taxRateController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                      borderSide: BorderSide(color: DS.separator),
                    ),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Text('%)  ', style: DS.body()),
              Text('$_currencySymbol${_tax.toStringAsFixed(2)}', style: DS.body(color: DS.textSecondary)),
            ],
          ),
        ),
        _summRow(l10n.total, '$_currencySymbol${_total.toStringAsFixed(2)}', big: true),
        _field(l10n.notes, _notes, maxLines: 2, onSmartWrite: () => SmartWriter.quotationNotes(validUntil: _valid.text)),
      ]),
    );
  }

  Widget _summRow(String l, String v, {bool big=false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('$l  ', style: big?DS.title():DS.body()), Text(v, style: big?DS.title(size:20).copyWith(color:DS.indigo):DS.body(color:DS.textSecondary))]));

  Future<void> _generate() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _building = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), build: (_) => [
        pw.Text(l10n.quotationTitle, style: _ts(fontSize: 28, bold: true, color: PdfColors.indigo900)),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(_from.text, style: _ts(fontSize: 13)), pw.Text('${l10n.quotationNumber}: ${_quoteNum.text}', style: _ts(fontSize: 10))]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Text('${l10n.date}: ${_date.text}', style: _ts(fontSize: 10)), pw.Text('${l10n.validUntil}: ${_valid.text}', style: _ts(fontSize: 10, color: PdfColors.red))]),
        ]),
        pw.SizedBox(height: 20),
        pw.Text('${l10n.billTo}: ${_to.text}', style: _ts(fontSize: 12, bold: true)),
        pw.Text('Payment Terms: $_paymentTerms', style: _ts(fontSize: 9, color: PdfColors.grey600)),
        pw.SizedBox(height: 10),
        _tableHeader([l10n.description, l10n.qty, l10n.unitPrice, l10n.total]),
        ..._items.asMap().entries.map((e) {
          final qty = double.tryParse(e.value['qty']!.text) ?? 0;
          final rate = double.tryParse(e.value['rate']!.text) ?? 0;
          return _tableRow([e.value['desc']!.text, qty.toString(), '$_currencySymbol${rate.toStringAsFixed(2)}', '$_currencySymbol${(qty*rate).toStringAsFixed(2)}'], even: e.key.isEven);
        }),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _totalRow(l10n.subtotal, '$_currencySymbol${_subtotal.toStringAsFixed(2)}'),
          _totalRow(l10n.tax, '$_currencySymbol${_tax.toStringAsFixed(2)}'),
          pw.Divider(),
          _totalRow(l10n.total, '$_currencySymbol${_total.toStringAsFixed(2)}', bold: true),
        ])]),
        if (_notes.text.trim().isNotEmpty) ...[pw.SizedBox(height: 16), pw.Text('${l10n.notes}:', style: _ts(fontSize: 10, bold: true)), pw.Text(_notes.text, style: _ts(fontSize: 9, color: PdfColors.grey600))],
      ]));
      final (path, bytes) = await _savePdf(doc, '${l10n.quotation}_${_quoteNum.text}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _building = false); }
  }

  pw.Widget _tableHeader(List<String> cols) => pw.Container(color: PdfColors.indigo900, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7), child: pw.Row(children: cols.asMap().entries.map((e) => pw.Expanded(flex: e.key==0?4:1, child: pw.Text(e.value, textAlign: e.key==0?pw.TextAlign.left:pw.TextAlign.right, style: _ts(fontSize: 9, bold: true, color: PdfColors.white)))).toList()));
  pw.Widget _tableRow(List<String> cols, {bool even=true}) => pw.Container(color: even?PdfColors.grey100:PdfColors.white, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Row(children: cols.asMap().entries.map((e) => pw.Expanded(flex: e.key==0?4:1, child: pw.Text(e.value, textAlign: e.key==0?pw.TextAlign.left:pw.TextAlign.right, style: _ts(fontSize: 9)))).toList()));
  pw.Widget _totalRow(String k, String v, {bool bold=false}) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Row(children: [pw.SizedBox(width: 100, child: pw.Text(k, textAlign: pw.TextAlign.right, style: _ts(fontSize: 10, bold: bold))), pw.SizedBox(width: 60, child: pw.Text(v, textAlign: pw.TextAlign.right, style: _ts(fontSize: bold?13:10, bold: bold, color: bold?PdfColors.indigo900:null)))]));
}

// ─────────────────────────────────────────────────────────────────────────────
// BILL OF SALE (with optional vehicle fields)
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
  final _terms = TextEditingController(text: '');
  bool _b = false;
  bool _isVehicle = false;
  final _make = TextEditingController(text: '');
  final _model = TextEditingController(text: '');
  final _year = TextEditingController(text: '');
  final _vin = TextEditingController(text: '');
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.billOfSale,
      icon: Icons.description_rounded,
      color: DS.orange,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.seller, _seller)), Expanded(child: _field(l10n.buyer, _buyer))]),
        _field(l10n.itemDescription, _item, maxLines: 2),
        _row([Expanded(child: _field(l10n.salePrice, _price)), Expanded(child: _field(l10n.dateOfSale, _date))]),
        // Vehicle toggle
        Row(children: [
          Checkbox(value: _isVehicle, onChanged: (v) => setState(() => _isVehicle = v!), activeColor: DS.orange),
          Text('This is a vehicle sale', style: DS.body()),
        ]),
        if (_isVehicle) ...[
          _row([Expanded(child: _field('Make', _make)), Expanded(child: _field('Model', _model))]),
          _row([Expanded(child: _field('Year', _year)), Expanded(child: _field('VIN', _vin))]),
        ],
        _field('Additional Terms', _terms, maxLines: 4, onSmartWrite: () => SmartWriter.billOfSale(seller: _seller.text, buyer: _buyer.text, item: _item.text)),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text(l10n.billOfSaleTitle, style: _ts(fontSize: 24, bold: true)),
        pw.SizedBox(height: 20),
        pw.Text('${l10n.billOfSaleIntro1} ${_date.text} ${l10n.billOfSaleIntro2} ${_seller.text} ${l10n.billOfSaleIntro3} ${_buyer.text} ${l10n.billOfSaleIntro4}', style: _ts(fontSize: 12)),
        pw.SizedBox(height: 16),
        pw.Text('${l10n.billOfSaleAmount} $_currencySymbol${_price.text}, ${l10n.billOfSaleTransfer} ', style: _ts(fontSize: 12)),
        pw.SizedBox(height: 8),
        pw.Container(padding: const pw.EdgeInsets.all(12), decoration: pw.BoxDecoration(border: pw.Border.all()), child: pw.Text(_item.text, style: _ts(fontSize: 11))),
        if (_isVehicle) ...[
          pw.SizedBox(height: 8),
          pw.Text('Vehicle Details:', style: _ts(fontSize: 10, bold: true)),
          pw.Text('Make: ${_make.text}, Model: ${_model.text}, Year: ${_year.text}, VIN: ${_vin.text}', style: _ts(fontSize: 9)),
        ],
        pw.SizedBox(height: 16),
        pw.Text(
          _terms.text.trim().isNotEmpty
              ? _terms.text
              : SmartWriter.billOfSale(seller: _seller.text, buyer: _buyer.text, item: _item.text),
          style: _ts(fontSize: 9.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${l10n.sellerSignature}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${l10n.buyerSignature}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'bill_of_sale_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPENSE REPORT (unchanged)
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
    _items.add({
      'desc': TextEditingController(text: 'Expense description'),
      'amount': TextEditingController(text: '50.00'),
      'category': TextEditingController(text: 'Travel'),
    });
  }
  double get _total => _items.fold(0.0, (s, i) => s + (double.tryParse(i['amount']!.text) ?? 0));

  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.expenseReport,
      icon: Icons.assessment_rounded,
      color: DS.green,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.employee, _employee)), Expanded(child: _field(l10n.department, _dept, suggestKey: 'department'))]),
        _field(l10n.date, _date),
        SectionHeader(l10n.expenses),
        ..._items.asMap().entries.map((e) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)), child: Column(children: [
          Row(children: [Text('#${e.key+1}', style: DS.caption()), const Spacer(), if(_items.length>1) GestureDetector(onTap: () => setState(() => _items.removeAt(e.key)), child: const Icon(Icons.close_rounded, color: DS.red, size: 18))]),
          const SizedBox(height: 8),
          _field('Category', e.value['category']!, suggestKey: 'expenseCategory'),
          _field(l10n.description, e.value['desc']!, onSmartWrite: () => SmartWriter.expenseDescription(category: e.value['category']!.text)),
          _field(l10n.amount, e.value['amount']!),
        ]))),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _items.add({'desc': TextEditingController(text: ''), 'amount': TextEditingController(text: '0.00'), 'category': TextEditingController(text: 'Travel')})), icon: const Icon(Icons.add_rounded, size: 16), label: Text(l10n.addExpense), style: TextButton.styleFrom(foregroundColor: DS.indigo))),
        _row([const Expanded(child: SizedBox()), Padding(padding: const EdgeInsets.only(top: 8), child: Text('${l10n.total}: $_currencySymbol${_total.toStringAsFixed(2)}', style: DS.title(size: 18).copyWith(color: DS.green)))]),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40), build: (_) => pw.Column(children: [
        pw.Text(l10n.expenseReportTitle, style: _ts(fontSize: 22, bold: true, color: PdfColors.green700)),
        pw.SizedBox(height: 10),
        pw.Row(children: [pw.Text('${l10n.employee}: ${_employee.text}', style: _ts(fontSize: 11)), pw.Spacer(), pw.Text('${l10n.date}: ${_date.text}', style: _ts(fontSize: 11))]),
        pw.Text('${l10n.department}: ${_dept.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 16),
        pw.Container(color: PdfColors.green700, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Row(children: [pw.Expanded(flex: 3, child: pw.Text(l10n.description, style: _ts(fontSize: 10, bold: true, color: PdfColors.white))), pw.Expanded(child: pw.Text(l10n.amount, style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.right))])),
        ..._items.asMap().entries.map((e) {
          final amt = double.tryParse(e.value['amount']!.text) ?? 0;
          final cat = e.value['category']?.text ?? '';
          final descText = cat.isNotEmpty ? '${e.value['desc']!.text}  ($cat)' : e.value['desc']!.text;
          return pw.Container(color: e.key.isEven ? PdfColors.grey100 : PdfColors.white, padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5), child: pw.Row(children: [pw.Expanded(flex: 3, child: pw.Text(descText, style: _ts(fontSize: 9))), pw.Expanded(child: pw.Text('$_currencySymbol${amt.toStringAsFixed(2)}', style: _ts(fontSize: 9), textAlign: pw.TextAlign.right))]));
        }),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text('${l10n.total.toUpperCase()}  $_currencySymbol${_total.toStringAsFixed(2)}', style: _ts(fontSize: 14, bold: true, color: PdfColors.green700))]),
      ])));
      final (path, bytes) = await _savePdf(doc, 'expense_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FREELANCE CONTRACT (enhanced with payment schedule, revisions)
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
  final _paymentSchedule = TextEditingController(text: '50% upfront, 50% on completion');
  final _revisions = TextEditingController(text: '2');
  bool _b = false;

  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.freelanceContract,
      icon: Icons.person_rounded,
      color: DS.purple,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.freelancer, _freelancer)), Expanded(child: _field(l10n.client, _client))]),
        _field(l10n.scopeOfWork, _scope, maxLines: 3,
            onSmartWrite: () => SmartWriter.freelanceContract(
              freelancer: _freelancer.text,
              client: _client.text,
            )
          ),
        _row([Expanded(child: _field(l10n.hourlyRateFixed, _rate)), Expanded(child: _field(l10n.deadline, _deadline))]),
        _row([Expanded(child: _field('Payment Schedule', _paymentSchedule)), Expanded(child: _field('Revisions Included', _revisions))]),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final contractText = SmartWriter.freelanceContract(
        freelancer: _freelancer.text,
        client: _client.text,
      );
      final customDetails = '''
Payment Schedule: ${_paymentSchedule.text}
Revisions: ${_revisions.text}
''';
      final fullText = '$contractText\n\nAdditional Details:\n$customDetails';

      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text(l10n.freelanceContractTitle, style: _ts(fontSize: 20, bold: true)),
        pw.SizedBox(height: 16),
        pw.Text(fullText, style: _ts(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_freelancer.text}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_client.text}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'freelance_contract_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RENTAL AGREEMENT (expanded with utilities, pets, subletting, etc.)
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
  final _terms = TextEditingController(text: '');
  bool _b = false;
  final _propertyType = TextEditingController(text: 'Apartment');
  final _utilities = TextEditingController(text: 'Tenant pays electricity and gas');
  final _petPolicy = TextEditingController(text: 'Pets not allowed');
  final _subletting = TextEditingController(text: 'Not permitted without consent');

  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.rentalAgreement,
      icon: Icons.home_rounded,
      color: DS.orange,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.landlord, _landlord)), Expanded(child: _field(l10n.tenant, _tenant))]),
        _field(l10n.propertyAddress, _property),
        _row([Expanded(child: _field('Property Type', _propertyType)), Expanded(child: _field(l10n.monthlyRent, _rent))]),
        _row([Expanded(child: _field(l10n.startDate, _start)), Expanded(child: _field(l10n.endDate, _end))]),
        _field('Utilities', _utilities),
        _field('Pet Policy', _petPolicy),
        _field('Subletting', _subletting),
        _field(l10n.additionalTerms, _terms, maxLines: 3,
          onSmartWrite: () => SmartWriter.rentalAgreement(
            property: _property.text,
            landlord: _landlord.text,
            tenant: _tenant.text,
          )
        ),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final rentalText = SmartWriter.rentalAgreement(
        property: _property.text,
        landlord: _landlord.text,
        tenant: _tenant.text,
      );
      final customDetails = '''
Property Type: ${_propertyType.text}
Utilities: ${_utilities.text}
Pet Policy: ${_petPolicy.text}
Subletting: ${_subletting.text}
''';
      final fullText = '$rentalText\n\nAdditional Details:\n$customDetails';

      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text(l10n.rentalAgreementTitle, style: _ts(fontSize: 18, bold: true)),
        pw.SizedBox(height: 16),
        pw.Text(fullText, style: _ts(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_landlord.text}  ${l10n.signature}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_tenant.text}  ${l10n.signature}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'rental_agreement_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NON-COMPETE → Post-Employment Restriction Agreement (with disclaimer)
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
  final _terms = TextEditingController(text: '');
  bool _b = false;

  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: 'Post-Employment Restriction Agreement',
      icon: Icons.block_rounded,
      color: DS.red,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        // Disclaimer box
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: DS.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DS.red.withOpacity(0.3)),
          ),
          child: Text(
            'Important: The enforceability of post-employment restrictions varies significantly by jurisdiction. This template is provided for document-preparation purposes and should be reviewed by qualified counsel before use.',
            style: TextStyle(color: DS.red, fontSize: 12),
          ),
        ),
        _row([Expanded(child: _field(l10n.employee, _employee)), Expanded(child: _field(l10n.company, _company))]),
        _row([Expanded(child: _field(l10n.duration, _duration)), Expanded(child: _field(l10n.geographicRadius, _radius))]),
        _field('Additional Terms', _terms, maxLines: 3,
          onSmartWrite: () => SmartWriter.nonCompete(
            company: _company.text,
            employee: _employee.text,
          )
        ),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final nonCompeteText = SmartWriter.nonCompete(
        company: _company.text,
        employee: _employee.text,
      );
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text('Post-Employment Restriction Agreement', style: _ts(fontSize: 18, bold: true, color: PdfColors.red900)),
        pw.SizedBox(height: 16),
        pw.Text(nonCompeteText, style: _ts(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_company.text}  ${l10n.representative}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_employee.text}  ${l10n.signature}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'post_employment_restriction_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPLOYMENT CONTRACT (using engine)
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
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.employmentContract,
      icon: Icons.work_rounded,
      color: DS.indigo,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.employee, _employee)), Expanded(child: _field(l10n.employer, _employer))]),
        _row([Expanded(child: _field(l10n.position, _position, suggestKey: 'jobTitle')), Expanded(child: _field(l10n.startDate, _start))]),
        _field(l10n.annualSalary, _salary),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final contractText = SmartWriter.employmentContract(
        company: _employer.text,
        employee: _employee.text,
        position: _position.text,
        salary: _salary.text,
      );
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text(l10n.employmentContractTitle, style: _ts(fontSize: 20, bold: true, color: PdfColors.indigo900)),
        pw.SizedBox(height: 16),
        pw.Text(contractText, style: _ts(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_employer.text}  ${l10n.signature}', style: _ts(fontSize: 9))])), pw.SizedBox(width: 40), pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_employee.text}  ${l10n.signature}', style: _ts(fontSize: 9))]))]),
      ]));
      final (path, bytes) = await _savePdf(doc, 'employment_contract_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TERMINATION LETTER (unchanged)
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
  final _notes = TextEditingController(text: 'Additional notes or severance details...');
  Uint8List? _logoBytes;
  bool _b = false;
  static String _today() => '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: kIsWeb);
    if (r == null || r.files.isEmpty || !mounted) return;
    final picked = r.files.first;
    final Uint8List? imgBytes = kIsWeb ? picked.bytes : await PlatformFileService.readBytes(picked.path ?? '');
    if (imgBytes == null || imgBytes.isEmpty || !mounted) return;
    final bytes = await PlatformFileService.readBytes(picked.path ?? '') ?? (picked.bytes ?? Uint8List(0));
    setState(() => _logoBytes = bytes);
  }

  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.terminationLetter,
      icon: Icons.exit_to_app_rounded,
      color: DS.red,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        _row([Expanded(child: _field(l10n.employee, _employee)), Expanded(child: _field(l10n.company, _company))]),
        _field(l10n.reasonTermination, _reason, maxLines: 3, onSmartWrite: () => SmartWriter.terminationReason()),
        _field(l10n.effectiveDate, _effective),
        _LogoPicker(logoBytes: _logoBytes, onPick: _pickLogo),
        _field('Additional Notes / Custom Terms', _notes, maxLines: 6, onSmartWrite: () => SmartWriter.terminationLetter(employee: _employee.text, company: _company.text, effectiveDate: _effective.text, reason: _reason.text)),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      pw.MemoryImage? logoImg = _logoBytes != null ? pw.MemoryImage(_logoBytes!) : null;
      final bodyText = _notes.text.trim().isNotEmpty
          ? _notes.text
          : SmartWriter.terminationLetter(employee: _employee.text, company: _company.text, effectiveDate: _effective.text, reason: _reason.text);
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(50),
        build: (_) => [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(l10n.terminationLetterTitle, style: _ts(fontSize: 20, bold: true, color: PdfColors.red900)),
            if (logoImg != null) pw.Image(logoImg, width: 80, height: 40, fit: pw.BoxFit.contain),
          ]),
          pw.SizedBox(height: 16),
          pw.Text('${l10n.dear} ${_employee.text},', style: _ts(fontSize: 12)),
          pw.SizedBox(height: 10),
          pw.Text('${l10n.reason}: ${_reason.text}', style: _ts(fontSize: 11).copyWith(fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 12),
          pw.Text(bodyText, style: _ts(fontSize: 9.5, color: PdfColors.grey700)),
          pw.SizedBox(height: 20),
          pw.Text(l10n.terminationLetterFooter, style: _ts(fontSize: 10)),
          pw.SizedBox(height: 40),
          pw.Row(children: [pw.Expanded(child: pw.Column(children: [pw.Divider(), pw.Text('${_company.text}  ${l10n.representative}', style: _ts(fontSize: 9))]))]),
        ],
      ));
      final (path, bytes) = await _savePdf(doc, 'termination_${_employee.text.replaceAll(' ', '_')}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS PROPOSAL (unchanged)
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
  final _summary = TextEditingController(text: '');
  bool _b = false;

  @override
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.businessProposal,
      icon: Icons.lightbulb_rounded,
      color: DS.orange,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        Row(children: [Text('${l10n.currency}: ', style: const TextStyle(color: DS.textSecondary)), CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c))]),
        _row([Expanded(child: _field(l10n.from, _from)), Expanded(child: _field(l10n.to, _to))]),
        _field(l10n.projectTitle, _project),
        _row([Expanded(child: _field(l10n.estimatedBudget, _budget)), Expanded(child: _field(l10n.timeline, _timeline))]),
        _field('Executive Summary', _summary, maxLines: 5, onSmartWrite: () => SmartWriter.businessProposal(from: _from.text, to: _to.text, project: _project.text, timeline: _timeline.text)),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text(l10n.businessProposalTitle, style: _ts(fontSize: 22, bold: true, color: PdfColors.orange700)),
        pw.SizedBox(height: 8),
        pw.Text('${l10n.preparedFor}: ${_to.text}', style: _ts(fontSize: 12)),
        pw.Text('${l10n.preparedBy}: ${_from.text}', style: _ts(fontSize: 12)),
        pw.SizedBox(height: 16),
        pw.Text('${l10n.project}: ${_project.text}', style: _ts(fontSize: 14, bold: true)),
        pw.SizedBox(height: 8),
        pw.Text('${l10n.budget}: $_currencySymbol${_budget.text}', style: _ts(fontSize: 11)),
        pw.Text('${l10n.timeline}: ${_timeline.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 16),
        pw.Text(
          _summary.text.trim().isNotEmpty
              ? _summary.text
              : SmartWriter.businessProposal(from: _from.text, to: _to.text, project: _project.text, timeline: _timeline.text),
          style: _ts(fontSize: 9.5),
        ),
      ]));
      final (path, bytes) = await _savePdf(doc, 'proposal_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEETING MINUTES (unchanged)
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
  Widget build(BuildContext c) {
    final l10n = AppLocalizations.of(c)!;
    return _Scaffold(
      title: l10n.meetingMinutes,
      icon: Icons.event_note_rounded,
      color: DS.cyan,
      onGenerate: _b ? null : _gen,
      building: _b,
      child: Column(children: [
        _row([Expanded(child: _field(l10n.project, _project)), Expanded(child: _field(l10n.date, _date))]),
        _field(l10n.attendees, _attendees, maxLines: 2),
        _field(l10n.minutesDecisions, _notes, maxLines: 5, onSmartWrite: () => SmartWriter.meetingNotes(project: _project.text)),
      ]),
    );
  }

  Future<void> _gen() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _b = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(50), build: (_) => [
        pw.Text(l10n.meetingMinutesTitle, style: _ts(fontSize: 20, bold: true, color: PdfColors.cyan900)),
        pw.SizedBox(height: 8),
        pw.Text('${l10n.project}: ${_project.text}   |   ${l10n.date}: ${_date.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 8),
        pw.Text('${l10n.attendees}: ${_attendees.text}', style: _ts(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text('${l10n.minutes}:', style: _ts(fontSize: 12, bold: true)),
        pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(border: pw.Border.all()), child: pw.Text(_notes.text, style: _ts(fontSize: 10))),
      ]));
      final (path, bytes) = await _savePdf(doc, 'meeting_minutes_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally { if (mounted) setState(() => _b = false); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESUME / CV (unchanged)
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
    final l10n = AppLocalizations.of(context)!;
    return _Scaffold(
      title: l10n.resume,
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
            _profileToggle(l10n.fresher, ProfileType.fresher),
            const SizedBox(width: 8),
            _profileToggle(l10n.experienced, ProfileType.experienced),
          ]),
        ),
        // Photo upload
        Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)), child: Row(children: [
          if (_photoBytes != null) CircleAvatar(radius: 30, backgroundImage: MemoryImage(_photoBytes!))
          else CircleAvatar(radius: 30, backgroundColor: DS.bgCard2, child: const Icon(Icons.person, color: DS.textSecondary)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l10n.photoOptional, style: DS.body(size:13).copyWith(fontWeight: FontWeight.w600)), Text(l10n.photoHint, style: DS.caption().copyWith(fontSize: 11))])),
          TextButton(onPressed: _pickPhoto, child: Text(_photoBytes != null ? l10n.change : l10n.upload, style: const TextStyle(color: DS.indigo, fontSize: 12, fontWeight: FontWeight.w600))),
        ])),
        SectionHeader(l10n.personalDetails),
        _field(l10n.fullName, _fullName),
        _field(l10n.jobTitleOptional, _jobTitle, suggestKey: 'jobTitle'),
        _row([Expanded(child: _field(l10n.email, _email)), Expanded(child: _field(l10n.phone, _phone))]),
        _row([Expanded(child: _field(l10n.location, _location)), Expanded(child: _field(l10n.linkedinPortfolio, _linkedin))]),
        _field(_profileType == ProfileType.fresher ? l10n.professionalSummary : l10n.professionalSummary, _summary,
          maxLines: 3,
          onSmartWrite: () => SmartWriter.resumeSummary(jobTitle: _jobTitle.text, isFresher: _profileType == ProfileType.fresher),
        ),
        SectionHeader(l10n.education),
        _row([Expanded(child: _field(l10n.degree, _degree)), Expanded(child: _field(l10n.institution, _institution))]),
        _row([Expanded(child: _field(l10n.yearDuration, _eduYear)), Expanded(child: _field(l10n.gpa, _gpa))]),
        SectionHeader(_profileType == ProfileType.fresher ? l10n.internships : l10n.workExperience),
        ..._workExperiences.asMap().entries.map((e) => _dynamicCard(
          index: e.key,
          title: _profileType == ProfileType.fresher ? l10n.internship : l10n.experience,
          controllers: e.value,
          fields: const ['title', 'company', 'date', 'desc'],
          labels: [l10n.titleRole, l10n.company, l10n.duration, l10n.descriptionBullets],
          onDelete: _workExperiences.length > 1 ? () => setState(() => _workExperiences.removeAt(e.key)) : null,
          fieldMaxLines: const {'desc': 4},
          fieldSmartWrite: {'desc': () => SmartWriter.resumeBullets(title: e.value['title']!.text, company: e.value['company']!.text, isFresher: _profileType == ProfileType.fresher)},
        )),
        TextButton.icon(onPressed: _addWorkExperience, icon: const Icon(Icons.add, size: 16), label: Text(_profileType == ProfileType.fresher ? l10n.addInternship : l10n.addWorkExperience), style: TextButton.styleFrom(foregroundColor: _teal)),
        SectionHeader(l10n.projects),
        ..._projects.asMap().entries.map((e) => _dynamicCard(
          index: e.key,
          title: l10n.project,
          controllers: e.value,
          fields: const ['name', 'tech', 'desc'],
          labels: [l10n.projectName, l10n.technologiesUsed, l10n.description],
          onDelete: _projects.length > 1 ? () => setState(() => _projects.removeAt(e.key)) : null,
          fieldMaxLines: const {'desc': 2},
          fieldSmartWrite: {'desc': () => SmartWriter.projectDescription(name: e.value['name']!.text, tech: e.value['tech']!.text)},
        )),
        TextButton.icon(onPressed: _addProject, icon: const Icon(Icons.add, size: 16), label: Text(l10n.addProject), style: TextButton.styleFrom(foregroundColor: _teal)),
        SectionHeader(l10n.skills),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ..._skills.asMap().entries.map((e) => Chip(
            label: Text(e.value.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
            backgroundColor: _teal.withOpacity(0.2),
            deleteIcon: const Icon(Icons.close, size: 16, color: DS.red),
            onDeleted: () => setState(() => _skills.removeAt(e.key)),
          )),
          ActionChip(
            label: Text('+ ${l10n.addSkill}', style: TextStyle(color: _teal, fontSize: 12)),
            onPressed: _addSkill,
            backgroundColor: DS.bgCard,
          ),
        ]),
        SectionHeader(l10n.certifications),
        ..._certifications.asMap().entries.map((e) => _dynamicCard(
          index: e.key,
          title: l10n.certification,
          controllers: e.value,
          fields: const ['name', 'org', 'year'],
          labels: [l10n.certificationName, l10n.issuingOrg, l10n.year],
          onDelete: _certifications.length > 1 ? () => setState(() => _certifications.removeAt(e.key)) : null,
        )),
        TextButton.icon(onPressed: _addCertification, icon: const Icon(Icons.add, size: 16), label: Text(l10n.addCertification), style: TextButton.styleFrom(foregroundColor: _teal)),
        SectionHeader(l10n.achievements),
        ..._achievements.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: DS.separator)),
          child: Row(children: [
            Expanded(child: TextField(controller: e.value, style: const TextStyle(color: Colors.white, fontSize: 13), decoration: InputDecoration(border: InputBorder.none, hintText: l10n.achievementHint, hintStyle: const TextStyle(color: DS.textSecondary)))),
            IconButton(icon: const Icon(Icons.auto_awesome_rounded, size: 16, color: DS.indigo), tooltip: 'Auto-write', onPressed: () => setState(() => e.value.text = SmartWriter.achievement())),
            IconButton(icon: const Icon(Icons.close, size: 18, color: DS.red), onPressed: () => setState(() => _achievements.removeAt(e.key))),
          ]),
        )),
        TextButton.icon(onPressed: _addAchievement, icon: const Icon(Icons.add, size: 16), label: Text(l10n.addAchievement), style: TextButton.styleFrom(foregroundColor: _teal)),
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

  Widget _dynamicCard({
    required int index,
    required String title,
    required Map<String, TextEditingController> controllers,
    required List<String> fields,
    required List<String> labels,
    VoidCallback? onDelete,
    Map<String, int>? fieldMaxLines,
    Map<String, String Function()>? fieldSmartWrite,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)),
      child: Column(children: [
        Row(children: [Text('$title ${index+1}', style: DS.caption()), const Spacer(), if(onDelete != null) GestureDetector(onTap: onDelete, child: const Icon(Icons.close_rounded, color: DS.red, size: 18))]),
        const SizedBox(height: 8),
        for (int i=0; i<fields.length; i++) _field(
          labels[i],
          controllers[fields[i]]!,
          maxLines: fieldMaxLines?[fields[i]] ?? 1,
          onSmartWrite: fieldSmartWrite?[fields[i]],
        ),
      ]),
    );
  }

  Future<void> _generate() async {
    final l10n = AppLocalizations.of(context)!;
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
          if (_summary.text.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(_summary.text, style: _ts(fontSize: 10)),
            pw.SizedBox(height: 6),
            pw.Divider(),
          ],
          // Education
          _sectionHeader(l10n.education),
          pw.Row(children: [pw.Expanded(child: pw.Text(_degree.text, style: _ts(fontSize: 11, bold: true))), pw.Text(_eduYear.text, style: _ts(fontSize: 10, color: PdfColors.grey600))]),
          pw.Text(_institution.text, style: _ts(fontSize: 10)),
          if (_gpa.text.isNotEmpty) pw.Text('GPA: ${_gpa.text}', style: _ts(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          // Work Experience
          _sectionHeader(_profileType == ProfileType.fresher ? l10n.internships : l10n.workExperience),
          ..._workExperiences.map((exp) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [pw.Expanded(child: pw.Text(exp['title']!.text, style: _ts(fontSize: 11, bold: true))), pw.Text(exp['date']!.text, style: _ts(fontSize: 10, color: PdfColors.grey600))]),
            pw.Text(exp['company']!.text, style: _ts(fontSize: 10)),
            pw.Padding(padding: const pw.EdgeInsets.only(left: 12, top: 4), child: pw.Text(exp['desc']!.text.replaceAll('•', '\u2022'), style: _ts(fontSize: 9))),
            pw.SizedBox(height: 6),
          ])),
          // Projects
          if (_projects.isNotEmpty) ...[
            _sectionHeader(l10n.projects),
            ..._projects.map((proj) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(proj['name']!.text, style: _ts(fontSize: 11, bold: true)),
              pw.Text('${l10n.tech}: ${proj['tech']!.text}', style: _ts(fontSize: 9, color: PdfColors.grey700)),
              pw.Text(proj['desc']!.text, style: _ts(fontSize: 9)),
              pw.SizedBox(height: 6),
            ])),
          ],
          // Skills
          _sectionHeader(l10n.skills),
          pw.Text(_skills.map((s) => s.text).join(', '), style: _ts(fontSize: 9)),
          pw.SizedBox(height: 8),
          // Certifications
          if (_certifications.isNotEmpty) ...[
            _sectionHeader(l10n.certifications),
            ..._certifications.map((cert) => pw.Text('• ${cert['name']!.text} (${cert['org']!.text}, ${cert['year']!.text})', style: _ts(fontSize: 9))),
            pw.SizedBox(height: 8),
          ],
          // Achievements
          if (_achievements.isNotEmpty) ...[
            _sectionHeader(l10n.achievements),
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
// RESTAURANT MENU (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class RestaurantMenuForm extends StatefulWidget {
  const RestaurantMenuForm({super.key});
  @override
  State<RestaurantMenuForm> createState() => _RestaurantMenuFormState();
}

class _RestaurantMenuFormState extends State<RestaurantMenuForm> {
  String _currency = 'USD';
  String get _currencySymbol => CurrencySelector.currencies[_currency] ?? '\$';
  final _restaurantName = TextEditingController(text: 'Café Delicious');
  final _tagline = TextEditingController(text: '');
  final List<Map<String, TextEditingController>> _items = [];
  Uint8List? _logoBytes;
  bool _building = false;

  static const _categories = ['Appetizers', 'Mains', 'Desserts', 'Beverages', 'Specials'];

  @override
  void initState() {
    super.initState();
    _addItem();
  }

  void _addItem() {
    setState(() {
      _items.add({
        'name': TextEditingController(text: 'Dish name'),
        'desc': TextEditingController(text: 'Description'),
        'price': TextEditingController(text: '10.00'),
        'category': TextEditingController(text: _categories.first),
      });
    });
  }

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: kIsWeb);
    if (r == null || r.files.isEmpty || !mounted) return;
    final picked = r.files.first;
    final Uint8List? imgBytes = kIsWeb ? picked.bytes : await PlatformFileService.readBytes(picked.path ?? '');
    if (imgBytes == null || imgBytes.isEmpty || !mounted) return;
    final bytes = await PlatformFileService.readBytes(picked.path ?? '') ?? (picked.bytes ?? Uint8List(0));
    setState(() => _logoBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Scaffold(
      title: 'Restaurant Menu',
      icon: Icons.restaurant_rounded,
      color: const Color(0xFFE67E22),
      onGenerate: _building ? null : _generate,
      building: _building,
      child: Column(children: [
        _field('Restaurant Name', _restaurantName),
        _field('Tagline / Intro', _tagline, maxLines: 2, onSmartWrite: () => SmartWriter.restaurantTagline(restaurantName: _restaurantName.text)),
        const SizedBox(height: 8),
        Row(children: [
          Text('Currency: ', style: const TextStyle(color: DS.textSecondary)),
          CurrencySelector(value: _currency, onChanged: (c) => setState(() => _currency = c)),
        ]),
        _LogoPicker(logoBytes: _logoBytes, onPick: _pickLogo),
        SectionHeader('Menu Items'),
        ..._items.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)),
          child: Column(children: [
            Row(children: [
              Text('#${e.key+1}', style: DS.caption()),
              const Spacer(),
              if (_items.length > 1)
                GestureDetector(
                  onTap: () => setState(() => _items.removeAt(e.key)),
                  child: const Icon(Icons.close_rounded, color: DS.red, size: 18),
                ),
            ]),
            const SizedBox(height: 8),
            _field('Item Name', e.value['name']!),
            _field('Description', e.value['desc']!, maxLines: 2, onSmartWrite: () => SmartWriter.menuItemDescription(dishName: e.value['name']!.text, category: e.value['category']!.text)),
            Row(children: [
              Expanded(child: _field('Price', e.value['price']!)),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Category', style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(
                      value: e.value['category']!.text,
                      dropdownColor: DS.bgCard,
                      style: const TextStyle(color: Colors.white),
                      items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                      onChanged: (val) => setState(() => e.value['category']!.text = val!),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: DS.bgCard,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ]),
        )),
        TextButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add Menu Item'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFE67E22)),
        ),
      ]),
    );
  }

  Future<void> _generate() async {
    setState(() => _building = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      pw.MemoryImage? logoImg = _logoBytes != null ? pw.MemoryImage(_logoBytes!) : null;
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(_restaurantName.text, style: _ts(fontSize: 24, bold: true, color: PdfColors.orange700)),
            if (logoImg != null) pw.Image(logoImg, width: 80, height: 40, fit: pw.BoxFit.contain),
          ]),
          pw.SizedBox(height: 4),
          pw.Text('Menu', style: _ts(fontSize: 16, color: PdfColors.grey700)),
          if (_tagline.text.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(_tagline.text, style: _ts(fontSize: 10, color: PdfColors.grey600).copyWith(fontStyle: pw.FontStyle.italic)),
          ],
          pw.Divider(thickness: 2),
          pw.SizedBox(height: 12),
          ..._categories.map((cat) {
            final catItems = _items.where((i) => i['category']!.text == cat).toList();
            if (catItems.isEmpty) return pw.SizedBox.shrink();
            return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(cat.toUpperCase(), style: _ts(fontSize: 14, bold: true, color: PdfColors.orange700)),
              pw.SizedBox(height: 6),
              ...catItems.map((item) {
                final price = double.tryParse(item['price']!.text) ?? 0;
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(children: [
                    pw.Expanded(
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(item['name']!.text, style: _ts(fontSize: 12, bold: true)),
                        pw.Text(item['desc']!.text, style: _ts(fontSize: 9, color: PdfColors.grey600)),
                      ]),
                    ),
                    pw.Text('$_currencySymbol${price.toStringAsFixed(2)}', style: _ts(fontSize: 12, bold: true)),
                  ]),
                );
              }),
              pw.SizedBox(height: 10),
            ]);
          }),
        ],
      ));
      final (path, bytes) = await _savePdf(doc, 'menu_${_restaurantName.text.replaceAll(' ', '_')}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHIFT SCHEDULE (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class ShiftScheduleForm extends StatefulWidget {
  const ShiftScheduleForm({super.key});
  @override
  State<ShiftScheduleForm> createState() => _ShiftScheduleFormState();
}

class _ShiftScheduleFormState extends State<ShiftScheduleForm> {
  final _storeName = TextEditingController(text: 'Main Street Café');
  final _weekStart = TextEditingController(text: _today());
  final List<Map<String, TextEditingController>> _shifts = [];
  Uint8List? _logoBytes;
  bool _building = false;

  static String _today() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  @override
  void initState() {
    super.initState();
    _addShift();
  }

  void _addShift() {
    setState(() {
      _shifts.add({
        'employee': TextEditingController(text: 'Employee'),
        'role': TextEditingController(text: 'Waiter'),
        'date': TextEditingController(text: _today()),
        'start': TextEditingController(text: '09:00'),
        'end': TextEditingController(text: '17:00'),
      });
    });
  }

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: kIsWeb);
    if (r == null || r.files.isEmpty || !mounted) return;
    final picked = r.files.first;
    final Uint8List? imgBytes = kIsWeb ? picked.bytes : await PlatformFileService.readBytes(picked.path ?? '');
    if (imgBytes == null || imgBytes.isEmpty || !mounted) return;
    final bytes = await PlatformFileService.readBytes(picked.path ?? '') ?? (picked.bytes ?? Uint8List(0));
    setState(() => _logoBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Scaffold(
      title: 'Shift Schedule',
      icon: Icons.schedule_rounded,
      color: const Color(0xFF2ECC71),
      onGenerate: _building ? null : _generate,
      building: _building,
      child: Column(children: [
        _field('Store / Venue', _storeName),
        _field('Week Starting', _weekStart),
        _LogoPicker(logoBytes: _logoBytes, onPick: _pickLogo),
        SectionHeader('Shifts'),
        ..._shifts.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)),
          child: Column(children: [
            Row(children: [
              Text('#${e.key+1}', style: DS.caption()),
              const Spacer(),
              if (_shifts.length > 1)
                GestureDetector(
                  onTap: () => setState(() => _shifts.removeAt(e.key)),
                  child: const Icon(Icons.close_rounded, color: DS.red, size: 18),
                ),
            ]),
            const SizedBox(height: 8),
            _row([
              Expanded(child: _field('Employee', e.value['employee']!)),
              Expanded(child: _field('Role', e.value['role']!, suggestKey: 'role')),
            ]),
            _row([
              Expanded(child: _field('Date', e.value['date']!)),
              Expanded(child: _field('Start', e.value['start']!)),
              Expanded(child: _field('End', e.value['end']!)),
            ]),
          ]),
        )),
        TextButton.icon(
          onPressed: _addShift,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add Shift'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF2ECC71)),
        ),
      ]),
    );
  }

  Future<void> _generate() async {
    setState(() => _building = true);
    await PdfSaveService.ensureFontsLoaded();
    try {
      final doc = pw.Document(compress: true);
      pw.MemoryImage? logoImg = _logoBytes != null ? pw.MemoryImage(_logoBytes!) : null;
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(_storeName.text, style: _ts(fontSize: 22, bold: true, color: PdfColors.green700)),
            if (logoImg != null) pw.Image(logoImg, width: 80, height: 40, fit: pw.BoxFit.contain),
          ]),
          pw.SizedBox(height: 4),
          pw.Text('Shift Schedule - Week starting ${_weekStart.text}', style: _ts(fontSize: 12, color: PdfColors.grey600)),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 12),
          pw.Container(
            color: PdfColors.green700,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Row(children: [
              pw.Expanded(flex: 2, child: pw.Text('Employee', style: _ts(fontSize: 10, bold: true, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('Role', style: _ts(fontSize: 10, bold: true, color: PdfColors.white))),
              pw.Expanded(flex: 2, child: pw.Text('Date', style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 1, child: pw.Text('Start', style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 1, child: pw.Text('End', style: _ts(fontSize: 10, bold: true, color: PdfColors.white), textAlign: pw.TextAlign.center)),
            ]),
          ),
          ..._shifts.asMap().entries.map((e) {
            final even = e.key.isEven;
            return pw.Container(
              color: even ? PdfColors.grey100 : PdfColors.white,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Row(children: [
                pw.Expanded(flex: 2, child: pw.Text(e.value['employee']!.text, style: _ts(fontSize: 9))),
                pw.Expanded(flex: 2, child: pw.Text(e.value['role']!.text, style: _ts(fontSize: 9))),
                pw.Expanded(flex: 2, child: pw.Text(e.value['date']!.text, style: _ts(fontSize: 9), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 1, child: pw.Text(e.value['start']!.text, style: _ts(fontSize: 9), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 1, child: pw.Text(e.value['end']!.text, style: _ts(fontSize: 9), textAlign: pw.TextAlign.center)),
              ]),
            );
          }),
        ],
      ));
      final (path, bytes) = await _savePdf(doc, 'shift_schedule_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: path, preloadedBytes: bytes)));
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Logo Picker
// ─────────────────────────────────────────────────────────────────────────────
class _LogoPicker extends StatelessWidget {
  final Uint8List? logoBytes;
  final VoidCallback onPick;
  const _LogoPicker({required this.logoBytes, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DS.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DS.separator),
      ),
      child: Row(children: [
        if (logoBytes != null)
          Container(width: 60, height: 40, child: Image.memory(logoBytes!, fit: BoxFit.contain))
        else
          Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(color: DS.bgCard2, borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.image_rounded, color: DS.textSecondary),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Company Logo', style: DS.body(size: 13).copyWith(fontWeight: FontWeight.w600)),
            Text('Upload a logo to appear on the PDF', style: DS.caption().copyWith(fontSize: 11)),
          ]),
        ),
        TextButton(
          onPressed: onPick,
          child: Text(logoBytes != null ? 'Change' : 'Upload', style: const TextStyle(color: DS.indigo, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
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

// ─────────────────────────────────────────────────────────────────────────────
// _Scaffold with FIXED AppBar – no collision between title and Generate button
// ─────────────────────────────────────────────────────────────────────────────
class _Scaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final VoidCallback? onGenerate;
  final bool building;
  const _Scaffold({required this.title, required this.icon, required this.color, required this.child, this.onGenerate, required this.building});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
        // 🔥 FIX: title now uses a flexible row with ellipsis, and centerTitle: false
        // so the title never overlaps the "Generate PDF" action button.
        title: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          if (onGenerate != null)
            TextButton(
              onPressed: building ? null : onGenerate,
              child: building
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo))
                  : Text(l10n.generatePdf, style: GoogleFonts.inter(color: DS.indigo, fontSize: 14, fontWeight: FontWeight.w600)),
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
              label: Text(building ? l10n.generating : l10n.generatePdf, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

/// The shared text field used across all 19 forms.
Widget _field(
  String label,
  TextEditingController ctrl, {
  int maxLines = 1,
  VoidCallback? onChanged,
  String? suggestKey,
  String Function()? onSmartWrite,
}) {
  final hasSuggestions = suggestKey != null && SmartSuggestions.hasBank(suggestKey);
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: DS.textSecondary, fontSize: 12, fontWeight: FontWeight.w600))),
        if (onSmartWrite != null)
          GestureDetector(
            onTap: () {
              ctrl.text = onSmartWrite();
              onChanged?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: DS.indigo.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome_rounded, size: 12, color: DS.indigo),
                SizedBox(width: 4),
                Text('Auto-write', style: TextStyle(color: DS.indigo, fontSize: 10.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 5),
      hasSuggestions
          ? _SmartAutocompleteField(controller: ctrl, suggestKey: suggestKey!, maxLines: maxLines, onChanged: onChanged)
          : TextField(controller: ctrl, maxLines: maxLines, style: const TextStyle(color: Colors.white, fontSize: 14), onChanged: (_) => onChanged?.call(), decoration: InputDecoration(filled: true, fillColor: DS.bgCard, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)))),
    ]),
  );
}

/// Fuzzy-autocomplete text field.
class _SmartAutocompleteField extends StatelessWidget {
  final TextEditingController controller;
  final String suggestKey;
  final int maxLines;
  final VoidCallback? onChanged;
  const _SmartAutocompleteField({required this.controller, required this.suggestKey, required this.maxLines, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: FocusNode(),
      optionsBuilder: (v) => SmartSuggestions.suggest(suggestKey, v.text),
      onSelected: (s) {
        controller.text = s;
        onChanged?.call();
      },
      fieldViewBuilder: (context, textController, focusNode, onSubmit) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (_) => onChanged?.call(),
          decoration: InputDecoration(
            filled: true,
            fillColor: DS.bgCard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.separator, width: 0.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DS.indigo)),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            color: DS.bgCard,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, minWidth: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final opt = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(opt, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget _row(List<Widget> cols) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: cols.expand((w) => [w, if (w != cols.last) const SizedBox(width: 10)]).toList());

class _ItemRow extends StatelessWidget {
  final int index;
  final Map<String, TextEditingController> ctrls;
  final VoidCallback? onDelete;
  final VoidCallback onChanged;
  const _ItemRow({required this.index, required this.ctrls, this.onDelete, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: DS.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: DS.separator)),
      child: Column(children: [
        Row(children: [Text('#$index', style: DS.caption()), const Spacer(), if (onDelete != null) GestureDetector(onTap: onDelete, child: const Icon(Icons.close_rounded, color: DS.red, size: 18))]),
        const SizedBox(height: 8),
        _field(l10n.description, ctrls['desc']!, onChanged: onChanged),
        Row(children: [Expanded(child: _field(l10n.qty, ctrls['qty']!, onChanged: onChanged)), const SizedBox(width: 10), Expanded(child: _field(l10n.rate, ctrls['rate']!, onChanged: onChanged))]),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(title, style: const TextStyle(color: DS.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)));
}