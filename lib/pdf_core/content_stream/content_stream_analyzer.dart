import 'dart:math';
import 'dart:typed_data';
import 'cs_lexer.dart';
import 'text_state.dart';
import 'font_info.dart';

class KernPair {
  final int charIndex;
  final double adjustment;
  const KernPair(this.charIndex, this.adjustment);
}

class TextRun {
  final int id;
  final int byteStart;
  final int byteEnd;
  final String text;
  final double x, y, width, height;
  final double baselineX, baselineY;
  final double endX;
  final String fontRef;
  final double fontSize;
  final double widthEm;
  final double originalHz;
  final double charSpacing;
  final double wordSpacing;
  final List<KernPair>? kerning;
  final List<TextRun>? constituents;

  const TextRun({
    required this.id,
    required this.byteStart,
    required this.byteEnd,
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.baselineX,
    required this.baselineY,
    required this.endX,
    required this.fontRef,
    required this.fontSize,
    required this.widthEm,
    required this.originalHz,
    required this.charSpacing,
    required this.wordSpacing,
    this.kerning,
    this.constituents,
  });
}

/// A Form XObject that can be invoked from a content stream via `Do`.
/// Its content stream is analyzed recursively, with its own font table and
/// its own nested forms.
class FormXObject {
  final Uint8List contentBytes;
  final Map<String, FontInfo> fonts;
  final Map<String, FormXObject> forms;

  /// Six-element affine matrix [a, b, c, d, e, f]. Applied to the CTM when
  /// the form is invoked, before its content stream runs. Default identity
  /// if the form declared no `/Matrix`.
  final List<double> matrix;

  const FormXObject({
    required this.contentBytes,
    required this.fonts,
    required this.forms,
    required this.matrix,
  });
}

class ContentStreamAnalyzer {
  final Uint8List _bytes;
  final Map<String, FontInfo> _fonts;
  final Map<String, FormXObject> _forms;

  ContentStreamAnalyzer(
    this._bytes,
    this._fonts, {
    Map<String, FormXObject>? forms,
  }) : _forms = forms ?? const {};

  /// Raw per-operator runs (no merging).
  List<TextRun> analyze() {
    final runs = <TextRun>[];
    final state = PdfTextState();
    _analyzeInto(runs, state);
    return runs;
  }

  /// Runs merged into visual lines (same baseline, same font).
  List<TextRun> analyzeLines() => _mergeRuns(analyze());

  void _analyzeInto(List<TextRun> runs, PdfTextState state) {
    final lexer = ContentStreamLexer(_bytes);
    final operands = <dynamic>[];
    final operandStarts = <int>[];

    while (true) {
      final start = lexer.offset;
      final tok = lexer.nextToken();
      if (tok == null) break;

      if (tok.type != ContentStreamTokenType.operator) {
        operands.add(tok.value);
        operandStarts.add(start);
        continue;
      }

      final op = tok.value as String;
      switch (op) {
        case 'q':
          state.saveGraphicsState();
          break;
        case 'Q':
          state.restoreGraphicsState();
          break;
        case 'cm':
          if (operands.length >= 6) {
            state.concatCtm(
                _d(operands[0]),
                _d(operands[1]),
                _d(operands[2]),
                _d(operands[3]),
                _d(operands[4]),
                _d(operands[5]));
          }
          break;
        case 'BT':
          state.beginTextBlock();
          break;
        case 'ET':
          break;
        case 'Tc':
          if (operands.isNotEmpty) state.charSpacing = _d(operands.last);
          break;
        case 'Tw':
          if (operands.isNotEmpty) state.wordSpacing = _d(operands.last);
          break;
        case 'Tz':
          if (operands.isNotEmpty) state.horizontalScaling = _d(operands.last);
          break;
        case 'TL':
          if (operands.isNotEmpty) state.leading = _d(operands.last);
          break;
        case 'Ts':
          if (operands.isNotEmpty) state.textRise = _d(operands.last);
          break;
        case 'Tf':
          if (operands.length >= 2) {
            state.fontRef = '/' + operands[operands.length - 2].toString();
            state.fontSize = _d(operands.last);
          }
          break;
        case 'Tm':
          if (operands.length >= 6) {
            state.setTextMatrix(_d(operands[0]), _d(operands[1]),
                _d(operands[2]), _d(operands[3]), _d(operands[4]), _d(operands[5]));
          }
          break;
        case 'Td':
          if (operands.length >= 2) {
            state.moveTextLine(_d(operands[0]), _d(operands[1]));
          }
          break;
        case 'TD':
          if (operands.length >= 2) {
            state.leading = -_d(operands[1]);
            state.moveTextLine(_d(operands[0]), _d(operands[1]));
          }
          break;
        case 'T*':
          state.nextLine();
          break;
        case 'Tj':
          if (operands.isNotEmpty) {
            final last = operands.last;
            final bStart = operandStarts.isNotEmpty ? operandStarts.last : start;
            if (last is List<int>) {
              _emitRun(runs, last, state, bStart, lexer.offset, null);
            } else if (last is String) {
              final bytes = _hexToBytes(last);
              if (bytes != null) {
                _emitRun(runs, bytes, state, bStart, lexer.offset, null);
              }
            }
          }
          break;
        case 'TJ':
          if (operands.isNotEmpty && operands.last is List<dynamic>) {
            final bStart =
                operandStarts.isNotEmpty ? operandStarts.last : start;
            _emitTJRun(runs, operands.last as List<dynamic>, state, bStart,
                lexer.offset);
          }
          break;
        case 'Do':
          // Form XObject invocation. Recurse into the form's content stream
          // with the form's own fonts and forms. This is how headers,
          // footers, watermarks, and much of what Word / InDesign / Figma /
          // Canva emit actually renders — the text lives in the form, not
          // in the page's own content stream.
          if (operands.isNotEmpty) {
            final name = '/' + operands.last.toString();
            final form = _forms[name];
            if (form != null) {
              _recurseIntoForm(form, runs, state);
            }
          }
          break;
      }
      operands.clear();
      operandStarts.clear();
    }
  }

  /// Enter a Form XObject: apply its `/Matrix` to the CTM, swap in its font
  /// table and nested forms, run its content stream, then restore the outer
  /// graphics state. Also restores the font reference explicitly, since the
  /// form's own `Tf` operators would otherwise leave it pointing at a name
  /// the caller's font table doesn't know about.
  void _recurseIntoForm(
      FormXObject form, List<TextRun> runs, PdfTextState state) {
    final savedFontRef = state.fontRef;
    final savedFontSize = state.fontSize;

    state.saveGraphicsState();
    if (form.matrix.length >= 6) {
      state.concatCtm(
        form.matrix[0],
        form.matrix[1],
        form.matrix[2],
        form.matrix[3],
        form.matrix[4],
        form.matrix[5],
      );
    }

    try {
      final sub = ContentStreamAnalyzer(
        form.contentBytes,
        form.fonts,
        forms: form.forms,
      );
      sub._analyzeInto(runs, state);
    } finally {
      state.restoreGraphicsState();
      state.fontRef = savedFontRef;
      state.fontSize = savedFontSize;
    }
  }

  void _emitRun(List<TextRun> runs, List<int> bytes, PdfTextState state,
      int byteStart, int byteEnd, List<KernPair>? kerning) {
    final info = _fonts[state.fontRef];
    final text = info?.decode(bytes) ?? String.fromCharCodes(bytes);
    final widthEm = info?.widthEm(bytes) ?? (bytes.length * 0.6);
    _record(runs, text, widthEm, state, byteStart, byteEnd, kerning);
  }

  void _emitTJRun(List<TextRun> runs, List<dynamic> arr, PdfTextState state,
      int byteStart, int byteEnd) {
    final info = _fonts[state.fontRef];
    final textBuffer = StringBuffer();
    final allBytes = <int>[];
    final kerning = <KernPair>[];
    int decodedLen = 0;

    for (final el in arr) {
      if (el is List<int>) {
        allBytes.addAll(el);
        final s = info?.decode(el) ?? String.fromCharCodes(el);
        textBuffer.write(s);
        decodedLen += s.length;
      } else if (el is num) {
        kerning.add(KernPair(decodedLen, el.toDouble()));
      }
    }
    final text = textBuffer.toString();
    if (text.isEmpty) return;

    final widthEm = info?.widthEm(allBytes) ?? (allBytes.length * 0.6);
    _record(runs, text, widthEm, state, byteStart, byteEnd,
        kerning.isEmpty ? null : kerning);
    state.advanceBy(widthEm);
  }

  void _record(List<TextRun> runs, String text, double widthEm,
      PdfTextState state, int byteStart, int byteEnd, List<KernPair>? kerning) {
    final trm = state.textRenderingMatrix;
    final origin = trm.transformPoint(0, 0);
    final end = trm.transformPoint(widthEm, 0);
    final asc = trm.transformPoint(0, 0.75);
    final desc = trm.transformPoint(0, -0.2);

    final left = min(min(origin.x, end.x), min(asc.x, desc.x));
    final right = max(max(origin.x, end.x), max(asc.x, desc.x));
    final bottom = min(min(origin.y, end.y), min(asc.y, desc.y));
    final top = max(max(origin.y, end.y), max(asc.y, desc.y));

    runs.add(TextRun(
      id: runs.length,
      byteStart: byteStart,
      byteEnd: byteEnd,
      text: text,
      x: left,
      y: bottom,
      width: right - left,
      height: top - bottom,
      baselineX: origin.x,
      baselineY: origin.y,
      endX: end.x,
      fontRef: state.fontRef,
      fontSize: state.fontSize,
      widthEm: widthEm,
      originalHz: state.horizontalScaling,
      charSpacing: state.charSpacing,
      wordSpacing: state.wordSpacing,
      kerning: kerning,
    ));
    state.advanceBy(widthEm);
  }

  List<TextRun> _mergeRuns(List<TextRun> runs) {
    if (runs.length < 2) return runs;
    final out = <TextRun>[];
    var current = runs[0];
    for (int i = 1; i < runs.length; i++) {
      final next = runs[i];
      if (_canMerge(current, next)) {
        current = _merge(current, next);
      } else {
        out.add(current);
        current = next;
      }
    }
    out.add(current);
    return out;
  }

  bool _canMerge(TextRun a, TextRun b) {
    if (a.fontRef != b.fontRef) return false;
    if ((a.fontSize - b.fontSize).abs() > 0.1) return false;
    if ((a.originalHz - b.originalHz).abs() > 0.5) return false;
    if ((a.charSpacing - b.charSpacing).abs() > 0.01) return false;
    if ((a.wordSpacing - b.wordSpacing).abs() > 0.01) return false;
    if ((a.baselineY - b.baselineY).abs() > a.fontSize * 0.3) return false;
    final gap = b.baselineX - a.endX;
    if (gap < -a.fontSize * 0.5) return false;
    if (gap > a.fontSize * 1.0) return false;
    return true;
  }

  TextRun _merge(TextRun a, TextRun b) {
    final parts = <TextRun>[
      ...(a.constituents ?? [a]),
      ...(b.constituents ?? [b]),
    ];
    final left = min(a.x, b.x);
    final right = max(a.x + a.width, b.x + b.width);
    final bottom = min(a.y, b.y);
    final top = max(a.y + a.height, b.y + b.height);
    final gap = b.baselineX - a.endX;
    final needsSpace = gap > a.fontSize * 0.15;
    final text = a.text + (needsSpace ? ' ' : '') + b.text;

    return TextRun(
      id: a.id,
      byteStart: a.byteStart,
      byteEnd: b.byteEnd,
      text: text,
      x: left,
      y: bottom,
      width: right - left,
      height: top - bottom,
      baselineX: a.baselineX,
      baselineY: a.baselineY,
      endX: b.endX,
      fontRef: a.fontRef,
      fontSize: a.fontSize,
      widthEm: a.widthEm + b.widthEm,
      originalHz: a.originalHz,
      charSpacing: a.charSpacing,
      wordSpacing: a.wordSpacing,
      kerning: null,
      constituents: parts,
    );
  }

  static double _d(dynamic v) => v is num ? v.toDouble() : 0.0;

  static Uint8List? _hexToBytes(String hex) {
    if (hex.isEmpty) return null;
    final padded = hex.length.isOdd ? '${hex}0' : hex;
    final out = <int>[];
    for (int i = 0; i < padded.length; i += 2) {
      final b = int.tryParse(padded.substring(i, i + 2), radix: 16);
      if (b != null) out.add(b);
    }
    return Uint8List.fromList(out);
  }
}