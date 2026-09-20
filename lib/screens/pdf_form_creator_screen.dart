import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

import '../pdf_core/pdf_document_builder.dart';
import '../widgets/ds.dart';

// ─── Models ───────────────────────────────────────────────────────────────

enum FieldType { text, checkbox, radio, dropdown, signature }

class DraftField {
  String name;
  String partialName;
  FieldType type;
  String label;
  bool multiline;
  bool readOnly;
  List<String> options;
  String? selectedOption;
  double? nx, ny, nw, nh;
  int pageIndex;
  String? tooltip;
  DateTime createdAt;

  DraftField({
    required this.name,
    required this.type,
    required this.label,
    this.partialName = '',
    this.multiline = false,
    this.readOnly = false,
    this.options = const [],
    this.selectedOption,
    this.nx,
    this.ny,
    this.nw,
    this.nh,
    this.pageIndex = 0,
    this.tooltip,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String? validate() {
    if (name.isEmpty) return 'Field name is required';
    if (label.isEmpty) return 'Field label is required';
    if ((type == FieldType.radio || type == FieldType.dropdown) && options.isEmpty) {
      return 'At least one option is required';
    }
    return null;
  }

  List<double> toPdfRect(double pageWidth, double pageHeight) {
    if (nx == null || ny == null || nw == null || nh == null) {
      return [0, 0, 100, 100];
    }
    final double llx = nx! * pageWidth;
    final double ury = pageHeight - (ny! * pageHeight);
    final double urx = llx + nw! * pageWidth;
    final double lly = ury - nh! * pageHeight;
    return [llx, lly, urx, ury];
  }

  DraftField copyWith({
    String? name,
    String? label,
    bool? multiline,
    bool? readOnly,
    List<String>? options,
    String? selectedOption,
    String? tooltip,
  }) {
    return DraftField(
      name: name ?? this.name,
      type: type,
      label: label ?? this.label,
      partialName: partialName,
      multiline: multiline ?? this.multiline,
      readOnly: readOnly ?? this.readOnly,
      options: options ?? this.options,
      selectedOption: selectedOption ?? this.selectedOption,
      nx: nx,
      ny: ny,
      nw: nw,
      nh: nh,
      pageIndex: pageIndex,
      tooltip: tooltip ?? this.tooltip,
      createdAt: createdAt,
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────

class PdfFormCreatorScreen extends StatefulWidget {
  final String? existingFilePath;
  final Uint8List? existingFileBytes;

  const PdfFormCreatorScreen({
    super.key,
    this.existingFilePath,
    this.existingFileBytes,
  });

  @override
  State<PdfFormCreatorScreen> createState() => _PdfFormCreatorScreenState();
}

class _PdfFormCreatorScreenState extends State<PdfFormCreatorScreen> {
  bool? _useExisting;
  final _titleCtrl = TextEditingController(text: 'Fillable Form');

  // Existing PDF mode
  Uint8List? _srcBytes;
  String? _srcPath;
  int _pageCount = 0;
  int _currentPage = 0;
  bool _loadingPdf = false;
  bool _saving = false;
  final List<DraftField> _placedFields = [];
  FieldType? _activeTool;
  DraftField? _selectedField;
  pdfrx.PdfDocument? _pdfrxDoc;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initializeMode();
  }

  void _initializeMode() {
    if (widget.existingFilePath != null || widget.existingFileBytes != null) {
      _useExisting = true;
      _srcPath = widget.existingFilePath;
      _srcBytes = widget.existingFileBytes;
      _loadExistingPdf();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _pdfrxDoc?.dispose();
    super.dispose();
  }

  // ─── PDF Loading ────────────────────────────────────────────────────────

  Future<void> _loadExistingPdf() async {
    if (_srcBytes == null && _srcPath == null) return;

    setState(() {
      _loadingPdf = true;
      _loadError = null;
    });

    try {
      final bytes = _srcBytes ?? await File(_srcPath!).readAsBytes();
      _srcBytes = bytes;

      _pdfrxDoc = await pdfrx.PdfDocument.openData(bytes);
      _pageCount = _pdfrxDoc!.pages.length;
      _currentPage = 0;

      setState(() => _loadingPdf = false);
    } catch (e) {
      setState(() {
        _loadingPdf = false;
        _loadError = 'Failed to load PDF: ${e.toString()}';
      });

      if (mounted) {
        _showError(_loadError!);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      }
    }
  }

  // ─── Field Placement ──────────────────────────────────────────────────

  Future<void> _onPageTap(Offset localPos, Size renderSize) async {
    // ── Check if tap is inside an existing field ────────────────────
    final fieldsOnPage = _placedFields.where((f) => f.pageIndex == _currentPage);
    final double px = localPos.dx / renderSize.width;
    final double py = localPos.dy / renderSize.height;

    for (final f in fieldsOnPage) {
      final nx = f.nx!;
      final ny = f.ny!;
      final nw = f.nw!;
      final nh = f.nh!;
      if (px >= nx && px <= nx + nw && py >= ny && py <= ny + nh) {
        return;
      }
    }

    // ── No tool selected? Deselect ──────────────────────────────────
    if (_activeTool == null) {
      setState(() => _selectedField = null);
      return;
    }

    // ── Place new field ──────────────────────────────────────────────
    final FieldType activeTool = _activeTool!;

    final nx = (localPos.dx / renderSize.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / renderSize.height).clamp(0.0, 1.0);

    double nw, nh;
    switch (activeTool) {
      case FieldType.checkbox:
        nw = 0.025;
        nh = 0.025;
        break;
      case FieldType.radio:
        nw = 0.025;
        nh = 0.025;
        break;
      case FieldType.signature:
        nw = 0.40;
        nh = 0.10;
        break;
      default:
        nw = 0.35;
        nh = 0.035;
    }

    final String? name = await _showFieldNameDialog();
    if (name == null || name.isEmpty) return;

    List<String> options = [];
    if (activeTool == FieldType.dropdown) {
      final String? optionsInput = await _showOptionsDialog();
      if (optionsInput == null) return;
      options = optionsInput
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (options.isEmpty) {
        options = ['Option 1', 'Option 2'];
        _showError('No options entered – using default.');
      }
    }

    setState(() {
      _placedFields.add(DraftField(
        name: name,
        type: activeTool,
        label: name,
        pageIndex: _currentPage,
        nx: nx,
        ny: ny,
        nw: nw,
        nh: nh,
        options: options,
      ));
      _activeTool = null;
      _selectedField = null;
    });
  }

  Future<String?> _showFieldNameDialog() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: DS.bgCard,
        title: const Text('Field Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\s]')),
          ],
          decoration: InputDecoration(
            hintText: 'e.g., Full Name',
            hintStyle: TextStyle(color: DS.textSecondary.withOpacity(0.5)),
            filled: true,
            fillColor: DS.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: DS.indigo)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) {
                _showError('Field name cannot be empty');
                return;
              }
              Navigator.pop(context, name);
            },
            child: const Text('Add', style: TextStyle(color: DS.indigo)),
          ),
        ],
      ),
    );
  }

  Future<String?> _showOptionsDialog() {
    final ctrl = TextEditingController(text: 'Option 1, Option 2, Option 3');
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: DS.bgCard,
        title: const Text('Options (comma separated)', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Option 1, Option 2, Option 3',
            hintStyle: TextStyle(color: DS.textSecondary.withOpacity(0.5)),
            filled: true,
            fillColor: DS.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: DS.indigo)),
          ),
          TextButton(
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.pop(context, text.isEmpty ? null : text);
            },
            child: const Text('Add', style: TextStyle(color: DS.indigo)),
          ),
        ],
      ),
    );
  }

  void _removePlacedField(DraftField f) {
    setState(() => _placedFields.remove(f));
  }

  void _editField(DraftField field) {
    final nameCtrl = TextEditingController(text: field.label);
    showModalBottomSheet(
      context: context,
      backgroundColor: DS.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditFieldBottomSheet(
        field: field,
        nameCtrl: nameCtrl,
        onDelete: () {
          Navigator.pop(context);
          _removePlacedField(field);
          setState(() => _selectedField = null);
        },
        onSave: (updated) {
          setState(() {
            final idx = _placedFields.indexOf(field);
            if (idx != -1) {
              _placedFields[idx] = updated;
              _selectedField = updated;
            }
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  // ─── Save PDF ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_srcBytes == null) {
      _showError('No PDF loaded');
      return;
    }

    if (_placedFields.isEmpty) {
      _showError('Add at least one field before saving');
      return;
    }

    for (final field in _placedFields) {
      final error = field.validate();
      if (error != null) {
        _showError('Field "${field.label}": $error');
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final srcDoc = await pdfrx.PdfDocument.openData(_srcBytes!);
      final pageCount = srcDoc.pages.length;

      final builder = PdfDocumentBuilder(
        title: _titleCtrl.text.trim(),
        author: 'PDF Form Creator',
      );

      for (int i = 0; i < pageCount; i++) {
        await _renderAndAddPage(builder, srcDoc, i);
      }

      final outputBytes = builder.build();

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Fillable PDF',
        fileName: '${_titleCtrl.text.trim().replaceAll(RegExp(r'[^\w\s-]'), '')}_form.pdf',
        bytes: outputBytes,
      );

      if (outputPath == null) {
        setState(() => _saving = false);
        return;
      }

      if (mounted) {
        final snackBar = SnackBar(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('✅ Form saved successfully!', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                outputPath,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () {
              launchUrl(Uri.file(outputPath));
            },
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(snackBar);

        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to save form: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _renderAndAddPage(
    PdfDocumentBuilder builder,
    pdfrx.PdfDocument srcDoc,
    int pageIdx,
  ) async {
    final page = srcDoc.pages[pageIdx];
    final pageW = page.width.toDouble();
    final pageH = page.height.toDouble();

    try {
      final img = await page.render(
        fullWidth: pageW * 2.0,
        fullHeight: pageH * 2.0,
        backgroundColor: const Color(0xFFFFFFFF),
      );

      if (img == null) return;

      final newPage = builder.addPage(width: pageW, height: pageH);

      newPage.addImage(
        rgbaPixels: img.pixels,
        width: img.width,
        height: img.height,
        x: 0,
        y: 0,
        targetWidth: pageW,
        targetHeight: pageH,
        swapRedBlue: true,
      );

      final fieldsOnPage = _placedFields.where((f) => f.pageIndex == pageIdx);
      for (final field in fieldsOnPage) {
        _addFieldToPage(newPage, field, pageW, pageH);
      }
    } catch (e) {
      rethrow;
    }
  }

  void _addFieldToPage(PdfPageBuilder page, DraftField field, double pageW, double pageH) {
    final rect = field.toPdfRect(pageW, pageH);

    switch (field.type) {
      case FieldType.text:
        page.addTextField(
          name: field.name,
          rect: rect,
          multiline: field.multiline,
          readOnly: field.readOnly,
          tooltip: field.tooltip,
        );
        break;
      case FieldType.checkbox:
        page.addCheckbox(
          name: field.name,
          rect: rect,
          tooltip: field.tooltip,
        );
        break;
      case FieldType.radio:
        _addRadioGroup(page, field, pageW, pageH);
        break;
      case FieldType.dropdown:
        page.addDropdown(
          name: field.name,
          rect: rect,
          options: field.options,
          selectedValue: field.selectedOption,
          tooltip: field.tooltip,
        );
        break;
      case FieldType.signature:
        page.addSignatureField(
          name: field.name,
          rect: rect,
          tooltip: field.tooltip,
        );
        break;
    }
  }

  void _addRadioGroup(PdfPageBuilder page, DraftField field, double pageW, double pageH) {
    final options = field.options.asMap().entries.map((e) {
      final idx = e.key;
      final label = e.value;
      return {
        'exportValue': label,
        'rect': [
          field.nx! * pageW,
          pageH - ((field.ny! + idx * 0.04) * pageH),
          (field.nx! + field.nw!) * pageW,
          pageH - ((field.ny! + idx * 0.04 - field.nh!) * pageH),
        ],
      };
    }).toList();

    page.addRadioGroup(
      groupName: field.name,
      options: options,
      selectedValue: field.selectedOption,
      tooltip: field.tooltip,
    );
  }

  // ─── UI Helpers ──────────────────────────────────────────────────────────

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DS.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _getFieldTypeLabel(FieldType type) {
    switch (type) {
      case FieldType.text:
        return 'Text';
      case FieldType.checkbox:
        return 'Checkbox';
      case FieldType.radio:
        return 'Radio';
      case FieldType.dropdown:
        return 'Dropdown';
      case FieldType.signature:
        return 'Signature';
    }
  }

  IconData _getFieldTypeIcon(FieldType type) {
    switch (type) {
      case FieldType.text:
        return Icons.short_text_rounded;
      case FieldType.checkbox:
        return Icons.check_box_outlined;
      case FieldType.radio:
        return Icons.radio_button_checked_rounded;
      case FieldType.dropdown:
        return Icons.arrow_drop_down_circle_outlined;
      case FieldType.signature:
        return Icons.edit_rounded;
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_useExisting == null) {
      return _buildModeChoice();
    }

    if (!_useExisting!) {
      return Scaffold(
        backgroundColor: DS.bg,
        appBar: AppBar(
          backgroundColor: DS.bgCard,
          elevation: 0,
          title: const Text('Create Form — Blank'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: DS.indigo),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('Blank mode not implemented – use existing PDF', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        elevation: 0,
        title: const Text('Create Form'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: DS.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo),
                  )
                : const Text('Save', style: TextStyle(color: DS.indigo, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loadingPdf
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildErrorView()
              : _buildFormCreator(),
    );
  }

  Widget _buildModeChoice() {
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        elevation: 0,
        title: const Text('Create Form', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: DS.indigo),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modeCard(
                icon: Icons.note_add_rounded,
                title: 'Start Blank',
                subtitle: 'Build a new form from scratch',
                onTap: () => setState(() => _useExisting = false),
              ),
              const SizedBox(height: 16),
              _modeCard(
                icon: Icons.picture_as_pdf_rounded,
                title: 'Add Fields to a PDF',
                subtitle: 'Pick an existing PDF and place fields on it',
                onTap: () => _pickExistingPdf(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: DS.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DS.separator),
        ),
        child: Row(
          children: [
            Icon(icon, color: DS.indigo, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(color: DS.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExistingPdf() async {
    Navigator.pop(context, {'requestPickExisting': true});
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: DS.red),
            const SizedBox(height: 16),
            const Text(
              'Could not load PDF',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? 'Unknown error',
              style: const TextStyle(color: DS.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Form Creator ──────────────────────────────────────────────────────

  Widget _buildFormCreator() {
    return Column(
      children: [
        if (_pageCount > 1) _buildPageIndicator() else const SizedBox.shrink(),
        Expanded(child: _buildPagePreview()),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildPageIndicator() {
    return Container(
      color: DS.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Page ${_currentPage + 1} of $_pageCount',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              if (_currentPage > 0)
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: DS.indigo),
                  onPressed: () => setState(() => _currentPage--),
                ),
              if (_currentPage < _pageCount - 1)
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: DS.indigo),
                  onPressed: () => setState(() => _currentPage++),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Page preview with field overlays ──────────────────────────────────

  Widget _buildPagePreview() {
    if (_pdfrxDoc == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final renderSize =
            Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTapDown: (details) async {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;

            final local = box.globalToLocal(details.globalPosition);

            await _onPageTap(local, renderSize);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              pdfrx.PdfPageView(
                document: _pdfrxDoc!,
                pageNumber: _currentPage + 1,
                alignment: Alignment.center,
              ),
              ..._placedFields
                  .where((f) => f.pageIndex == _currentPage)
                  .map((f) => _fieldOverlay(f, renderSize)),
            ],
          ),
        );
      },
    );
  }

  // ─── Field overlay with professional resize handle ────────────────────

Widget _fieldOverlay(DraftField f, Size renderSize) {
  final bool selected = _selectedField == f;
  final double left = f.nx! * renderSize.width;
  final double top = f.ny! * renderSize.height;
  final double width = f.nw! * renderSize.width;
  final double height = f.nh! * renderSize.height;
  const double minPx = 20;
  const double handleSize = 20;
  const double touchPadding = 12;

  final double totalHandleSize = handleSize + touchPadding * 2;
  final double extra = totalHandleSize / 2;

  return Positioned(
    left: left - extra,
    top: top - extra,
    width: width + extra * 2,
    height: height + extra * 2,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        // ─── Field body ──────────────────────────────────────────────
        Positioned(
          left: extra,
          top: extra,
          width: width,
          height: height,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedField = f;
                _activeTool = null;
              });
            },
            // ✅ Long‑press to open edit sheet (where delete lives)
            onLongPress: () => _editField(f),
            onPanStart: (_) {
              setState(() => _selectedField = f);
            },
            onPanUpdate: (d) {
              if (_activeTool != null) return;
              setState(() {
                f.nx = ((f.nx! + d.delta.dx / renderSize.width)
                    .clamp(0.0, 1.0 - f.nw!));
                f.ny = ((f.ny! + d.delta.dy / renderSize.height)
                    .clamp(0.0, 1.0 - f.nh!));
              });
            },
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: _fieldColor(f.type).withOpacity(0.15),
                border: Border.all(
                  color: selected ? DS.indigo : _fieldColor(f.type),
                  width: selected ? 2.0 : 1.5,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getFieldTypeIcon(f.type), size: 12,
                        color: _fieldColor(f.type)),
                    const SizedBox(width: 3),
                    Text(
                      f.label,
                      style: TextStyle(
                        color: _fieldColor(f.type),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ─── Resize handle ──────────────────────────────────────────
        if (selected)
          Positioned(
            left: extra + width - totalHandleSize / 2,
            top: extra + height - totalHandleSize / 2,
            child: Listener(
              onPointerMove: (event) {
                final dx = event.delta.dx / renderSize.width;
                final dy = event.delta.dy / renderSize.height;
                setState(() {
                  final newW = (f.nw! + dx)
                      .clamp(minPx / renderSize.width, 1.0 - f.nx!);
                  final newH = (f.nh! + dy)
                      .clamp(minPx / renderSize.height, 1.0 - f.ny!);
                  f.nw = newW;
                  f.nh = newH;
                });
              },
              child: Container(
                width: totalHandleSize,
                height: totalHandleSize,
                decoration: BoxDecoration(
                  color: DS.indigo,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.open_in_full_rounded,
                  size: handleSize * 0.6,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

  Color _fieldColor(FieldType type) {
    switch (type) {
      case FieldType.text:
        return DS.indigo;
      case FieldType.checkbox:
        return Colors.green;
      case FieldType.radio:
        return Colors.orange;
      case FieldType.dropdown:
        return Colors.purple;
      case FieldType.signature:
        return Colors.blue;
    }
  }

  // ─── Bottom bar (radio removed) ──────────────────────────────────────

  Widget _buildBottomBar() {
    final visibleFieldTypes = FieldType.values.where((t) => t != FieldType.radio).toList();

    return Container(
      color: DS.bgCard,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ...visibleFieldTypes.map((type) {
                final active = _activeTool == type;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          setState(() => _activeTool = active ? null : type),
                      icon: Icon(_getFieldTypeIcon(type), size: 16),
                      label: Text(_getFieldTypeLabel(type),
                          style: const TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: active ? DS.indigo : DS.bg,
                        foregroundColor: active ? Colors.white : DS.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_alt_rounded),
              label: Text(_saving ? 'Saving...' : 'Save Form'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DS.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Edit Field Bottom Sheet ───────────────────────────────────────────────

class _EditFieldBottomSheet extends StatefulWidget {
  final DraftField field;
  final TextEditingController nameCtrl;
  final VoidCallback onDelete;
  final Function(DraftField) onSave;

  const _EditFieldBottomSheet({
    required this.field,
    required this.nameCtrl,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<_EditFieldBottomSheet> createState() => _EditFieldBottomSheetState();
}

class _EditFieldBottomSheetState extends State<_EditFieldBottomSheet> {
  late bool _multiline;
  late bool _readOnly;
  late String _selectedOption;

  @override
  void initState() {
    super.initState();
    _multiline = widget.field.multiline;
    _readOnly = widget.field.readOnly;
    _selectedOption = widget.field.selectedOption ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit "${widget.field.label}"',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: widget.nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Label',
              labelStyle: const TextStyle(color: DS.textSecondary),
              filled: true,
              fillColor: DS.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (widget.field.type == FieldType.text) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              value: _multiline,
              onChanged: (v) => setState(() => _multiline = v),
              title: const Text('Multi-line', style: TextStyle(color: Colors.white)),
              activeColor: DS.indigo,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _readOnly,
              onChanged: (v) => setState(() => _readOnly = v),
              title: const Text('Read-only', style: TextStyle(color: Colors.white)),
              activeColor: DS.indigo,
              contentPadding: EdgeInsets.zero,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, color: DS.red),
                  label: const Text('Delete', style: TextStyle(color: DS.red)),
                  onPressed: widget.onDelete,
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: DS.red)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                  onPressed: () {
                    final updated = widget.field.copyWith(
                      label: widget.nameCtrl.text.trim(),
                      multiline: _multiline,
                      readOnly: _readOnly,
                    );
                    widget.onSave(updated);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: DS.indigo),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
