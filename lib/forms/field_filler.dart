import 'dart:convert';
import '../pdf_core/incremental_writer.dart';
import '../pdf_core/object_parser.dart';
import '../pdf_core/lexer.dart' show PdfRawString;
import 'appearance.dart';

/// Marks a value to emit verbatim into a PDF dictionary (no re-quoting).
class PdfRawToken {
  final String raw;
  const PdfRawToken(this.raw);
}

class PdfFieldFiller {

  // ── Text fields (/Tx) ──────────────────────────────────────────────────────

  List<IncrementalUpdatePayload> fillTextField({
    required int fieldObjectId,
    required Map<String, dynamic> originalFieldDict,
    required int newAppearanceObjectId,
    required String textValue,
    String fontResourceName = '/Helv',
    double fontSize = 0,
  }) {
    final rect   = _rectOf(originalFieldDict);
    final width  = rect != null ? (rect[2] - rect[0]).abs().toDouble() : 100.0;
    final height = rect != null ? (rect[3] - rect[1]).abs().toDouble() : 20.0;

    final apContent = PdfAppearanceGenerator().generateTextAppearance(
      text: textValue,
      width: width,
      height: height,
      fontName: fontResourceName,
      fontSize: fontSize,
      alignment: _textAlignment(originalFieldDict),
    );

    final apBody = _buildFormXObject(apContent, width, height, fontResourceName);
    final sanitized = _escape(textValue);

    final merged = Map<String, dynamic>.from(originalFieldDict);
    merged['/FT'] = '/Tx';
    merged['/V']  = PdfRawToken('($sanitized)');
    merged['/AP'] = PdfRawToken('<< /N $newAppearanceObjectId 0 R >>');

    return [
      IncrementalUpdatePayload(fieldObjectId, 0, _serializeDict(merged)),
      IncrementalUpdatePayload(newAppearanceObjectId, 0, apBody),
    ];
  }

  // ── Checkboxes (/Btn) ──────────────────────────────────────────────────────

  List<IncrementalUpdatePayload> fillCheckboxField({
    required int fieldObjectId,
    required Map<String, dynamic> originalFieldDict,
    required int yesAppearanceObjectId,
    required int offAppearanceObjectId,
    required bool isChecked,
    double size = 12.0,
    // Real-world PDFs from Adobe use /On, /1, or custom values.
    // Pass the detected state name from PdfFormDocument._checkboxOnState.
    String? customOnStateName,
  }) {
    final String onState = customOnStateName ?? '/Yes';

    final rect = _rectOf(originalFieldDict);
    final double s = rect != null
        ? ((rect[2] - rect[0]).abs()).clamp(6.0, 24.0).toDouble()
        : size;

    final gen = PdfAppearanceGenerator();
    final yesBody = _asFormXObject(
        gen.generateCheckboxAppearance(isChecked: true,  size: s), s, s);
    final offBody = _asFormXObject(
        gen.generateCheckboxAppearance(isChecked: false, size: s), s, s);

    final merged = Map<String, dynamic>.from(originalFieldDict);
    merged['/FT'] = '/Btn';
    merged['/V']  = PdfRawToken(isChecked ? onState : '/Off');
    merged['/AS'] = PdfRawToken(isChecked ? onState : '/Off');
    merged['/AP'] = PdfRawToken(
      '<< /N << $onState $yesAppearanceObjectId 0 R /Off $offAppearanceObjectId 0 R >> >>',
    );

    return [
      IncrementalUpdatePayload(fieldObjectId, 0, _serializeDict(merged)),
      IncrementalUpdatePayload(yesAppearanceObjectId, 0, yesBody),
      IncrementalUpdatePayload(offAppearanceObjectId, 0, offBody),
    ];
  }

  // ── Radio button groups ────────────────────────────────────────────────────

  List<IncrementalUpdatePayload> fillRadioGroup({
    required int parentObjectId,
    required Map<String, dynamic> parentFieldDict,
    required List<Map<String, dynamic>> kids,
    required List<int> kidObjectIds,
    required List<List<int>> apObjectIds,   // [[onId, offId], ...]
    required String selectedStateName,      // '/Yes' | '/Option1' | etc.
  }) {
    final payloads = <IncrementalUpdatePayload>[];

    // Parent gets /V = the selected export value
    final parentDict = Map<String, dynamic>.from(parentFieldDict);
    parentDict['/V'] = PdfRawToken(selectedStateName);
    payloads.add(IncrementalUpdatePayload(
        parentObjectId, 0, _serializeDict(parentDict)));

    for (int i = 0; i < kids.length; i++) {
      final kid      = Map<String, dynamic>.from(kids[i]);
      final onState  = _kidOnStateName(kid) ?? selectedStateName;
      final selected = onState == selectedStateName;

      final int onId  = apObjectIds[i][0];
      final int offId = apObjectIds[i][1];

      final rect = _rectOf(kid);
      final double s = rect != null
          ? ((rect[2] - rect[0]).abs()).clamp(6.0, 24.0).toDouble()
          : 12.0;

      final gen = PdfAppearanceGenerator();
      final onBody  = _asFormXObject(
          gen.generateRadioButtonAppearance(isSelected: true,  size: s), s, s);
      final offBody = _asFormXObject(
          gen.generateRadioButtonAppearance(isSelected: false, size: s), s, s);

      kid['/AS'] = PdfRawToken(selected ? onState : '/Off');
      kid['/AP'] = PdfRawToken(
        '<< /N << $onState $onId 0 R /Off $offId 0 R >> >>',
      );

      payloads.add(IncrementalUpdatePayload(kidObjectIds[i], 0, _serializeDict(kid)));
      payloads.add(IncrementalUpdatePayload(onId,  0, onBody));
      payloads.add(IncrementalUpdatePayload(offId, 0, offBody));
    }

    return payloads;
  }

  // ── Choice fields (/Ch) ────────────────────────────────────────────────────

  List<IncrementalUpdatePayload> fillChoiceField({
    required int fieldObjectId,
    required Map<String, dynamic> originalFieldDict,
    required int newAppearanceObjectId,
    required String selectedValue,
  }) {
    final rect   = _rectOf(originalFieldDict);
    final width  = rect != null ? (rect[2] - rect[0]).abs().toDouble() : 120.0;
    final height = rect != null ? (rect[3] - rect[1]).abs().toDouble() : 16.0;

    final apContent = PdfAppearanceGenerator().generateTextAppearance(
      text: selectedValue,
      width: width,
      height: height,
    );
    final apBody = _buildFormXObject(apContent, width, height, '/Helv');

    final merged = Map<String, dynamic>.from(originalFieldDict);
    merged['/FT'] = '/Ch';
    merged['/V']  = PdfRawToken('(${_escape(selectedValue)})');
    merged.remove('/I');   // viewer will re-derive index
    merged['/AP'] = PdfRawToken('<< /N $newAppearanceObjectId 0 R >>');

    return [
      IncrementalUpdatePayload(fieldObjectId, 0, _serializeDict(merged)),
      IncrementalUpdatePayload(newAppearanceObjectId, 0, apBody),
    ];
  }

  // ── Signature fields (/Sig) — visual only ─────────────────────────────────

  List<IncrementalUpdatePayload> fillSignatureFieldVisual({
    required int fieldObjectId,
    required Map<String, dynamic> originalFieldDict,
    required int newAppearanceObjectId,
    required String signatureText,
    String mode = 'text',
  }) {
    final rect   = _rectOf(originalFieldDict);
    final width  = rect != null ? (rect[2] - rect[0]).abs().toDouble() : 150.0;
    final height = rect != null ? (rect[3] - rect[1]).abs().toDouble() : 40.0;

    final apContent = PdfAppearanceGenerator().generateSignatureAppearance(
      width: width,
      height: height,
      mode: mode,
      label: signatureText,
    );
    final apBody = _buildFormXObject(apContent, width, height, '/Helv');

    final merged = Map<String, dynamic>.from(originalFieldDict);
    merged['/V']  = PdfRawToken('(${_escape(signatureText)})');
    merged['/AP'] = PdfRawToken('<< /N $newAppearanceObjectId 0 R >>');

    return [
      IncrementalUpdatePayload(fieldObjectId, 0, _serializeDict(merged)),
      IncrementalUpdatePayload(newAppearanceObjectId, 0, apBody),
    ];
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _escape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');

  String _f(num n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();

  List<num>? _rectOf(Map<String, dynamic> dict) {
    final r = dict['/Rect'];
    if (r is List && r.length == 4 && r.every((e) => e is num)) {
      return r.cast<num>();
    }
    return null;
  }

  String _textAlignment(Map<String, dynamic> dict) {
    final q = dict['/Q'];
    if (q is num) {
      switch (q.toInt()) {
        case 1: return 'center';
        case 2: return 'right';
      }
    }
    return 'left';
  }

  String? _kidOnStateName(Map<String, dynamic> kid) {
    final ap = kid['/AP'];
    if (ap is Map<String, dynamic>) {
      final n = ap['/N'];
      if (n is Map<String, dynamic>) {
        return n.keys.firstWhere((k) => k != '/Off', orElse: () => '/Yes');
      }
    }
    return null;
  }

  /// Wraps an appearance-stream chunk from PdfAppearanceGenerator into a
  /// proper Form XObject with /Type /Subtype /BBox.
  String _asFormXObject(String rawChunk, double w, double h) {
    final extra = '/Type /XObject /Subtype /Form /BBox [0 0 ${_f(w)} ${_f(h)}] ';
    return rawChunk.replaceFirst('<<', '<< $extra');
  }

  /// Builds a complete Form XObject from an appearance content string,
  /// including a /Resources /Font entry for Helvetica.
  String _buildFormXObject(String apContent, double w, double h, String fontName) {
    // apContent from generateTextAppearance / generateSignatureAppearance
    // is already wrapped as "<< /Length N >>\r\nstream\r\n...\r\nendstream"
    // Strip the inner dict, rebuild with XObject keys + font resources.
    final streamStart = apContent.indexOf('stream\r\n');
    final String body;
    final int bodyLen;

    if (streamStart >= 0) {
      final inner = apContent.substring(
          streamStart + 8, apContent.lastIndexOf('\r\nendstream'));
      bodyLen = utf8.encode(inner).length;
      body = inner;
    } else {
      body = apContent;
      bodyLen = utf8.encode(body).length;
    }

    return '<< /Type /XObject /Subtype /Form '
        '/BBox [0 0 ${_f(w)} ${_f(h)}] '
        '/Resources << /Font << $fontName << /Type /Font /Subtype /Type1 '
        '/BaseFont /Helvetica >> >> >> '
        '/Length $bodyLen >>\r\nstream\r\n$body\r\nendstream';
  }

  String _serializeDict(Map<String, dynamic> dict) {
    final buf = StringBuffer('<<\r\n');
    dict.forEach((key, value) {
      buf.write('  $key ${_serializeValue(value)}\r\n');
    });
    buf.write('>>');
    return buf.toString();
  }

  String _serializeValue(dynamic value) {
    if (value is PdfRawToken)         return value.raw;
    if (value is PdfIndirectReference) return '${value.objectId} ${value.generation} R';
    if (value is PdfRawString)        return '(${_escape(value.text)})';
    if (value is num)                 return _f(value);
    if (value is bool)                return value.toString();
    if (value is String) {
      if (value.startsWith('/') || value.startsWith('<')) return value;
      return '(${_escape(value)})';
    }
    if (value is List)                return '[${value.map(_serializeValue).join(' ')}]';
    if (value is Map<String, dynamic>) return _serializeDict(value);
    return 'null';
  }
}
