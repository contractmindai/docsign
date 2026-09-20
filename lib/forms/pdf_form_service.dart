import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:archive/archive.dart' show ZLibEncoder;

import '../pdf_core/document.dart';
import '../pdf_core/lexer.dart' show PdfRawString;
import '../pdf_core/object_parser.dart';
import '../pdf_core/xref_parser.dart';
import '../pdf_core/incremental_writer.dart';
import '../pdf_core/verifier.dart';
import 'page_context_editor.dart' show PdfDocumentKind;
import 'acroform.dart';
import 'field_filler.dart';

class PdfFormInfo {
  final PdfDocumentKind kind;
  final bool hasAcroFields;
  final bool hasXfa;
  final bool isXfaDynamic;
  final String? xfaWarning;

  const PdfFormInfo({
    required this.kind,
    required this.hasAcroFields,
    required this.hasXfa,
    required this.isXfaDynamic,
    this.xfaWarning,
  });

  String get summary {
    switch (kind) {
      case PdfDocumentKind.acroForm:
        return 'Standard AcroForm — full fill support.';
      case PdfDocumentKind.xfaStatic:
        return 'Static XFA form — basic AcroForm fields supported; '
            'XFA scripting ignored.';
      case PdfDocumentKind.xfaDynamic:
        return 'Dynamic XFA form — cannot be filled without LiveCycle runtime.';
      case PdfDocumentKind.flat:
        return 'Flat PDF — no form fields. Use PageContentEditor.';
      case PdfDocumentKind.unknown:
        return 'Unknown or unreadable PDF.';
    }
  }
}

class PdfFormOpenResult {
  final PdfFormDocument? document;
  final String? unsupportedReason;
  final PdfFormInfo info;

  const PdfFormOpenResult.ok(this.document, this.info)
      : unsupportedReason = null;
  const PdfFormOpenResult.unsupported(this.unsupportedReason, this.info)
      : document = null;

  bool get isSupported => document != null;
}

class PdfFormDocument {
  final Uint8List originalBytes;
  List<AcroFormField> fields;
  final PdfFormInfo info;

  final int _acroFormObjectId;
  final int _catalogObjectId;
  final PdfDocumentEngine _engine;

  final List<IncrementalUpdatePayload> _pendingUpdates = [];
  int _nextObjectId;

  final Set<int> _removedFieldObjectIds = {};

  PdfFormDocument._(
    this.originalBytes,
    this.fields,
    this.info,
    this._nextObjectId,
    this._acroFormObjectId,
    this._catalogObjectId,
    this._engine,
  );

  static PdfFormOpenResult open(Uint8List bytes) {
    final PdfDocumentEngine engine;
    try {
      engine = PdfDocumentEngine(bytes);
    } catch (e) {
      final info = PdfFormInfo(
          kind: PdfDocumentKind.unknown,
          hasAcroFields: false,
          hasXfa: false,
          isXfaDynamic: false);
      return PdfFormOpenResult.unsupported('Cannot parse PDF: $e', info);
    }

    if (!engine.hasUsableXref) {
      final info = PdfFormInfo(
          kind: PdfDocumentKind.unknown,
          hasAcroFields: false,
          hasXfa: false,
          isXfaDynamic: false);
      return PdfFormOpenResult.unsupported(
          'Cannot read cross-reference table.', info);
    }

    final catalog = engine.catalog;
    if (catalog == null) {
      final info = PdfFormInfo(
          kind: PdfDocumentKind.unknown,
          hasAcroFields: false,
          hasXfa: false,
          isXfaDynamic: false);
      return PdfFormOpenResult.unsupported('Cannot locate catalog.', info);
    }

    final Map<String, dynamic>? acroFormDict =
        _resolveDict(catalog['/AcroForm'], engine);

    if (acroFormDict == null) {
      final info = PdfFormInfo(
          kind: PdfDocumentKind.flat,
          hasAcroFields: false,
          hasXfa: false,
          isXfaDynamic: false);
      return PdfFormOpenResult.unsupported(
          'No AcroForm. Use PageContentEditor.', info);
    }

    final bool hasXfa = acroFormDict.containsKey('/XFA');
    final bool isDynamic = hasXfa && _isXfaDynamic(acroFormDict['/XFA']);

    if (isDynamic) {
      final info = PdfFormInfo(
          kind: PdfDocumentKind.xfaDynamic,
          hasAcroFields: false,
          hasXfa: true,
          isXfaDynamic: true);
      return PdfFormOpenResult.unsupported(
          'Dynamic XFA form — requires Adobe LiveCycle.', info);
    }

    _resolveEveryObject(engine);
    final fields = PdfAcroFormTreeWalker(engine.resolvedObjectsCache)
        .locateFormFields(catalog);

    final kind =
        hasXfa ? PdfDocumentKind.xfaStatic : PdfDocumentKind.acroForm;
    final info = PdfFormInfo(
      kind: kind,
      hasAcroFields: fields.isNotEmpty,
      hasXfa: hasXfa,
      isXfaDynamic: false,
      xfaWarning: hasXfa
          ? 'XFA data present — only AcroForm fields are supported.'
          : null,
    );

    if (fields.isEmpty) {
      return PdfFormOpenResult.unsupported('No fillable fields found.', info);
    }

    final acroFormRef = catalog['/AcroForm'];
    final int acroFormObjId = acroFormRef is PdfIndirectReference
        ? acroFormRef.objectId
        : -1;
    final int catalogObjId = _findCatalogObjectId(engine);

    return PdfFormOpenResult.ok(
        PdfFormDocument._(
          bytes, fields, info, engine.highestObjectId + 1,
          acroFormObjId, catalogObjId, engine,
        ),
        info);
  }

  static int _findCatalogObjectId(PdfDocumentEngine engine) {
    final rootRef = engine.globalXrefTable.trailerDict['/Root'];
    if (rootRef is PdfIndirectReference) return rootRef.objectId;
    for (final id in engine.globalXrefTable.offsets.keys) {
      final obj = engine.resolvedObjectsCache[id];
      if (obj is Map<String, dynamic> && obj['/Type']?.toString() == '/Catalog') {
        return id;
      }
    }
    return -1;
  }

  // ─── Field lookup ──────────────────────────────────────────────────────────

  AcroFormField? findField(String name) {
    try { return fields.firstWhere((f) => f.fullyQualifiedName == name); }
    catch (_) {}
    try { return fields.firstWhere(
        (f) => f.fullyQualifiedName.toLowerCase() == name.toLowerCase()); }
    catch (_) {}
    try { return fields.firstWhere(
        (f) => f.partialName.toLowerCase() == name.toLowerCase()); }
    catch (_) {}
    return null;
  }

  List<AcroFormField> get textFields =>
      fields.where((f) => f.type == AcroFieldType.text).toList();
  List<AcroFormField> get checkboxFields =>
      fields.where((f) => f.type == AcroFieldType.checkbox).toList();
  List<AcroFormField> get radioGroups =>
      fields.where((f) => f.type == AcroFieldType.radio).toList();
  List<AcroFormField> get choiceFields =>
      fields.where((f) => f.type == AcroFieldType.choice).toList();
  List<AcroFormField> get signatureFields =>
      fields.where((f) => f.type == AcroFieldType.signature).toList();

  Map<String, String> get currentValues => {
        for (final f in fields)
          f.fullyQualifiedName: _valueStr(f.currentValue),
      };

  // ─── Setters ───────────────────────────────────────────────────────────────

  void setTextValue(AcroFormField field, String value) {
    _require(field, AcroFieldType.text, 'setTextValue');
    final apId = _nextObjectId++;
    _pendingUpdates.addAll(PdfFieldFiller().fillTextField(
      fieldObjectId: field.objectId,
      originalFieldDict: field.rawDict,
      newAppearanceObjectId: apId,
      textValue: value,
    ));
  }

  void setCheckboxValue(AcroFormField field, bool checked) {
    _require(field, AcroFieldType.checkbox, 'setCheckboxValue');
    final onState = _checkboxOnState(field.rawDict);
    final yesId = _nextObjectId++;
    final offId = _nextObjectId++;
    _pendingUpdates.addAll(PdfFieldFiller().fillCheckboxField(
      fieldObjectId: field.objectId,
      originalFieldDict: field.rawDict,
      yesAppearanceObjectId: yesId,
      offAppearanceObjectId: offId,
      isChecked: checked,
      customOnStateName: checked ? onState : null,
    ));
  }

  void setRadioValue(AcroFormField field, String selectedValue) {
    _require(field, AcroFieldType.radio, 'setRadioValue');
    final kids = field.radioKids;
    final apIds = kids.map((_) => [_nextObjectId++, _nextObjectId++]).toList();
    _pendingUpdates.addAll(PdfFieldFiller().fillRadioGroup(
      parentObjectId: field.objectId,
      parentFieldDict: field.rawDict,
      kids: kids.map((k) => k.rawDict).toList(),
      kidObjectIds: kids.map((k) => k.objectId).toList(),
      apObjectIds: apIds,
      selectedStateName: selectedValue,
    ));
  }

  void setChoiceValue(AcroFormField field, String value) {
    _require(field, AcroFieldType.choice, 'setChoiceValue');
    final apId = _nextObjectId++;
    _pendingUpdates.addAll(PdfFieldFiller().fillChoiceField(
      fieldObjectId: field.objectId,
      originalFieldDict: field.rawDict,
      newAppearanceObjectId: apId,
      selectedValue: value,
    ));
  }

  void setSignatureValue(AcroFormField field, String text,
      {String mode = 'text'}) {
    _require(field, AcroFieldType.signature, 'setSignatureValue');
    final apId = _nextObjectId++;
    _pendingUpdates.addAll(PdfFieldFiller().fillSignatureFieldVisual(
      fieldObjectId: field.objectId,
      originalFieldDict: field.rawDict,
      newAppearanceObjectId: apId,
      signatureText: text,
      mode: mode,
    ));
  }

  // ─── Signature image embedding (corrected byte-level streams) ──────────

  void setSignatureImage(AcroFormField field, Uint8List pngBytes) {
    _require(field, AcroFieldType.signature, 'setSignatureImage');

    final image = img.decodePng(pngBytes);
    if (image == null) {
      throw ArgumentError('Invalid PNG image data');
    }

    // Get field rectangle
    final rectObj = field.rawDict['/Rect'];
    if (rectObj is! List || rectObj.length < 4) {
      throw ArgumentError('Field /Rect is missing or invalid');
    }
    final rect = rectObj.map((e) => (e as num).toDouble()).toList();
    final double fieldWidth = rect[2] - rect[0];
    final double fieldHeight = rect[3] - rect[1];

    // Convert RGBA to RGB
    final rgbData = Uint8List(image.width * image.height * 3);
    int idx = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        rgbData[idx++] = pixel.r.toInt();
        rgbData[idx++] = pixel.g.toInt();
        rgbData[idx++] = pixel.b.toInt();
      }
    }
    final compressed = ZLibEncoder().encode(rgbData);

    // Build image XObject as raw bytes (no String.fromCharCodes on compressed data)
    final int imageXObjId = _nextObjectId++;
    final List<int> imageStream = [
      ..._a('<< /Type /XObject /Subtype /Image /Width ${image.width} /Height ${image.height} '),
      ..._a('/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${compressed.length} >>\n'),
      ..._a('stream\n'),
      ...compressed,
      ..._a('\nendstream'),
    ];
    _pendingUpdates.add(IncrementalUpdatePayload(imageXObjId, 0, _bytesToStr(imageStream)));

    // Build Form XObject that references the image and scales it to the field rect
    final int formXObjId = _nextObjectId++;
    final String formContent =
        'q\n'
        '1 1 1 rg\n'
        '0 0 ${fieldWidth} ${fieldHeight} re f\n'   // white background
        'q ${fieldWidth} 0 0 ${fieldHeight} 0 0 cm /Img Do Q\n'
        'Q';
    final List<int> formStream = [
      ..._a('<< /Type /XObject /Subtype /Form /BBox [0 0 ${fieldWidth} ${fieldHeight}] '),
      ..._a('/Resources << /XObject << /Img $imageXObjId 0 R >> >> '),
      ..._a('/Length ${formContent.length} >>\nstream\n'),
      ..._a(formContent),
      ..._a('\nendstream'),
    ];
    _pendingUpdates.add(IncrementalUpdatePayload(formXObjId, 0, _bytesToStr(formStream)));

    // Update field dictionary – set /AP to use the Form XObject, set /V, and do NOT set /AS
    final updatedDict = Map<String, dynamic>.from(field.rawDict);
    updatedDict['/AP'] = _RawToken('<< /N $formXObjId 0 R >>');
    updatedDict['/V'] = _RawToken('<</Type /Sig /Contents (Signed)>>');

    // Ensure white background in /MK
    final existingMk = field.rawDict['/MK'] as Map<String, dynamic>? ?? {};
    final newMk = Map<String, dynamic>.from(existingMk);
    newMk['/BG'] = [1.0, 1.0, 1.0];
    if (!newMk.containsKey('/BC')) {
      newMk['/BC'] = [0.2, 0.4, 0.8];
    }
    updatedDict['/MK'] = _RawToken(_serializeFieldDict(newMk));

    _pendingUpdates.add(IncrementalUpdatePayload(
      field.objectId,
      0,
      _serializeFieldDict(updatedDict),
    ));
  }

  // Helper to convert a list of ints (bytes) to a string for IncrementalUpdatePayload
  static String _bytesToStr(List<int> bytes) => String.fromCharCodes(bytes);
  static List<int> _a(String s) => s.codeUnits;

  bool fillByName(String name, String value) {
    final f = findField(name);
    if (f == null) return false;
    switch (f.type) {
      case AcroFieldType.text: setTextValue(f, value);
      case AcroFieldType.checkbox:
        setCheckboxValue(f, value == '1' || value.toLowerCase() == 'true');
      case AcroFieldType.radio:
        setRadioValue(f, value.startsWith('/') ? value : '/$value');
      case AcroFieldType.choice: setChoiceValue(f, value);
      case AcroFieldType.signature: setSignatureValue(f, value);
      case AcroFieldType.pushbutton: return false;
      case AcroFieldType.unknown: return false;
    }
    return true;
  }

  Map<String, bool> fillAll(Map<String, String> values) =>
      {for (final e in values.entries) e.key: fillByName(e.key, e.value)};

  // ─── FR-4: Edit existing field properties ────────────────────────────────

  void editFieldProperties(
    AcroFormField field, {
    String? tooltip,
    String? defaultValue,
    double? fontSize,
    String? alignment,
    List<double>? borderColor,
    List<double>? backgroundColor,
    bool? required,
    bool? readOnly,
    int? maxLength,
  }) {
    final merged = Map<String, dynamic>.from(field.rawDict);

    if (tooltip != null) {
      merged['/TU'] = _RawToken('(${_pdfEscape(tooltip)})');
    }
    if (defaultValue != null) {
      merged['/DV'] = _RawToken('(${_pdfEscape(defaultValue)})');
    }
    if (fontSize != null) {
      final fontName = _extractFontName(field.rawDict['/DA']?.toString());
      merged['/DA'] = _RawToken('($fontName ${_fmt(fontSize)} Tf 0 g)');
    }
    if (alignment != null) {
      final q = alignment == 'center' ? 1 : alignment == 'right' ? 2 : 0;
      merged['/Q'] = q;
    }
    if (borderColor != null || backgroundColor != null) {
      final existingMk = field.rawDict['/MK'];
      final bc = borderColor ?? _mkColor(existingMk, '/BC') ?? [0, 0, 0];
      final bg = backgroundColor ?? _mkColor(existingMk, '/BG') ?? [1, 1, 1];
      merged['/MK'] = _RawToken(
          '<< /BC [${bc.map(_fmt).join(' ')}] /BG [${bg.map(_fmt).join(' ')}] >>');
    }
    if (required != null || readOnly != null) {
      int ff = (field.rawDict['/Ff'] as num?)?.toInt() ?? 0;
      if (required != null) {
        ff = required ? (ff | 2) : (ff & ~2);
      }
      if (readOnly != null) {
        ff = readOnly ? (ff | 1) : (ff & ~1);
      }
      merged['/Ff'] = ff;
    }
    if (maxLength != null) {
      merged['/MaxLen'] = maxLength;
    }

    _pendingUpdates.add(IncrementalUpdatePayload(
      field.objectId, 0, _serializeFieldDict(merged),
    ));

    final idx = fields.indexWhere((f) => f.objectId == field.objectId);
    if (idx >= 0) {
      fields[idx] = AcroFormField(
        partialName: field.partialName,
        fullyQualifiedName: field.fullyQualifiedName,
        fieldType: field.fieldType,
        type: field.type,
        objectId: field.objectId,
        currentValue: field.currentValue,
        rawDict: merged,
        radioKids: field.radioKids,
      );
    }
  }

  // ─── FR-5: Delete fields ──────────────────────────────────────────────────

  bool deleteField(AcroFormField field) {
    final idx = fields.indexWhere((f) => f.objectId == field.objectId);
    if (idx < 0) return false;

    _removedFieldObjectIds.add(field.objectId);
    for (final kid in field.radioKids) {
      _removedFieldObjectIds.add(kid.objectId);
    }
    fields.removeAt(idx);
    return true;
  }

  int deleteFields(List<AcroFormField> toDelete) {
    int count = 0;
    for (final f in toDelete) {
      if (deleteField(f)) count++;
    }
    return count;
  }

  // ─── FR-6: Duplicate fields ──────────────────────────────────────────────

  AcroFormField duplicateField(
    AcroFormField field, {
    required String newName,
    List<double>? newRect,
  }) {
    final int newId = _nextObjectId++;

    final List<double> rect = newRect ??
        (() {
          final r = field.rawDict['/Rect'];
          if (r is List && r.length == 4) {
            final orig = r.cast<num>().map((n) => n.toDouble()).toList();
            return [orig[0] + 20, orig[1] - 20, orig[2] + 20, orig[3] - 20];
          }
          return [72.0, 700.0, 220.0, 720.0];
        })();

    final dup = Map<String, dynamic>.from(field.rawDict);
    dup['/T'] = _RawToken('(${_pdfEscape(newName)})');
    dup['/Rect'] = _RawToken('[${rect.map(_fmt).join(' ')}]');
    dup.remove('/V');
    dup.remove('/AS');
    if (field.type == AcroFieldType.checkbox || field.type == AcroFieldType.radio) {
      dup['/V'] = '/Off';
      dup['/AS'] = '/Off';
    }

    _pendingUpdates.add(IncrementalUpdatePayload(newId, 0, _serializeFieldDict(dup)));

    final newField = AcroFormField(
      partialName: newName,
      fullyQualifiedName: newName,
      fieldType: field.fieldType,
      type: field.type,
      objectId: newId,
      currentValue: null,
      rawDict: dup,
      radioKids: const [],
    );

    fields.add(newField);
    _newFieldObjectIds.add(newId);
    return newField;
  }

  // ─── FR-9: Validation ──────────────────────────────────────────────────────

  String? validateValue(AcroFormField field, String value, {FieldValidationRule? rule}) {
    final ff = (field.rawDict['/Ff'] as num?)?.toInt() ?? 0;
    final bool isRequired = (ff & 2) != 0;

    if (isRequired && value.trim().isEmpty) {
      return '${_displayName(field)} is required.';
    }
    if (value.isEmpty) return null;

    final maxLen = (field.rawDict['/MaxLen'] as num?)?.toInt();
    if (maxLen != null && value.length > maxLen) {
      return '${_displayName(field)} must be $maxLen characters or fewer.';
    }

    if (rule != null) {
      return rule.validate(value, fieldLabel: _displayName(field));
    }
    return null;
  }

  Map<String, String> validateAll(
    Map<String, String> values, {
    Map<String, FieldValidationRule>? rules,
  }) {
    final errors = <String, String>{};
    for (final f in fields) {
      if (f.type != AcroFieldType.text && f.type != AcroFieldType.choice) continue;
      final value = values[f.fullyQualifiedName] ?? '';
      final rule = rules?[f.fullyQualifiedName];
      final error = validateValue(f, value, rule: rule);
      if (error != null) errors[f.fullyQualifiedName] = error;
    }
    return errors;
  }

  String _displayName(AcroFormField f) =>
      f.partialName.isEmpty ? f.fullyQualifiedName : f.partialName;

  // ─── FR-8: Import / Export ──────────────────────────────────────────────

  String exportJson() {
    final map = <String, dynamic>{
      for (final f in fields) f.fullyQualifiedName: _exportValue(f),
    };
    return jsonEncode(map);
  }

  Map<String, bool> importJson(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final values = decoded.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    return fillAll(values);
  }

  String exportFdf() {
    final buf = StringBuffer();
    buf.write('%FDF-1.2\n1 0 obj\n<< /FDF << /Fields [\n');
    for (final f in fields) {
      if (f.type == AcroFieldType.pushbutton) continue;
      final value = _exportValue(f);
      buf.write('<< /T (${_pdfEscape(f.fullyQualifiedName)}) '
          '/V (${_pdfEscape(value)}) >>\n');
    }
    buf.write('] >> >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n');
    return buf.toString();
  }

  Map<String, bool> importFdf(String fdfText) {
    final re = RegExp(
        r'/T\s*\(((?:[^()\\]|\\.)*)\)\s*/V\s*\(((?:[^()\\]|\\.)*)\)',
        dotAll: true);
    final values = <String, String>{};
    for (final m in re.allMatches(fdfText)) {
      final name = _unescapePdfString(m.group(1) ?? '');
      final value = _unescapePdfString(m.group(2) ?? '');
      values[name] = value;
    }
    return fillAll(values);
  }

  String exportXfdf() {
    final buf = StringBuffer();
    buf.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    buf.write('<xfdf xmlns="http://ns.adobe.com/xfdf/" xml:space="preserve">\n');
    buf.write('  <fields>\n');
    for (final f in fields) {
      if (f.type == AcroFieldType.pushbutton) continue;
      final value = _exportValue(f);
      buf.write('    <field name="${_xmlEscape(f.fullyQualifiedName)}">\n');
      buf.write('      <value>${_xmlEscape(value)}</value>\n');
      buf.write('    </field>\n');
    }
    buf.write('  </fields>\n</xfdf>\n');
    return buf.toString();
  }

  Map<String, bool> importXfdf(String xfdfText) {
    final fieldRe = RegExp(
        r'<field\s+name="((?:[^"\\]|\\.)*)"[^>]*>\s*<value>(.*?)</value>',
        dotAll: true);
    final values = <String, String>{};
    for (final m in fieldRe.allMatches(xfdfText)) {
      final name = _xmlUnescape(m.group(1) ?? '');
      final value = _xmlUnescape(m.group(2) ?? '');
      values[name] = value;
    }
    return fillAll(values);
  }

  String _exportValue(AcroFormField f) {
    final v = f.currentValue;
    if (v == null) return '';
    if (v is PdfRawString) return v.text;
    return v.toString();
  }

  // ─── Saving ────────────────────────────────────────────────────────────────

  bool get hasPendingChanges => _pendingUpdates.isNotEmpty;

  final Set<int> _newFieldObjectIds = {};

  Uint8List save({bool verify = true}) {
    final bool hasDeletions = _removedFieldObjectIds.isNotEmpty;
    if (_pendingUpdates.isEmpty && !hasDeletions) return originalBytes;

    if (hasDeletions) {
      _applyDeletions();
    }

    final xref = PdfXrefParser(originalBytes).findLastStartXref();

    // The incremental trailer must re-declare /Root. Without it, some
    // readers (Acrobat Windows in particular) refuse to open the appended
    // file because they won't follow /Prev to reach the original trailer.
    final engineRootRef = _engine.globalXrefTable.trailerDict['/Root'];
    if (engineRootRef is! PdfIndirectReference) {
      throw StateError('Source PDF has no /Root in its trailer');
    }

    final result = PdfIncrementalWriter.appendUpdates(
      originalBytes,
      _pendingUpdates,
      xref,
      _nextObjectId - 1,
      rootRef: engineRootRef,
    );
    if (verify) {
      final check = PdfOutputVerifier().verifyDocumentBytes(result);
      if (!check.isValid) {
        throw StateError('PDF verification failed: ${check.report}');
      }
    }
    return result;
  }

  void _applyDeletions() {
    if (_acroFormObjectId < 0) return;

    final keptIds = fields
        .where((f) => f.type != AcroFieldType.radio || f.radioKids.isNotEmpty)
        .map((f) => f.objectId)
        .toList();
    final fieldsArr = keptIds.map((id) => '$id 0 R').join(' ');

    _pendingUpdates.add(IncrementalUpdatePayload(
      _acroFormObjectId,
      0,
      '<< /Fields [$fieldsArr] /DA (/Helv 10 Tf 0 g) /NeedAppearances true >>',
    ));

    for (final id in _engine.globalXrefTable.offsets.keys) {
      final obj = _engine.resolvedObjectsCache[id];
      if (obj is! Map<String, dynamic>) continue;
      if (obj['/Type']?.toString() != '/Page') continue;

      final annots = obj['/Annots'];
      if (annots is! List) continue;

      final annotIds = annots
          .whereType<PdfIndirectReference>()
          .map((r) => r.objectId)
          .toList();
      final toRemove =
          annotIds.where((aid) => _removedFieldObjectIds.contains(aid));
      if (toRemove.isEmpty) continue;

      final keptAnnotIds =
          annotIds.where((aid) => !_removedFieldObjectIds.contains(aid));
      final updated = Map<String, dynamic>.from(obj);
      updated['/Annots'] =
          _RawToken('[${keptAnnotIds.map((aid) => '$aid 0 R').join(' ')}]');
      _pendingUpdates.add(IncrementalUpdatePayload(id, 0, _serializeFieldDict(updated)));
    }
  }

  // ─── FR-11: Flatten form ───────────────────────────────────────────────────

  void flattenForm({List<AcroFormField>? fieldsToFlatten}) {
    final targets = fieldsToFlatten ?? List<AcroFormField>.from(fields);
    if (targets.isEmpty) return;

    final Map<int, List<AcroFormField>> byPage = {};
    for (final f in targets) {
      final pageObjId = _fieldPageObjectId(f);
      if (pageObjId < 0) continue;
      byPage.putIfAbsent(pageObjId, () => []).add(f);
    }

    for (final entry in byPage.entries) {
      final pageObjId = entry.key;
      final pageDict = _engine.resolvedObjectsCache[pageObjId];
      if (pageDict is! Map<String, dynamic>) continue;

      final ops = StringBuffer();
      for (final f in entry.value) {
        final apRef = _apStreamRef(f);
        final rect = _rectOf(f.rawDict);
        if (apRef == null || rect == null) continue;

        final resName = '/Fz${f.objectId}';
        ops.write('q 1 0 0 1 ${_fmt(rect[0].toDouble())} ${_fmt(rect[1].toDouble())} cm '
            '$resName Do Q\n');
        _flattenResourceRefs[resName] = apRef;
      }

      if (ops.isEmpty) continue;

      final overlayBody = 'q\n${ops.toString()}Q\n';
      final overlayBytes = utf8.encode(overlayBody);
      final overlayObjId = _nextObjectId++;

      final resourceEntries = entry.value
          .map((f) {
            final ref = _flattenResourceRefs['/Fz${f.objectId}'];
            if (ref == null) return '';
            return '/Fz${f.objectId} ${ref.objectId} ${ref.generation} R';
          })
          .where((s) => s.isNotEmpty)
          .join(' ');

      _pendingUpdates.add(IncrementalUpdatePayload(
        overlayObjId,
        0,
        '<< /Type /XObject /Subtype /Form '
        '/BBox [${_pageBBox(pageDict)}] '
        '/Resources << /XObject << $resourceEntries >> >> '
        '/Length ${overlayBytes.length} >>\r\nstream\r\n$overlayBody\r\nendstream',
      ));

      final updatedPage = Map<String, dynamic>.from(pageDict);
      updatedPage['/Contents'] = _RawToken(
          _appendToContentsArr(pageDict['/Contents'], overlayObjId));
      _pendingUpdates.add(IncrementalUpdatePayload(
          pageObjId, 0, _serializeFieldDict(updatedPage)));
    }

    for (final f in targets) {
      deleteField(f);
    }
  }

  final Map<String, PdfIndirectReference> _flattenResourceRefs = {};

  int _fieldPageObjectId(AcroFormField f) {
    final pRef = f.rawDict['/P'];
    if (pRef is PdfIndirectReference) return pRef.objectId;
    for (final id in _engine.globalXrefTable.offsets.keys) {
      final obj = _engine.resolvedObjectsCache[id];
      if (obj is Map<String, dynamic> && obj['/Type']?.toString() == '/Page') {
        final annots = obj['/Annots'];
        if (annots is List &&
            annots.whereType<PdfIndirectReference>().any((r) => r.objectId == f.objectId)) {
          return id;
        }
      }
    }
    return -1;
  }

  PdfIndirectReference? _apStreamRef(AcroFormField f) {
    final ap = f.rawDict['/AP'];
    Map<String, dynamic>? apDict;
    if (ap is Map<String, dynamic>) apDict = ap;
    if (ap is PdfIndirectReference) {
      final r = _engine.resolveIndirectReference(ap);
      if (r is Map<String, dynamic>) apDict = r;
    }
    if (apDict == null) return null;

    final n = apDict['/N'];
    if (n is PdfIndirectReference) return n;
    if (n is Map<String, dynamic>) {
      final as_ = f.rawDict['/AS']?.toString() ?? '/Off';
      final stateRef = n[as_];
      if (stateRef is PdfIndirectReference) return stateRef;
    }
    return null;
  }

  String _pageBBox(Map<String, dynamic> pageDict) {
    final mb = pageDict['/MediaBox'];
    if (mb is List && mb.length == 4) {
      return mb.map((v) => v.toString()).join(' ');
    }
    return '0 0 612 792';
  }

  String _appendToContentsArr(dynamic existing, int newId) {
    final newRef = '$newId 0 R';
    if (existing == null) return '[$newRef]';
    if (existing is PdfIndirectReference) {
      return '[${existing.objectId} ${existing.generation} R $newRef]';
    }
    if (existing is List) {
      final refs = existing.map((e) {
        if (e is PdfIndirectReference) return '${e.objectId} ${e.generation} R';
        return e.toString();
      }).join(' ');
      return '[$refs $newRef]';
    }
    return '[$newRef]';
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _require(AcroFormField f, AcroFieldType t, String method) {
    if (f.type != t) {
      throw ArgumentError('$method requires ${t.name}; '
          '"${f.fullyQualifiedName}" is ${f.type.name}.');
    }
  }

  String _checkboxOnState(Map<String, dynamic> dict) {
    final ap = dict['/AP'];
    if (ap is Map<String, dynamic>) {
      final n = ap['/N'];
      if (n is Map<String, dynamic>) {
        return n.keys.firstWhere((k) => k != '/Off', orElse: () => '/Yes');
      }
    }
    final as_ = dict['/AS'];
    if (as_ is String && as_ != '/Off') return as_;
    return '/Yes';
  }

  static void _resolveEveryObject(PdfDocumentEngine engine) {
    for (final id in engine.globalXrefTable.offsets.keys) {
      try { engine.resolveObjectId(id); } catch (_) {}
    }
    for (final id in engine.globalXrefTable.compressedLocations.keys) {
      try { engine.resolveObjectId(id); } catch (_) {}
    }
  }

  static bool _isXfaDynamic(dynamic xfa) {
    if (xfa is List) {
      for (final item in xfa) {
        final s = item.toString().toLowerCase().replaceAll('/', '');
        if (s == 'config') return true;
      }
    }
    return false;
  }

  static Map<String, dynamic>? _resolveDict(
      dynamic v, PdfDocumentEngine engine) {
    if (v is Map<String, dynamic>) return v;
    if (v is PdfIndirectReference) {
      final r = engine.resolveIndirectReference(v);
      if (r is Map<String, dynamic>) return r;
    }
    return null;
  }

  String _valueStr(dynamic v) {
    if (v == null) return '';
    if (v is PdfRawString) return v.text;
    return v.toString();
  }

  // ─── Field-dict serialization ─────────────────────────────────────────────

  String _serializeFieldDict(Map<String, dynamic> dict) {
    final buf = StringBuffer('<<\r\n');
    dict.forEach((k, v) => buf.write('  $k ${_serializeFieldValue(v)}\r\n'));
    buf.write('>>');
    return buf.toString();
  }

  String _serializeFieldValue(dynamic v) {
    if (v is _RawToken) return v.raw;
    if (v is PdfIndirectReference) return '${v.objectId} ${v.generation} R';
    if (v is PdfRawString) return '(${_pdfEscape(v.text)})';
    if (v is num) return _fmt(v.toDouble());
    if (v is bool) return v.toString();
    if (v is String) {
      if (v.startsWith('/') || v.startsWith('<') || v.startsWith('[')) return v;
      return '($v)';
    }
    if (v is List) return '[${v.map(_serializeFieldValue).join(' ')}]';
    if (v is Map<String, dynamic>) return _serializeFieldDict(v);
    return 'null';
  }

  String _fmt(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(3);

  String _pdfEscape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');

  String _unescapePdfString(String s) => s
      .replaceAll('\\)', ')')
      .replaceAll('\\(', '(')
      .replaceAll('\\\\', '\\');

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _xmlUnescape(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  List<num>? _rectOf(Map<String, dynamic> dict) {
    final r = dict['/Rect'];
    if (r is List && r.length == 4 && r.every((e) => e is num)) {
      return r.cast<num>();
    }
    return null;
  }

  List<double>? _mkColor(dynamic mk, String key) {
    if (mk is! Map<String, dynamic>) return null;
    final c = mk[key];
    if (c is List) return c.map((e) => (e as num).toDouble()).toList();
    return null;
  }

  String _extractFontName(String? da) {
    if (da == null) return '/Helv';
    final match = RegExp(r'(/\w+)\s+[\d.]+\s+Tf').firstMatch(da);
    return match?.group(1) ?? '/Helv';
  }
}

/// Marks a value to be emitted verbatim into a serialized PDF dictionary.
class _RawToken {
  final String raw;
  const _RawToken(this.raw);
}

/// A reusable validation rule for a text field's value.
class FieldValidationRule {
  final String? Function(String value, {required String fieldLabel}) _check;
  const FieldValidationRule._(this._check);

  String? validate(String value, {required String fieldLabel}) =>
      _check(value, fieldLabel: fieldLabel);

  factory FieldValidationRule.numeric() => FieldValidationRule._((v, {required fieldLabel}) {
        if (num.tryParse(v) == null) return '$fieldLabel must be a number.';
        return null;
      });

  factory FieldValidationRule.date() => FieldValidationRule._((v, {required fieldLabel}) {
        final patterns = [
          RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$'),
          RegExp(r'^\d{4}-\d{2}-\d{2}$'),
        ];
        if (!patterns.any((p) => p.hasMatch(v))) {
          return '$fieldLabel must be a valid date.';
        }
        return null;
      });

  factory FieldValidationRule.email() => FieldValidationRule._((v, {required fieldLabel}) {
        final re = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
        if (!re.hasMatch(v)) return '$fieldLabel must be a valid email address.';
        return null;
      });

  factory FieldValidationRule.phone() => FieldValidationRule._((v, {required fieldLabel}) {
        final re = RegExp(r'^[\d\s\+\-\(\)]{7,}$');
        if (!re.hasMatch(v)) return '$fieldLabel must be a valid phone number.';
        return null;
      });

  factory FieldValidationRule.length({int? min, int? max}) =>
      FieldValidationRule._((v, {required fieldLabel}) {
        if (min != null && v.length < min) {
          return '$fieldLabel must be at least $min characters.';
        }
        if (max != null && v.length > max) {
          return '$fieldLabel must be at most $max characters.';
        }
        return null;
      });

  factory FieldValidationRule.pattern(RegExp pattern, {String? message}) =>
      FieldValidationRule._((v, {required fieldLabel}) {
        if (!pattern.hasMatch(v)) {
          return message ?? '$fieldLabel is not in the correct format.';
        }
        return null;
      });

  factory FieldValidationRule.all(List<FieldValidationRule> rules) =>
      FieldValidationRule._((v, {required fieldLabel}) {
        for (final r in rules) {
          final err = r.validate(v, fieldLabel: fieldLabel);
          if (err != null) return err;
        }
        return null;
      });
}