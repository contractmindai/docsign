import 'dart:typed_data';
import 'package:archive/archive.dart' show ZLibEncoder;

/// Builds a new PDF document with form fields from scratch.
class PdfDocumentBuilder {
  final double defaultPageWidth;
  final double defaultPageHeight;
  final String title;
  final String author;

  int _nextId = 1;
  final Map<int, List<int>> _objects = {};
  final List<_PageBuilder> _pages = [];

  late final int _catalogId;
  late final int _pagesId;
  late final int _acroFormId;
  late final int _fontId;

  PdfDocumentBuilder({
    this.defaultPageWidth = 595.28,
    this.defaultPageHeight = 841.89,
    this.title = '',
    this.author = '',
  }) {
    _catalogId = _nextId++;
    _pagesId = _nextId++;
    _acroFormId = _nextId++;
    _fontId = _nextId++;
  }

  PdfPageBuilder addPage({double? width, double? height}) {
    final page = _PageBuilder(
      pageWidth: width ?? defaultPageWidth,
      pageHeight: height ?? defaultPageHeight,
      builder: this,
    );
    _pages.add(page);
    return page;
  }

  Uint8List build() {
    if (_pages.isEmpty) addPage();

    // Font object
    _storeObject(_fontId, _bytes('''<<
  /Type /Font
  /Subtype /Type1
  /BaseFont /Helvetica
  /Encoding /WinAnsiEncoding
>>'''));

    final List<int> pageIds = [];
    final List<int> fieldIds = [];

    for (final page in _pages) {
      final ids = page._build(this);
      pageIds.add(ids.pageId);
      fieldIds.addAll(ids.fieldIds);
    }

    // Pages dict
    final String kidsArr = pageIds.map((id) => '$id 0 R').join(' ');
    _storeObject(_pagesId, _bytes('''<<
  /Type /Pages
  /Kids [$kidsArr]
  /Count ${pageIds.length}
>>'''));

    // AcroForm
    final String fieldsArr = fieldIds.map((id) => '$id 0 R').join(' ');
    _storeObject(_acroFormId, _bytes('''<<
  /Fields [$fieldsArr]
  /DA (/Helv 10 Tf 0 g)
  /DR << /Font << /Helv $_fontId 0 R >> >>
  /NeedAppearances true
>>'''));

    // Info
    String infoRef = '';
    if (title.isNotEmpty || author.isNotEmpty) {
      final infoId = _nextId++;
      final parts = <String>[];
      if (title.isNotEmpty) parts.add('/Title (${_esc(title)})');
      if (author.isNotEmpty) parts.add('/Author (${_esc(author)})');
      parts.add('/Producer (PDF Engine - Pure Dart)');
      _storeObject(infoId, _bytes('<< ${parts.join(' ')} >>'));
      infoRef = ' /Info $infoId 0 R';
    }

    // Catalog
    _storeObject(_catalogId, _bytes('''<<
  /Type /Catalog
  /Pages $_pagesId 0 R
  /AcroForm $_acroFormId 0 R
>>'''));

    // Serialize
    final out = BytesBuilder(copy: false);
    final List<int> header = [
      ..._a('%PDF-1.7\n'),
      37, 226, 227, 207, 211, 10, // %âãÏÓ\n
    ];
    out.add(header);

    final allIds = _objects.keys.toList()..sort();
    final offsets = <int, int>{};

    for (final id in allIds) {
      offsets[id] = out.length;
      out.add(_a('$id 0 obj\n'));
      out.add(_objects[id]!);
      out.add(_a('\nendobj\n\n'));
    }

    final int xrefOffset = out.length;
    out.add(_a('xref\n'));

    final List<List<int>> runs = _groupRuns(allIds);
    out.add(_a('0 1\n'));
    // ── 20-byte free entry: 10-digit offset, space, 5-digit generation,
    //    space, 'f', \r\n. No space between the 'f' and \r\n.
    out.add(_a('0000000000 65535 f\r\n'));

    for (final run in runs) {
      out.add(_a('${run.first} ${run.length}\n'));
      for (final id in run) {
        final String off = offsets[id]!.toString().padLeft(10, '0');
        // ── 20-byte normal entry. No space between the 'n' and \r\n.
        out.add(_a('$off 00000 n\r\n'));
      }
    }

    final int maxId = allIds.reduce((a, b) => a > b ? a : b);
    out.add(_a('trailer\n<< /Size ${maxId + 1} /Root $_catalogId 0 R$infoRef >>\n'));
    out.add(_a('startxref\n$xrefOffset\n%%EOF\n'));

    return out.toBytes();
  }

  int _allocId() => _nextId++;
  void _storeObject(int id, List<int> body) => _objects[id] = body;

  static List<List<int>> _groupRuns(List<int> sortedIds) {
    if (sortedIds.isEmpty) return [];
    final runs = <List<int>>[];
    var current = [sortedIds[0]];
    for (int i = 1; i < sortedIds.length; i++) {
      if (sortedIds[i] == sortedIds[i - 1] + 1) {
        current.add(sortedIds[i]);
      } else {
        runs.add(current);
        current = [sortedIds[i]];
      }
    }
    runs.add(current);
    return runs;
  }

  static List<int> _a(String s) => s.codeUnits;

  static List<int> _bytes(String s) {
    final out = <int>[];
    for (final c in s.runes) {
      if (c < 0x80) {
        out.add(c);
      } else if (c < 0x800) {
        out.add(0xC0 | (c >> 6));
        out.add(0x80 | (c & 0x3F));
      } else {
        out.add(0xE0 | (c >> 12));
        out.add(0x80 | ((c >> 6) & 0x3F));
        out.add(0x80 | (c & 0x3F));
      }
    }
    return out;
  }

  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');

  static String _f(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(3);
}

// ─── Page builder ────────────────────────────────────────────────────────────

class PdfPageBuilder {
  final double pageWidth;
  final double pageHeight;
  final PdfDocumentBuilder _doc;

  final List<String> _ops = [];
  final List<_FieldSpec> _fieldSpecs = [];
  final List<int> _imageIds = []; // track image XObject IDs

  PdfPageBuilder({
    required this.pageWidth,
    required this.pageHeight,
    required PdfDocumentBuilder builder,
  }) : _doc = builder;

  // ─── Static content ────────────────────────────────────────────────────────

  void addLabel({
    required String text,
    required double x,
    required double y,
    double fontSize = 10.0,
    bool bold = false,
  }) {
    final font = bold ? '/HelvB' : '/Helv';
    final esc = PdfDocumentBuilder._esc(text);
    _ops.add('BT $font ${_f(fontSize)} Tf 0 g ${_f(x)} ${_f(y)} Td ($esc) Tj ET');
  }

  void addLine({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    double lineWidth = 0.5,
    List<double> color = const [0, 0, 0],
  }) {
    final c = color.map(_f).join(' ');
    _ops.add('${_f(lineWidth)} w $c RG ${_f(x1)} ${_f(y1)} m ${_f(x2)} ${_f(y2)} l S');
  }

  void addRect({
    required double x,
    required double y,
    required double width,
    required double height,
    List<double> fillColor = const [0.9, 0.9, 0.9],
    List<double>? strokeColor,
    double lineWidth = 0.5,
  }) {
    final fill = fillColor.map(_f).join(' ');
    final stroke = strokeColor?.map(_f).join(' ') ?? '0 0 0';
    if (strokeColor != null) {
      _ops.add(
          '$fill rg $stroke RG ${_f(lineWidth)} w ${_f(x)} ${_f(y)} ${_f(width)} ${_f(height)} re B');
    } else {
      _ops.add('$fill rg ${_f(x)} ${_f(y)} ${_f(width)} ${_f(height)} re f');
    }
  }

  // ─── Form fields ───────────────────────────────────────────────────────────

  void addTextField({
    required String name,
    required List<double> rect,
    String defaultValue = '',
    bool multiline = false,
    bool readOnly = false,
    double fontSize = 0,
    String? tooltip,
    String alignment = 'left',
  }) {
    _fieldSpecs.add(_FieldSpec(
      type: _FieldType.text,
      name: name,
      rect: rect,
      tooltip: tooltip,
      extra: {
        'defaultValue': defaultValue,
        'multiline': multiline,
        'readOnly': readOnly,
        'fontSize': fontSize,
        'alignment': alignment,
      },
    ));
  }

  void addCheckbox({
    required String name,
    required List<double> rect,
    bool checked = false,
    String? tooltip,
  }) {
    _fieldSpecs.add(_FieldSpec(
      type: _FieldType.checkbox,
      name: name,
      rect: rect,
      tooltip: tooltip,
      extra: {'checked': checked},
    ));
  }

  void addRadioGroup({
    required String groupName,
    required List<Map<String, dynamic>> options,
    String? selectedValue,
    String? tooltip,
  }) {
    _fieldSpecs.add(_FieldSpec(
      type: _FieldType.radio,
      name: groupName,
      rect: [0, 0, 0, 0],
      tooltip: tooltip,
      extra: {
        'options': options,
        'selectedValue': selectedValue,
      },
    ));
  }

  void addDropdown({
    required String name,
    required List<double> rect,
    required List<dynamic> options,
    String? selectedValue,
    String? tooltip,
  }) {
    _fieldSpecs.add(_FieldSpec(
      type: _FieldType.choice,
      name: name,
      rect: rect,
      tooltip: tooltip,
      extra: {'options': options, 'selectedValue': selectedValue},
    ));
  }

  void addSignatureField({
    required String name,
    required List<double> rect,
    String? tooltip,
  }) {
    _fieldSpecs.add(_FieldSpec(
      type: _FieldType.signature,
      name: name,
      rect: rect,
      tooltip: tooltip,
      extra: {},
    ));
  }

  // ─── Image background ──────────────────────────────────────────────────────

  /// Adds an image (raw RGBA pixels) as a background.
  /// [swapRedBlue] defaults to true because pdfrx often returns BGRA.
  void addImage({
    required Uint8List rgbaPixels,
    required int width,
    required int height,
    required double x,
    required double y,
    required double targetWidth,
    required double targetHeight,
    bool swapRedBlue = true,
  }) {
    final rgbData = Uint8List(width * height * 3);
    int idx = 0;
    for (int i = 0; i < rgbaPixels.length; i += 4) {
      if (swapRedBlue) {
        // BGRA → RGB (swap R and B)
        rgbData[idx++] = rgbaPixels[i + 2];
        rgbData[idx++] = rgbaPixels[i + 1];
        rgbData[idx++] = rgbaPixels[i];
      } else {
        rgbData[idx++] = rgbaPixels[i];
        rgbData[idx++] = rgbaPixels[i + 1];
        rgbData[idx++] = rgbaPixels[i + 2];
      }
    }

    // Compress with zlib (raw)
    final compressed = ZLibEncoder().encode(rgbData);

    // Store as an XObject
    final int imageId = _doc._allocId();
    _doc._storeObject(imageId, [
      ..._a(
          '<< /Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${compressed.length} >>\nstream\n'),
      ...compressed,
      ..._a('\nendstream'),
    ]);

    // Remember this image ID for page resources
    _imageIds.add(imageId);

    // Add the image to the page content
    _ops.add(
        'q ${_f(targetWidth)} 0 0 ${_f(targetHeight)} ${_f(x)} ${_f(y)} cm /Img$imageId Do Q');
  }

  // ─── Internal build ────────────────────────────────────────────────────────

  _PageBuildResult _build(PdfDocumentBuilder doc) {
    final int pageId = doc._allocId();

    final List<int> fieldIds = [];
    final List<int> annotIds = [];

    for (final spec in _fieldSpecs) {
      final result = _buildField(spec, doc, pageId);
      fieldIds.addAll(result.acroFormIds);
      annotIds.addAll(result.annotIds);
    }

    // Page content stream
    final String content = _ops.join('\n');
    final List<int> contentBytes = PdfDocumentBuilder._bytes(content);
    final int contentId = doc._allocId();
    doc._storeObject(contentId, [
      ..._a('<< /Length ${contentBytes.length} >>\nstream\n'),
      ...contentBytes,
      ..._a('\nendstream'),
    ]);

    // Build /Resources dictionary with Font and XObject
    final StringBuffer resources = StringBuffer();
    resources.writeln('/Font << /Helv ${doc._fontId} 0 R >>');

    if (_imageIds.isNotEmpty) {
      resources.write('/XObject << ');
      for (final id in _imageIds) {
        resources.write('/Img$id $id 0 R ');
      }
      resources.writeln('>>');
    }

    final String annotsArr = annotIds.map((id) => '$id 0 R').join(' ');
    doc._storeObject(pageId, PdfDocumentBuilder._bytes('''<<
  /Type /Page
  /Parent ${doc._pagesId} 0 R
  /MediaBox [0 0 ${_f(pageWidth)} ${_f(pageHeight)}]
  /Contents $contentId 0 R
  /Resources <<
$resources
  >>
  /Annots [$annotsArr]
>>'''));

    return _PageBuildResult(pageId: pageId, fieldIds: fieldIds);
  }

  // ─── Field builders ───────────────────────────────────────────────────────

  _FieldBuildResult _buildField(
      _FieldSpec spec, PdfDocumentBuilder doc, int pageId) {
    switch (spec.type) {
      case _FieldType.text:
        final id = _buildTextField(spec, doc, pageId);
        return _FieldBuildResult(acroFormIds: [id], annotIds: [id]);
      case _FieldType.checkbox:
        final id = _buildCheckbox(spec, doc, pageId);
        return _FieldBuildResult(acroFormIds: [id], annotIds: [id]);
      case _FieldType.radio:
        return _buildRadioGroup(spec, doc, pageId);
      case _FieldType.choice:
        final id = _buildDropdown(spec, doc, pageId);
        return _FieldBuildResult(acroFormIds: [id], annotIds: [id]);
      case _FieldType.signature:
        final id = _buildSignature(spec, doc, pageId);
        return _FieldBuildResult(acroFormIds: [id], annotIds: [id]);
    }
  }

  int _buildTextField(_FieldSpec spec, PdfDocumentBuilder doc, int pageId) {
    final bool ml = spec.extra['multiline'] as bool? ?? false;
    final bool ro = spec.extra['readOnly'] as bool? ?? false;
    final String dv = spec.extra['defaultValue'] as String? ?? '';
    final double fs = (spec.extra['fontSize'] as double?) ?? 0;
    final String align = spec.extra['alignment'] as String? ?? 'left';
    final int q = align == 'center' ? 1 : align == 'right' ? 2 : 0;
    int ff = 0;
    if (ml) ff |= 1 << 12;
    if (ro) ff |= 1;
    final String valLine = dv.isNotEmpty
        ? '/V (${PdfDocumentBuilder._esc(dv)}) /DV (${PdfDocumentBuilder._esc(dv)})'
        : '';
    final String tip = spec.tooltip != null
        ? '/TU (${PdfDocumentBuilder._esc(spec.tooltip!)})'
        : '';
    final int id = doc._allocId();
    doc._storeObject(id, PdfDocumentBuilder._bytes('''<<
  /Type /Annot /Subtype /Widget /FT /Tx
  /T (${PdfDocumentBuilder._esc(spec.name)}) $tip
  /Rect [${_rectStr(spec.rect)}]
  /P $pageId 0 R
  /DA (/Helv ${_f(fs)} Tf 0 g) /Q $q /Ff $ff $valLine
  /MK << /BC [0 0 0] /BG [1 1 1] >>
  /BS << /W 0.5 /S /S >>
>>'''));
    return id;
  }

  int _buildCheckbox(_FieldSpec spec, PdfDocumentBuilder doc, int pageId) {
    final bool checked = spec.extra['checked'] as bool? ?? false;
    final String state = checked ? '/Yes' : '/Off';
    final double w = (spec.rect[2] - spec.rect[0]).abs();
    final double h = (spec.rect[3] - spec.rect[1]).abs();
    final String tip = spec.tooltip != null
        ? '/TU (${PdfDocumentBuilder._esc(spec.tooltip!)})'
        : '';

    final int onApId = doc._allocId();
    final int offApId = doc._allocId();

    final String yesContent = _checkboxContent(w, h, true);
    doc._storeObject(
        onApId,
        PdfDocumentBuilder._bytes(
            '<< /Type /XObject /Subtype /Form /BBox [0 0 ${_f(w)} ${_f(h)}] /Length ${yesContent.length} >>\nstream\n$yesContent\nendstream'));

    final String offContent = _checkboxContent(w, h, false);
    doc._storeObject(
        offApId,
        PdfDocumentBuilder._bytes(
            '<< /Type /XObject /Subtype /Form /BBox [0 0 ${_f(w)} ${_f(h)}] /Length ${offContent.length} >>\nstream\n$offContent\nendstream'));

    final int id = doc._allocId();
    doc._storeObject(id, PdfDocumentBuilder._bytes('''<<
  /Type /Annot /Subtype /Widget /FT /Btn
  /T (${PdfDocumentBuilder._esc(spec.name)}) $tip
  /Rect [${_rectStr(spec.rect)}]
  /P $pageId 0 R /V $state /AS $state
  /AP << /N << /Yes $onApId 0 R /Off $offApId 0 R >> >>
  /MK << /BC [0 0 0] /BG [1 1 1] >>
>>'''));
    return id;
  }

  _FieldBuildResult _buildRadioGroup(
      _FieldSpec spec, PdfDocumentBuilder doc, int pageId) {
    final List options = spec.extra['options'] as List;
    final String? selVal = spec.extra['selectedValue'] as String?;
    final String tip = spec.tooltip != null
        ? '/TU (${PdfDocumentBuilder._esc(spec.tooltip!)})'
        : '';

    final List<int> kidIds = [];

    for (final opt in options) {
      final String exportVal = opt['exportValue'] as String? ?? '/Yes';
      final List<double> rect = (opt['rect'] as List).cast<double>();
      final bool selected = exportVal == selVal;
      final double w = (rect[2] - rect[0]).abs();
      final double h = (rect[3] - rect[1]).abs();

      final int onApId = doc._allocId();
      final int offApId = doc._allocId();

      final String onContent = _radioContent(w, h, true);
      final String offContent = _radioContent(w, h, false);
      doc._storeObject(
          onApId,
          PdfDocumentBuilder._bytes(
              '<< /Type /XObject /Subtype /Form /BBox [0 0 ${_f(w)} ${_f(h)}] /Length ${onContent.length} >>\nstream\n$onContent\nendstream'));
      doc._storeObject(
          offApId,
          PdfDocumentBuilder._bytes(
              '<< /Type /XObject /Subtype /Form /BBox [0 0 ${_f(w)} ${_f(h)}] /Length ${offContent.length} >>\nstream\n$offContent\nendstream'));

      final int kidId = doc._allocId();
      doc._storeObject(kidId, PdfDocumentBuilder._bytes('''<<
  /Type /Annot /Subtype /Widget
  /Rect [${_rectStr(rect)}]
  /P $pageId 0 R
  /AS ${selected ? exportVal : '/Off'}
  /AP << /N << $exportVal $onApId 0 R /Off $offApId 0 R >> >>
>>'''));
      kidIds.add(kidId);
    }

    final String kidsArr = kidIds.map((k) => '$k 0 R').join(' ');
    final String currentVal = selVal ?? '/Off';
    final int parentId = doc._allocId();
    doc._storeObject(parentId, PdfDocumentBuilder._bytes('''<<
  /FT /Btn /T (${PdfDocumentBuilder._esc(spec.name)}) $tip
  /Ff 32768 /V $currentVal
  /Kids [$kidsArr]
>>'''));

    return _FieldBuildResult(acroFormIds: [parentId], annotIds: kidIds);
  }

  int _buildDropdown(_FieldSpec spec, PdfDocumentBuilder doc, int pageId) {
    final List options = spec.extra['options'] as List;
    final String? selVal = spec.extra['selectedValue'] as String?;
    final String tip = spec.tooltip != null
        ? '/TU (${PdfDocumentBuilder._esc(spec.tooltip!)})'
        : '';

    final String optsStr = options.map((o) {
      if (o is List && o.length >= 2) {
        return '[(${PdfDocumentBuilder._esc(o[0].toString())}) (${PdfDocumentBuilder._esc(o[1].toString())})]';
      }
      return '(${PdfDocumentBuilder._esc(o.toString())})';
    }).join(' ');

    final String valStr =
        selVal != null ? '/V (${PdfDocumentBuilder._esc(selVal)})' : '';

    final int id = doc._allocId();
    doc._storeObject(id, PdfDocumentBuilder._bytes('''<<
  /Type /Annot /Subtype /Widget /FT /Ch
  /T (${PdfDocumentBuilder._esc(spec.name)}) $tip
  /Rect [${_rectStr(spec.rect)}]
  /P $pageId 0 R /Ff 131072
  /Opt [$optsStr] $valStr
  /DA (/Helv 10 Tf 0 g)
  /MK << /BC [0 0 0] /BG [1 1 1] >>
  /BS << /W 0.5 /S /S >>
>>'''));
    return id;
  }

  int _buildSignature(_FieldSpec spec, PdfDocumentBuilder doc, int pageId) {
    final String tip = spec.tooltip != null
        ? '/TU (${PdfDocumentBuilder._esc(spec.tooltip!)})'
        : '';
    final int id = doc._allocId();
    doc._storeObject(id, PdfDocumentBuilder._bytes('''<<
  /Type /Annot /Subtype /Widget /FT /Sig
  /T (${PdfDocumentBuilder._esc(spec.name)}) $tip
  /Rect [${_rectStr(spec.rect)}]
  /P $pageId 0 R
  /MK << /BC [0.2 0.4 0.8] /BG [0.94 0.97 1] >>
  /BS << /W 0.5 /S /S >>
>>'''));
    return id;
  }

  // ─── Appearance content streams ────────────────────────────────────────────

  String _checkboxContent(double w, double h, bool checked) {
    if (!checked) {
      return 'q 1 g 0 0 ${_f(w)} ${_f(h)} re f 0.8 g 0.5 w 0 0 ${_f(w)} ${_f(h)} re S Q';
    }
    final double mx = w * 0.15, my = h * 0.2;
    final double px = w * 0.38, py = h * 0.05;
    final double tx = w * 0.85, ty = h * 0.78;
    return 'q 1 g 0 0 ${_f(w)} ${_f(h)} re f 0 g 1.5 w ${_f(mx)} ${_f(my)} m ${_f(px)} ${_f(py)} l ${_f(tx)} ${_f(ty)} l S Q';
  }

  String _radioContent(double w, double h, bool selected) {
    final cx = w / 2;
    final cy = h / 2;
    final r = w / 2 - 1;
    const k = 0.5523;
    String circ(double cx, double cy, double r) =>
        '${_f(cx + r)} ${_f(cy)} m ${_f(cx + r)} ${_f(cy + r * k)} ${_f(cx + r * k)} ${_f(cy + r)} ${_f(cx)} ${_f(cy + r)} c ${_f(cx - r * k)} ${_f(cy + r)} ${_f(cx - r)} ${_f(cy + r * k)} ${_f(cx - r)} ${_f(cy)} c ${_f(cx - r)} ${_f(cy - r * k)} ${_f(cx - r * k)} ${_f(cy - r)} ${_f(cx)} ${_f(cy - r)} c ${_f(cx + r * k)} ${_f(cy - r)} ${_f(cx + r)} ${_f(cy - r * k)} ${_f(cx + r)} ${_f(cy)} c ';
    if (!selected) {
      return 'q 1 g ${circ(cx, cy, r)}f 0.7 g 0.5 w ${circ(cx, cy, r)}S Q';
    }
    return 'q 1 g ${circ(cx, cy, r)}f 0 g ${circ(cx, cy, r * 0.4)}f Q';
  }

  static List<int> _a(String s) => s.codeUnits;
  static String _f(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(3);
  static String _rectStr(List<double> r) => r.map(_f).join(' ');
}

// ─── Internal helpers ──────────────────────────────────────────────────────────

enum _FieldType { text, checkbox, radio, choice, signature }

class _FieldSpec {
  final _FieldType type;
  final String name;
  final List<double> rect;
  final String? tooltip;
  final Map<String, dynamic> extra;
  _FieldSpec({
    required this.type,
    required this.name,
    required this.rect,
    required this.extra,
    this.tooltip,
  });
}

class _PageBuildResult {
  final int pageId;
  final List<int> fieldIds;
  _PageBuildResult({required this.pageId, required this.fieldIds});
}

class _FieldBuildResult {
  final List<int> acroFormIds;
  final List<int> annotIds;
  const _FieldBuildResult({required this.acroFormIds, required this.annotIds});
}

class _PageBuilder extends PdfPageBuilder {
  _PageBuilder({
    required super.pageWidth,
    required super.pageHeight,
    required super.builder,
  });
}