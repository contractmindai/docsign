import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:signature/signature.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

import '../forms/pdf_form_service.dart';
import '../forms/acroform.dart';
import '../pdf_core/document.dart';
import '../pdf_core/object_parser.dart';
import '../pdf_core/pdf_document_builder.dart';
import '../widgets/ds.dart';

// ─── Top‑level isolate worker ──────────────────────────────────────────────

Future<Map<String, dynamic>> _parseFieldsWorker(Uint8List bytes) async {
  final engine = PdfDocumentEngine(bytes);
  final result = PdfFormDocument.open(bytes);
  if (!result.isSupported) {
    return {
      'placements': [],
      'pageCount': 0,
      'pageSizes': [],
      'error': result.unsupportedReason ?? 'No fillable fields',
    };
  }
  final doc = result.document!;

  final Map<int, int> pageIdToIndex = {};
  final pages = engine.walkPageTree();
  for (int i = 0; i < pages.length; i++) {
    for (final entry in engine.resolvedObjectsCache.entries) {
      if (entry.value == pages[i]) {
        pageIdToIndex[entry.key] = i;
        break;
      }
    }
  }

  final List<Map<String, dynamic>> placements = [];
  for (final f in doc.fields) {
    _extractWidgetsForIsolate(f, pageIdToIndex, engine, placements);
  }

  final List<Map<String, double>> pageSizes = [];
  for (final page in pages) {
    final mb = page['/MediaBox'];
    if (mb is List && mb.length == 4) {
      final w = (mb[2] as num).toDouble() - (mb[0] as num).toDouble();
      final h = (mb[3] as num).toDouble() - (mb[1] as num).toDouble();
      pageSizes.add({'width': w, 'height': h});
    } else {
      pageSizes.add({'width': 612.0, 'height': 792.0});
    }
  }

  return {
    'placements': placements,
    'pageCount': pages.length,
    'pageSizes': pageSizes,
    'error': null,
  };
}

void _extractWidgetsForIsolate(
  AcroFormField field,
  Map<int, int> pageIdToIndex,
  PdfDocumentEngine engine,
  List<Map<String, dynamic>> placements,
) {
  final dict = field.rawDict;

  List<String> radioOpts = [];
  if (field.type == AcroFieldType.radio) {
    final kids = dict['/Kids'];
    if (kids is List) {
      for (final kidRef in kids) {
        if (kidRef is PdfIndirectReference) {
          final kidDict = engine.resolveIndirectReference(kidRef) as Map<String, dynamic>?;
          if (kidDict != null) {
            String? exportVal;
            final as_ = kidDict['/AS']?.toString();
            if (as_ != null && as_ != '/Off') {
              exportVal = as_;
            } else {
              final ap = kidDict['/AP'];
              if (ap is Map<String, dynamic>) {
                final n = ap['/N'];
                if (n is Map<String, dynamic>) {
                  final keys = n.keys.where((k) => k != '/Off');
                  if (keys.isNotEmpty) exportVal = keys.first;
                }
              }
            }
            if (exportVal != null) radioOpts.add(exportVal);
          }
        }
      }
    }
  }

  if (dict.containsKey('/Rect')) {
    final pRef = dict['/P'];
    int pageIdx = 0;
    if (pRef is PdfIndirectReference) {
      pageIdx = pageIdToIndex[pRef.objectId] ?? 0;
    }
    final rectObj = dict['/Rect'];
    if (rectObj is List && rectObj.length == 4) {
      final rect = rectObj.map((e) => (e as num).toDouble()).toList();
      placements.add({
        'name': field.fullyQualifiedName,
        'pageIndex': pageIdx,
        'rect': rect,
        'typeIndex': field.type.index,
        'currentValue': field.currentValue?.toString(),
        'partialName': field.partialName,
        'radioOptions': radioOpts,
        'choiceOptions': field.type == AcroFieldType.choice ? field.choiceOptions : [],
        'flags': (field.rawDict['/Ff'] as num?)?.toInt() ?? 0,
      });
    }
  }

  final kids = dict['/Kids'];
  if (kids is List) {
    for (final kidRef in kids) {
      if (kidRef is PdfIndirectReference) {
        final kidDict = engine.resolveIndirectReference(kidRef) as Map<String, dynamic>?;
        if (kidDict != null) {
          final kidField = AcroFormField(
            partialName: field.partialName,
            fullyQualifiedName: field.fullyQualifiedName,
            fieldType: field.fieldType,
            type: field.type,
            objectId: kidRef.objectId,
            currentValue: kidDict['/V'] ?? field.currentValue,
            rawDict: kidDict,
            radioKids: [],
          );
          _extractWidgetsForIsolate(kidField, pageIdToIndex, engine, placements);
        }
      }
    }
  }
}

class _UiField {
  final String name;
  final AcroFieldType type;
  final int pageIndex;
  final List<double> rect;
  final String label;
  final String? currentValue;
  final List<String> radioOptions;
  final List<String> choiceOptions;
  final int flags;

  _UiField({
    required this.name,
    required this.type,
    required this.pageIndex,
    required this.rect,
    required this.label,
    this.currentValue,
    this.radioOptions = const [],
    this.choiceOptions = const [],
    this.flags = 0,
  });
}

// ─── Main Screen ────────────────────────────────────────────────────────────

class PdfFormFillerScreen extends StatefulWidget {
  final String filePath;
  final Uint8List? fileBytes;

  const PdfFormFillerScreen({
    super.key,
    required this.filePath,
    this.fileBytes,
  });

  @override
  State<PdfFormFillerScreen> createState() => _PdfFormFillerScreenState();
}

class _PdfFormFillerScreenState extends State<PdfFormFillerScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Uint8List? _pdfBytes;
  List<_UiField> _uiFields = [];
  int _pageCount = 0;
  int _currentPage = 0;

  pdfrx.PdfDocument? _pdfrxDoc;
  List<double> _pageWidths = [];
  List<double> _pageHeights = [];

  final Map<String, TextEditingController> _textCtrls = {};
  final Map<String, bool> _checkboxState = {};
  final Map<String, String?> _radioState = {};
  final Map<String, String?> _choiceState = {};
  final Map<String, Uint8List?> _sigState = {};
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _textCtrls.values) c.dispose();
    for (final f in _focusNodes.values) f.dispose();
    _pdfrxDoc?.dispose();
    super.dispose();
  }

  // ─── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      setState(() => _loading = true);

      final bytes = widget.fileBytes ?? await File(widget.filePath).readAsBytes();
      _pdfBytes = bytes;

      _pdfrxDoc = await pdfrx.PdfDocument.openData(bytes);
      _pageCount = _pdfrxDoc!.pages.length;
      _pageWidths = [];
      _pageHeights = [];
      for (int i = 0; i < _pageCount; i++) {
        final page = _pdfrxDoc!.pages[i];
        _pageWidths.add(page.width.toDouble());
        _pageHeights.add(page.height.toDouble());
      }

      Map<String, dynamic> result;
      try {
        result = await compute(_parseFieldsWorker, bytes);
      } catch (e) {
        result = {
          'placements': [],
          'pageCount': 0,
          'pageSizes': [],
          'error': e.toString(),
        };
      }

      final errorMsg = result['error'] as String?;
      if (errorMsg != null) {
        setState(() {
          _error = errorMsg;
          _loading = false;
        });
        return;
      }

      final placements = result['placements'] as List;
      _uiFields = placements.map((p) {
        final type = AcroFieldType.values[p['typeIndex'] as int];
        return _UiField(
          name: p['name'],
          type: type,
          pageIndex: p['pageIndex'],
          rect: List<double>.from(p['rect']),
          label: p['partialName'] ?? p['name'],
          currentValue: p['currentValue'],
          radioOptions: List<String>.from(p['radioOptions'] ?? []),
          choiceOptions: List<String>.from(p['choiceOptions'] ?? []),
          flags: p['flags'],
        );
      }).toList();

      for (final f in _uiFields) {
        final key = f.name;
        final raw = f.currentValue ?? '';
        switch (f.type) {
          case AcroFieldType.text:
            _textCtrls[key] = TextEditingController(text: raw);
            _focusNodes[key] = FocusNode();
            break;
          case AcroFieldType.checkbox:
            _checkboxState[key] = raw != '/Off' && raw.isNotEmpty;
            break;
          case AcroFieldType.radio:
            _radioState[key] = (raw == '/Off' || raw.isEmpty) ? null : raw;
            break;
          case AcroFieldType.choice:
            _choiceState[key] = raw.isEmpty ? null : raw;
            break;
          case AcroFieldType.signature:
            _sigState[key] = null;
            break;
          default:
            break;
        }
      }

      setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('Load error: $e\n$st');
      setState(() {
        _error = 'Could not open form: $e';
        _loading = false;
      });
    }
  }

  // ─── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_pdfBytes == null || _saving) return;
    setState(() => _saving = true);

    try {
      // 1. Fill the form fields
      final result = PdfFormDocument.open(_pdfBytes!);
      if (!result.isSupported) {
        throw Exception(result.unsupportedReason ?? 'Cannot open for saving');
      }
      final doc = result.document!;

      final Map<String, Uint8List> sigImages = {};

      for (final f in doc.fields) {
        final key = f.fullyQualifiedName;
        switch (f.type) {
          case AcroFieldType.text:
            final text = _textCtrls[key]?.text ?? '';
            if (text.isNotEmpty) doc.setTextValue(f, text);
            break;
          case AcroFieldType.checkbox:
            doc.setCheckboxValue(f, _checkboxState[key] ?? false);
            break;
          case AcroFieldType.radio:
            break;
          case AcroFieldType.choice:
            final val = _choiceState[key];
            if (val != null) doc.setChoiceValue(f, val);
            break;
          case AcroFieldType.signature:
            final sigBytes = _sigState[key];
            if (sigBytes != null) {
              sigImages[key] = sigBytes;
              doc.setSignatureValue(f, 'Signed', mode: 'text');
            }
            break;
          default:
            break;
        }
      }

      Uint8List outBytes = doc.save();

      // 2. Overlay signature images using rasterisation (reliable)
      if (sigImages.isNotEmpty) {
        outBytes = await _rebuildWithSignatureOverlay(outBytes, sigImages);
      }

      // 3. Show Save As dialog using file_picker
      final base = widget.filePath.split(RegExp(r'[/\\]')).last.replaceAll('.pdf', '');
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Filled PDF',
        fileName: '${base}_filled.pdf',
        bytes: outBytes,
      );

      if (outputPath == null) {
        // User cancelled
        setState(() => _saving = false);
        return;
      }

      if (!mounted) return;

      // 4. Show snackbar with the chosen path
      final snackBar = SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('✅ Saved successfully!', style: TextStyle(fontWeight: FontWeight.bold)),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: DS.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Rasterisation‑based signature overlay (reliable) ──────────────────

  Future<Uint8List> _rebuildWithSignatureOverlay(
    Uint8List pdfBytes,
    Map<String, Uint8List> sigImages,
  ) async {
    final srcDoc = await pdfrx.PdfDocument.openData(pdfBytes);
    final pageCount = srcDoc.pages.length;

    final builder = PdfDocumentBuilder(
      title: 'Signed Document',
      author: 'PDF Form Filler',
    );

    final fieldMap = {for (final f in _uiFields) f.name: f};

    for (int i = 0; i < pageCount; i++) {
      final page = srcDoc.pages[i];
      final pageW = page.width.toDouble();
      final pageH = page.height.toDouble();

      final imgData = await page.render(
        fullWidth: pageW * 2.0,
        fullHeight: pageH * 2.0,
        backgroundColor: const Color(0xFFFFFFFF),
      );
      if (imgData == null) continue;

      final newPage = builder.addPage(width: pageW, height: pageH);

      newPage.addImage(
        rgbaPixels: imgData.pixels,
        width: imgData.width,
        height: imgData.height,
        x: 0,
        y: 0,
        targetWidth: pageW,
        targetHeight: pageH,
        swapRedBlue: true,
      );

      final sigsOnPage = sigImages.entries.where((entry) {
        final uiField = fieldMap[entry.key];
        return uiField != null && uiField.pageIndex == i;
      });

      for (final entry in sigsOnPage) {
        final uiField = fieldMap[entry.key]!;
        final rect = uiField.rect;
        final sigPng = entry.value;

        final sigImage = img.decodePng(sigPng);
        if (sigImage == null) continue;

        final sigWidth = rect[2] - rect[0];
        final sigHeight = rect[3] - rect[1];

        final rgbaBytes = Uint8List(sigImage.width * sigImage.height * 4);
        int idx = 0;
        for (int y = 0; y < sigImage.height; y++) {
          for (int x = 0; x < sigImage.width; x++) {
            final pixel = sigImage.getPixel(x, y);
            rgbaBytes[idx++] = pixel.r.toInt();
            rgbaBytes[idx++] = pixel.g.toInt();
            rgbaBytes[idx++] = pixel.b.toInt();
            rgbaBytes[idx++] = pixel.a.toInt();
          }
        }

        newPage.addImage(
          rgbaPixels: rgbaBytes,
          width: sigImage.width,
          height: sigImage.height,
          x: rect[0],
          y: rect[1],
          targetWidth: sigWidth,
          targetHeight: sigHeight,
          swapRedBlue: false,
        );
      }
    }

    await srcDoc.dispose();
    return builder.build();
  }

  // ─── Signature capture ────────────────────────────────────────────────────

  Future<void> _captureSignature(String key) async {
    final bytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DS.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _SignatureSheet(),
    );
    if (bytes != null && mounted) {
      setState(() => _sigState[key] = bytes);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        backgroundColor: DS.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: DS.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_pageCount > 1
            ? 'Fill Form (Page ${_currentPage + 1}/$_pageCount)'
            : 'Fill Form',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        actions: [
          if (!_loading && _error == null && _uiFields.isNotEmpty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: DS.indigo))
                  : const Text('Save',
                      style: TextStyle(color: DS.indigo, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _uiFields.isEmpty) {
      return _errorView(_error ?? 'No fillable fields found.');
    }

    return Column(
      children: [
        if (_pageCount > 1) _buildPageNav(),
        Expanded(child: _buildPageWithOverlays()),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildPageNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: DS.bgCard,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: DS.indigo, size: 16),
            onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Page ${_currentPage + 1} of $_pageCount',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, color: DS.indigo, size: 16),
            onPressed: _currentPage < _pageCount - 1 ? () => setState(() => _currentPage++) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildPageWithOverlays() {
    if (_pdfrxDoc == null) return const Center(child: CircularProgressIndicator());

    final pageW = _pageWidths[_currentPage];
    final pageH = _pageHeights[_currentPage];
    final fields = _uiFields.where((f) => f.pageIndex == _currentPage).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = (viewW / pageW) * pageH;

        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: viewW,
              height: viewH,
              child: Stack(
                children: [
                  pdfrx.PdfPageView(
                    document: _pdfrxDoc!,
                    pageNumber: _currentPage + 1,
                    alignment: Alignment.center,
                  ),
                  for (final f in fields)
                    _buildFieldOverlay(f, viewW, viewH),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFieldOverlay(_UiField uiField, double renderW, double renderH) {
    final rect = uiField.rect;
    if (rect.length < 4) return const SizedBox.shrink();

    final double llx = rect[0];
    final double lly = rect[1];
    final double urx = rect[2];
    final double ury = rect[3];

    final double pageW = _pageWidths[uiField.pageIndex];
    final double pageH = _pageHeights[uiField.pageIndex];

    final double normX = llx / pageW;
    final double normY = lly / pageH;
    final double normW = (urx - llx) / pageW;
    final double normH = (ury - lly) / pageH;

    final double left = normX * renderW;
    final double top = (1 - (normY + normH)) * renderH;
    final double width = normW * renderW;
    final double height = normH * renderH;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: _buildFieldWidget(uiField),
    );
  }

  Widget _buildFieldWidget(_UiField field) {
    final key = field.name;
    final isReadOnly = (field.flags & 1) != 0;
    final isPassword = (field.flags & (1 << 13)) != 0;
    final isMultiline = (field.flags & (1 << 12)) != 0;

    switch (field.type) {
      case AcroFieldType.text:
        final ctrl = _textCtrls[key]!;
        final focus = _focusNodes[key]!;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDE7).withOpacity(0.92),
            border: Border.all(
              color: isReadOnly ? Colors.grey : DS.indigo.withOpacity(0.6),
              width: isReadOnly ? 0.5 : 1,
            ),
          ),
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            readOnly: isReadOnly,
            obscureText: isPassword,
            maxLines: isMultiline ? null : 1,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            ),
            style: const TextStyle(fontSize: 10, color: Colors.black87),
          ),
        );

      case AcroFieldType.checkbox:
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 1.5,
                child: Checkbox(
                  value: _checkboxState[key] ?? false,
                  onChanged: isReadOnly ? null : (v) => setState(() => _checkboxState[key] = v ?? false),
                  activeColor: DS.indigo,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (field.label.isNotEmpty)
                Flexible(
                  child: Text(
                    field.label,
                    style: const TextStyle(fontSize: 10, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );

      case AcroFieldType.radio:
        return const SizedBox.shrink();

      case AcroFieldType.choice:
        final options = field.choiceOptions;
        if (options.isEmpty) return const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDE7).withOpacity(0.92),
            border: Border.all(color: isReadOnly ? Colors.grey : DS.indigo.withOpacity(0.6), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _choiceState[key],
              hint: const Text('…', style: TextStyle(fontSize: 10)),
              items: options.map((o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: const TextStyle(fontSize: 10)),
              )).toList(),
              onChanged: isReadOnly ? null : (v) => setState(() => _choiceState[key] = v),
              isExpanded: true,
              style: const TextStyle(fontSize: 10, color: Colors.black87),
            ),
          ),
        );

      case AcroFieldType.signature:
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: GestureDetector(
            onTap: isReadOnly ? null : () => _captureSignature(key),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: _sigState[key] != null ? Colors.green : Colors.blue,
                  width: _sigState[key] != null ? 2.0 : 1.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _sigState[key] != null ? 'Signed' : 'Tap to sign',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: _sigState[key] != null ? Colors.black : Colors.grey[600],
                    ),
                  ),
                  if (_sigState[key] != null)
                    const Icon(Icons.check_circle, color: Colors.green, size: 14),
                ],
              ),
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ─── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final total = _uiFields.length;
    final filled = _uiFields.where((f) {
      final key = f.name;
      switch (f.type) {
        case AcroFieldType.text:
          return (_textCtrls[key]?.text ?? '').isNotEmpty;
        case AcroFieldType.checkbox:
          return _checkboxState[key] ?? false;
        case AcroFieldType.radio:
          return false;
        case AcroFieldType.choice:
          return (_choiceState[key] ?? '').isNotEmpty;
        case AcroFieldType.signature:
          return _sigState[key] != null;
        default:
          return false;
      }
    }).length;
    final allFilled = total > 0 && filled == total;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: DS.bgCard,
        border: Border(top: BorderSide(color: DS.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('$filled / $total fields filled',
                    style: const TextStyle(color: DS.textSecondary, fontSize: 12)),
                const Spacer(),
                Text('${total > 0 ? (filled * 100 ~/ total) : 0}%',
                    style: TextStyle(
                        color: allFilled ? const Color(0xFF4ADE80) : DS.indigo,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total > 0 ? filled / total : 0,
                backgroundColor: DS.separator,
                valueColor: AlwaysStoppedAnimation<Color>(
                    allFilled ? const Color(0xFF16A34A) : DS.indigo),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(allFilled ? Icons.check_circle_rounded : Icons.save_alt_rounded,
                        size: 19),
                label: Text(
                  _saving ? 'Saving…' : allFilled ? 'Submit Form' : 'Save Filled PDF',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: allFilled ? const Color(0xFF16A34A) : DS.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded, size: 64, color: DS.red),
            const SizedBox(height: 20),
            const Text('Cannot fill this PDF',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(color: DS.textSecondary, fontSize: 14, height: 1.6)),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              icon: const Icon(Icons.arrow_back_rounded, color: DS.indigo),
              label: const Text('Go back', style: TextStyle(color: DS.indigo, fontWeight: FontWeight.w600)),
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: DS.indigo),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Signature Sheet ───────────────────────────────────────────────────────────

class _SignatureSheet extends StatefulWidget {
  const _SignatureSheet();

  @override
  State<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<_SignatureSheet> {
  final SignatureController _controller = SignatureController(
    penStrokeWidth: 2.5,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  bool _hasDrawing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_controller.isNotEmpty) {
      final pngBytes = await _controller.toPngBytes();
      if (pngBytes != null && mounted) {
        Navigator.pop(context, pngBytes);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw your signature')),
      );
    }
  }

  void _clear() {
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: DS.separator,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Draw Your Signature',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DS.separator),
            ),
            height: 200,
            width: double.infinity,
            child: Signature(
              controller: _controller,
              height: 200,
              width: double.infinity,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.refresh_rounded, color: DS.textSecondary),
                label: const Text('Clear', style: TextStyle(color: DS.textSecondary)),
              ),
              ElevatedButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Confirm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DS.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
