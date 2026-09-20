import 'dart:convert';
import 'dart:typed_data';

import '../pdf_core/document.dart';
import '../pdf_core/incremental_writer.dart';
import '../pdf_core/object_parser.dart';
import '../pdf_core/xref_parser.dart';
import 'appearance.dart';

/// Result of opening a PDF for adding fields.
class PdfFieldAdderResult {
  final PdfFieldAdder? adder;
  final String? failureReason;
  const PdfFieldAdderResult.ok(this.adder) : failureReason = null;
  const PdfFieldAdderResult.unsupported(this.failureReason) : adder = null;
  bool get isSupported => adder != null;
}

/// Adds new AcroForm fields (text, checkbox, radio, dropdown, signature) onto
/// the pages of an EXISTING PDF — unlike [PdfDocumentBuilder], which only
/// creates a brand-new PDF from nothing.
///
/// This is what "Create Form" should call when the user picks an existing
/// PDF and wants to place fields on top of it (the common real-world case:
/// take a scanned/flat contract and turn it into a fillable form).
///
/// Two scenarios handled:
///   1. PDF has NO /AcroForm yet → one is created and added to the catalog.
///   2. PDF already HAS an /AcroForm → new fields are appended to /Fields
///      and to the target page's /Annots, alongside whatever fields already
///      exist. Existing fields and values are left completely untouched.
///
/// Like the rest of the engine, this is purely additive — original page
/// content, images, fonts, bookmarks are never touched. Saved via a single
/// incremental update.
class PdfFieldAdder {
  final Uint8List _originalBytes;
  final PdfDocumentEngine _engine;
  final Map<String, dynamic> _catalog;
  final int _catalogObjectId;

  /// Existing /AcroForm dict + its object ID, if the PDF already has one.
  Map<String, dynamic>? _existingAcroForm;
  int? _existingAcroFormId;

  /// Existing field object IDs already in /AcroForm /Fields (untouched).
  List<int> _existingFieldIds = [];

  final List<IncrementalUpdatePayload> _pendingUpdates = [];
  int _nextObjectId;

  /// Object IDs of fields added in this session (returned after save so the
  /// caller can immediately open the result with PdfFormDocument).
  final List<String> addedFieldNames = [];

  PdfFieldAdder._(
    this._originalBytes,
    this._engine,
    this._catalog,
    this._catalogObjectId,
    this._nextObjectId,
  );

  // ── Opening ──────────────────────────────────────────────────────────────

  static PdfFieldAdderResult open(Uint8List bytes) {
    final PdfDocumentEngine engine;
    try {
      engine = PdfDocumentEngine(bytes);
    } catch (e) {
      return PdfFieldAdderResult.unsupported('Cannot parse PDF: $e');
    }

    if (!engine.hasUsableXref) {
      return const PdfFieldAdderResult.unsupported(
          'Cannot read cross-reference table — file may be corrupted or encrypted.');
    }

    final catalog = engine.catalog;
    if (catalog == null) {
      return const PdfFieldAdderResult.unsupported(
          'Cannot locate document catalog.');
    }

    // Resolve everything so page tree + any existing AcroForm are available
    for (final id in engine.globalXrefTable.offsets.keys) {
      try { engine.resolveObjectId(id); } catch (_) {}
    }
    for (final id in engine.globalXrefTable.compressedLocations.keys) {
      try { engine.resolveObjectId(id); } catch (_) {}
    }

    final catalogId = _findCatalogObjectId(engine, catalog);
    if (catalogId < 0) {
      return const PdfFieldAdderResult.unsupported(
          'Could not locate the catalog object ID.');
    }

    final adder = PdfFieldAdder._(
      bytes, engine, catalog, catalogId, engine.highestObjectId + 1,
    );

    // Pick up any existing /AcroForm so we append rather than replace
    final acroRef = catalog['/AcroForm'];
    if (acroRef is PdfIndirectReference) {
      final resolved = engine.resolveIndirectReference(acroRef);
      if (resolved is Map<String, dynamic>) {
        adder._existingAcroForm = resolved;
        adder._existingAcroFormId = acroRef.objectId;
        final fields = resolved['/Fields'];
        if (fields is List) {
          adder._existingFieldIds = fields
              .whereType<PdfIndirectReference>()
              .map((r) => r.objectId)
              .toList();
        }
      }
    } else if (acroRef is Map<String, dynamic>) {
      // Rare: inline (non-indirect) AcroForm dict — still honour it
      adder._existingAcroForm = acroRef;
      final fields = acroRef['/Fields'];
      if (fields is List) {
        adder._existingFieldIds = fields
            .whereType<PdfIndirectReference>()
            .map((r) => r.objectId)
            .toList();
      }
    }

    return PdfFieldAdderResult.ok(adder);
  }

  int get pageCount => _engine.walkPageTree().length;

  /// MediaBox of the given page, useful for the UI to size its overlay
  /// to the actual PDF page dimensions (in points).
  List<double>? pageSize(int pageIndex) {
    final pages = _engine.walkPageTree();
    if (pageIndex < 0 || pageIndex >= pages.length) return null;
    final mb = pages[pageIndex]['/MediaBox'];
    if (mb is List && mb.length == 4) {
      return mb.map((v) => (v as num).toDouble()).toList();
    }
    return [0, 0, 612, 792]; // US Letter fallback
  }

  // ── Adding fields ─────────────────────────────────────────────────────────

  /// Adds a single-line or multi-line text field to [pageIndex].
  /// [rect] = [llx, lly, urx, ury] in PDF points (origin bottom-left).
  void addTextField({
    required int pageIndex,
    required String name,
    required List<double> rect,
    String defaultValue = '',
    bool multiline = false,
    String? tooltip,
  }) {
    final int fieldId = _nextObjectId++;
    final int pageObjId = _pageObjectId(pageIndex);
    if (pageObjId < 0) return;

    final int ff = multiline ? (1 << 12) : 0;
    final String dv = defaultValue.isNotEmpty
        ? '/V (${_esc(defaultValue)}) /DV (${_esc(defaultValue)})'
        : '';
    final String tip =
        tooltip != null ? '/TU (${_esc(tooltip)})' : '';

    _pendingUpdates.add(IncrementalUpdatePayload(fieldId, 0, '''<<
  /Type /Annot /Subtype /Widget /FT /Tx
  /T (${_esc(name)}) $tip
  /Rect [${_rect(rect)}]
  /P $pageObjId 0 R
  /F 4
  /DA (/Helv ${defaultValue.isEmpty ? 0 : 10} Tf 0 g)
  /Ff $ff $dv
  /MK << /BC [0 0 0] /BG [1 1 1] >>
  /BS << /W 0.5 /S /S >>
>>'''));

    _registerNewField(fieldId, pageObjId);
    addedFieldNames.add(name);
  }

  /// Adds a checkbox to [pageIndex].
  void addCheckbox({
    required int pageIndex,
    required String name,
    required List<double> rect,
    bool checked = false,
    String? tooltip,
  }) {
    final int fieldId = _nextObjectId++;
    final int pageObjId = _pageObjectId(pageIndex);
    if (pageObjId < 0) return;

    final double w = (rect[2] - rect[0]).abs();
    final double h = (rect[3] - rect[1]).abs();
    final String state = checked ? '/Yes' : '/Off';
    final String tip = tooltip != null ? '/TU (${_esc(tooltip)})' : '';

    final int onApId = _nextObjectId++;
    final int offApId = _nextObjectId++;
    final gen = PdfAppearanceGenerator();

    final String onContent = _asXObjectBody(
        gen.generateCheckboxAppearance(isChecked: true, size: w), w, h);
    final String offContent = _asXObjectBody(
        gen.generateCheckboxAppearance(isChecked: false, size: w), w, h);

    _pendingUpdates.add(IncrementalUpdatePayload(onApId, 0, onContent));
    _pendingUpdates.add(IncrementalUpdatePayload(offApId, 0, offContent));

    _pendingUpdates.add(IncrementalUpdatePayload(fieldId, 0, '''<<
  /Type /Annot /Subtype /Widget /FT /Btn
  /T (${_esc(name)}) $tip
  /Rect [${_rect(rect)}]
  /P $pageObjId 0 R
  /F 4
  /V $state /AS $state
  /AP << /N << /Yes $onApId 0 R /Off $offApId 0 R >> >>
  /MK << /BC [0 0 0] /BG [1 1 1] >>
>>'''));

    _registerNewField(fieldId, pageObjId);
    addedFieldNames.add(name);
  }

  /// Adds a radio button group. Each option is its own widget annotation
  /// on the page; they all share [groupName] as the parent field.
  void addRadioGroup({
    required int pageIndex,
    required String groupName,
    required List<Map<String, dynamic>> options, // {exportValue, rect}
    String? selectedValue,
    String? tooltip,
  }) {
    final int pageObjId = _pageObjectId(pageIndex);
    if (pageObjId < 0) return;

    final int parentId = _nextObjectId++;
    final List<int> kidIds = [];
    final gen = PdfAppearanceGenerator();
    final String tip = tooltip != null ? '/TU (${_esc(tooltip)})' : '';

    for (final opt in options) {
      final String exportVal = opt['exportValue'] as String? ?? '/Yes';
      final List<double> rect = (opt['rect'] as List).cast<double>();
      final bool selected = exportVal == selectedValue;
      final double w = (rect[2] - rect[0]).abs();
      final double h = (rect[3] - rect[1]).abs();

      final int onApId = _nextObjectId++;
      final int offApId = _nextObjectId++;
      _pendingUpdates.add(IncrementalUpdatePayload(onApId, 0,
          _asXObjectBody(gen.generateRadioButtonAppearance(isSelected: true, size: w), w, h)));
      _pendingUpdates.add(IncrementalUpdatePayload(offApId, 0,
          _asXObjectBody(gen.generateRadioButtonAppearance(isSelected: false, size: w), w, h)));

      final int kidId = _nextObjectId++;
      _pendingUpdates.add(IncrementalUpdatePayload(kidId, 0, '''<<
  /Type /Annot /Subtype /Widget
  /Parent $parentId 0 R
  /Rect [${_rect(rect)}]
  /P $pageObjId 0 R
  /F 4
  /AS ${selected ? exportVal : '/Off'}
  /AP << /N << $exportVal $onApId 0 R /Off $offApId 0 R >> >>
>>'''));
      kidIds.add(kidId);
      _registerNewField(kidId, pageObjId, addToAcroFormFields: false);
    }

    final String kidsArr = kidIds.map((k) => '$k 0 R').join(' ');
    _pendingUpdates.add(IncrementalUpdatePayload(parentId, 0, '''<<
  /FT /Btn /T (${_esc(groupName)}) $tip
  /Ff 32768 /V ${selectedValue ?? '/Off'}
  /Kids [$kidsArr]
>>'''));

    _registerNewField(parentId, pageObjId, addToPageAnnots: false);
    addedFieldNames.add(groupName);
  }

  /// Adds a dropdown / listbox.
  void addDropdown({
    required int pageIndex,
    required String name,
    required List<double> rect,
    required List<dynamic> options,
    String? selectedValue,
    String? tooltip,
  }) {
    final int fieldId = _nextObjectId++;
    final int pageObjId = _pageObjectId(pageIndex);
    if (pageObjId < 0) return;

    final String optsStr = options.map((o) {
      if (o is List && o.length >= 2) {
        return '[(${_esc(o[0].toString())}) (${_esc(o[1].toString())})]';
      }
      return '(${_esc(o.toString())})';
    }).join(' ');
    final String valStr =
        selectedValue != null ? '/V (${_esc(selectedValue)})' : '';
    final String tip = tooltip != null ? '/TU (${_esc(tooltip)})' : '';

    _pendingUpdates.add(IncrementalUpdatePayload(fieldId, 0, '''<<
  /Type /Annot /Subtype /Widget /FT /Ch
  /T (${_esc(name)}) $tip
  /Rect [${_rect(rect)}]
  /P $pageObjId 0 R
  /F 4 /Ff 131072
  /Opt [$optsStr] $valStr
  /DA (/Helv 10 Tf 0 g)
  /MK << /BC [0 0 0] /BG [1 1 1] >>
  /BS << /W 0.5 /S /S >>
>>'''));

    _registerNewField(fieldId, pageObjId);
    addedFieldNames.add(name);
  }

  /// Adds a signature field placeholder.
  void addSignatureField({
    required int pageIndex,
    required String name,
    required List<double> rect,
    String? tooltip,
  }) {
    final int fieldId = _nextObjectId++;
    final int pageObjId = _pageObjectId(pageIndex);
    if (pageObjId < 0) return;
    final String tip = tooltip != null ? '/TU (${_esc(tooltip)})' : '';

    _pendingUpdates.add(IncrementalUpdatePayload(fieldId, 0, '''<<
  /Type /Annot /Subtype /Widget /FT /Sig
  /T (${_esc(name)}) $tip
  /Rect [${_rect(rect)}]
  /P $pageObjId 0 R
  /F 4
  /MK << /BC [0.2 0.4 0.8] /BG [0.94 0.97 1] >>
  /BS << /W 0.5 /S /S >>
>>'''));

    _registerNewField(fieldId, pageObjId);
    addedFieldNames.add(name);
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  bool get hasPendingChanges => _pendingUpdates.isNotEmpty;

  /// Builds the final PDF bytes. Creates a new /AcroForm if none existed,
  /// or extends the existing one. Updates each target page's /Annots.
  /// Always returns a PDF immediately fillable by PdfFormDocument.open().
  Uint8List save() {
    if (_pendingUpdates.isEmpty) return _originalBytes;

    _finalizeAcroForm();
    _finalizePageAnnots();

    final xrefOffset = PdfXrefParser(_originalBytes).findLastStartXref();
    return PdfIncrementalWriter.appendUpdates(
      _originalBytes,
      _pendingUpdates,
      xrefOffset,
      _nextObjectId - 1,
    );
  }

  // ── Internal bookkeeping ──────────────────────────────────────────────────

  final Map<int, List<int>> _pageAnnotsToAdd = {}; // pageObjId -> [fieldIds]
  final List<int> _acroFormFieldsToAdd = [];

  void _registerNewField(
    int fieldId,
    int pageObjId, {
    bool addToAcroFormFields = true,
    bool addToPageAnnots = true,
  }) {
    if (addToAcroFormFields) _acroFormFieldsToAdd.add(fieldId);
    if (addToPageAnnots) {
      _pageAnnotsToAdd.putIfAbsent(pageObjId, () => []).add(fieldId);
    }
  }

  /// Writes (or extends) the /AcroForm dict and updates the catalog if a
void _finalizeAcroForm() {
  if (_existingAcroForm != null && _existingAcroFormId != null) {
    // Extend existing AcroForm: preserve all existing keys,
    // only update /Fields and add /NeedAppearances.
    final allFieldIds = [..._existingFieldIds, ..._acroFormFieldsToAdd];
    final fieldsArr = allFieldIds.map((id) => '$id 0 R').join(' ');

    // Start with the original dict, but we must not lose /DR, /XFA, etc.
    final merged = Map<String, dynamic>.from(_existingAcroForm!);
    // Ensure /Fields is the updated array
    merged['/Fields'] = _RawRef('[$fieldsArr]');
    // Ensure /NeedAppearances is true so viewers generate appearances if missing
    merged['/NeedAppearances'] = true;
    // Keep the original /DA if present, else set a default
    if (!merged.containsKey('/DA')) {
      merged['/DA'] = '/Helv 10 Tf 0 g';
    }

    _pendingUpdates.add(IncrementalUpdatePayload(
      _existingAcroFormId!,
      0,
      _serializeDict(merged),
    ));
    // Catalog already points to this AcroForm – no change needed.
  } else {
    // No AcroForm existed – create one and patch the catalog.
    final acroFormId = _nextObjectId++;
    final fieldsArr =
        _acroFormFieldsToAdd.map((id) => '$id 0 R').join(' ');
    _pendingUpdates.add(IncrementalUpdatePayload(
      acroFormId,
      0,
      '<< /Fields [$fieldsArr] /DA (/Helv 10 Tf 0 g) /NeedAppearances true >>',
    ));

    final updatedCatalog = Map<String, dynamic>.from(_catalog);
    updatedCatalog['/AcroForm'] = _RawRef('$acroFormId 0 R');
    _pendingUpdates.add(IncrementalUpdatePayload(
      _catalogObjectId,
      0,
      _serializeDict(updatedCatalog),
    ));
  }
}

  /// Updates each touched page's /Annots array to include the new field IDs,
  /// preserving every existing annotation already on that page.
  void _finalizePageAnnots() {
    // Scan BOTH regular offsets AND compressed object streams (ObjStm).
    // For PDFs from the Flutter pdf package, Acrobat, Word, or Chrome print-
    // to-PDF, page objects live in compressed ObjStm streams and their IDs
    // appear in compressedLocations, NOT in offsets. Scanning only offsets.keys
    // meant _finalizePageAnnots found zero pages and wrote nothing — so field
    // widgets were created but never linked to any page's /Annots, making them
    // invisible to every PDF viewer (which shows widget annotations, not the
    // logical AcroForm field dict).
    final allIds = {
      ..._engine.globalXrefTable.offsets.keys,
      ..._engine.globalXrefTable.compressedLocations.keys,
    };
    final pageObjIds = <int>[];
    for (final id in allIds) {
      final obj = _engine.resolvedObjectsCache[id];
      if (obj is Map<String, dynamic> && obj['/Type']?.toString() == '/Page') {
        pageObjIds.add(id);
      }
    }
    pageObjIds.sort();

    for (final entry in _pageAnnotsToAdd.entries) {
      final int pageObjId = entry.key;
      final List<int> newIds = entry.value;

      // Find the page dict matching this object ID
      final dict = _engine.resolvedObjectsCache[pageObjId];
      if (dict is! Map<String, dynamic>) continue;

      final updated = Map<String, dynamic>.from(dict);
      final String newAnnotsArr = _appendToAnnots(dict['/Annots'], newIds);
      updated['/Annots'] = _RawRef(newAnnotsArr);

      _pendingUpdates.add(IncrementalUpdatePayload(
        pageObjId, 0, _serializeDict(updated),
      ));
    }
  }

  String _appendToAnnots(dynamic existing, List<int> newIds) {
    final newRefs = newIds.map((id) => '$id 0 R').join(' ');
    if (existing == null) return '[$newRefs]';
    if (existing is List) {
      final existingRefs = existing.map((e) {
        if (e is PdfIndirectReference) return '${e.objectId} ${e.generation} R';
        return e.toString();
      }).join(' ');
      return '[$existingRefs $newRefs]';
    }
    if (existing is PdfIndirectReference) {
      // /Annots itself is an indirect reference to an array object — rare,
      // but handle by wrapping both as a fresh inline array referencing it.
      return '[${existing.objectId} ${existing.generation} R $newRefs]';
    }
    return '[$newRefs]';
  }

  // ── Page / object helpers ─────────────────────────────────────────────────

  int _pageObjectId(int pageIndex) {
    final allIds = {
      ..._engine.globalXrefTable.offsets.keys,
      ..._engine.globalXrefTable.compressedLocations.keys,
    };
    final pageObjIds = <int>[];
    for (final id in allIds) {
      final obj = _engine.resolvedObjectsCache[id];
      if (obj is Map<String, dynamic> && obj['/Type']?.toString() == '/Page') {
        pageObjIds.add(id);
      }
    }
    pageObjIds.sort();
    if (pageIndex < 0 || pageIndex >= pageObjIds.length) return -1;
    return pageObjIds[pageIndex];
  }

  static int _findCatalogObjectId(
      PdfDocumentEngine engine, Map<String, dynamic> catalog) {
    final rootRef = engine.globalXrefTable.trailerDict['/Root'];
    if (rootRef is PdfIndirectReference) return rootRef.objectId;
    // Fallback: scan resolved objects for the matching /Type /Catalog dict
    final allIds = {
      ...engine.globalXrefTable.offsets.keys,
      ...engine.globalXrefTable.compressedLocations.keys,
    };
    for (final id in allIds) {
      final obj = engine.resolvedObjectsCache[id];
      if (obj is Map<String, dynamic> &&
          obj['/Type']?.toString() == '/Catalog') {
        return id;
      }
    }
    return -1;
  }

  String _asXObjectBody(String rawChunk, double w, double h) {
    final extra = '/Type /XObject /Subtype /Form /BBox [0 0 ${_f(w)} ${_f(h)}] ';
    return rawChunk.replaceFirst('<<', '<< $extra');
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  String _serializeDict(Map<String, dynamic> dict) {
    final buf = StringBuffer('<<\r\n');
    dict.forEach((k, v) => buf.write('  $k ${_sv(v)}\r\n'));
    buf.write('>>');
    return buf.toString();
  }

  String _sv(dynamic v) {
    if (v is _RawRef) return v.raw;
    if (v is PdfIndirectReference) return '${v.objectId} ${v.generation} R';
    if (v is num) return _f(v.toDouble());
    if (v is bool) return v.toString();
    if (v is String) {
      if (v.startsWith('/') || v.startsWith('<') || v.startsWith('[')) return v;
      return '($v)';
    }
    if (v is List) return '[${v.map(_sv).join(' ')}]';
    if (v is Map<String, dynamic>) return _serializeDict(v);
    return 'null';
  }

  String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');

  String _rect(List<double> r) => r.map(_f).join(' ');
  String _f(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(3);
}

class _RawRef {
  final String raw;
  const _RawRef(this.raw);
}
