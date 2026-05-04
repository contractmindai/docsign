import 'dart:typed_data';
import 'dart:ui';

// ─────────────────────────────────────────────────────────────────────────────
// Annotation models — all include toJson/fromJson for persistence
// ─────────────────────────────────────────────────────────────────────────────

enum AnnotationTool {
  view, highlight, underline, strikethrough, ink,
  stickyNote, signature, initials, textStamp, redaction, clauseBookmark,
}

enum AnnotationType { highlight, underline, strikethrough, ink, stickyNote }

// ── Rect annotation ───────────────────────────────────────────────────────────

class RectAnnotation {
  final String id;
  final int pageIndex;
  final Rect normRect;
  final Color color;
  final AnnotationType type;
  const RectAnnotation({
    required this.id, required this.pageIndex, required this.normRect,
    required this.color, required this.type,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'pageIndex': pageIndex,
    'l': normRect.left, 't': normRect.top,
    'r': normRect.right, 'b': normRect.bottom,
    'color': color.value, 'type': type.name,
  };

  factory RectAnnotation.fromJson(Map<String, dynamic> j) => RectAnnotation(
    id: j['id'] as String, pageIndex: j['pageIndex'] as int,
    normRect: Rect.fromLTRB((j['l'] as num).toDouble(), (j['t'] as num).toDouble(),
        (j['r'] as num).toDouble(), (j['b'] as num).toDouble()),
    color: Color(j['color'] as int),
    type: AnnotationType.values.firstWhere((e) => e.name == j['type'],
        orElse: () => AnnotationType.highlight),
  );
}

// ── Ink stroke ────────────────────────────────────────────────────────────────

class InkStroke {
  final List<Offset> points;
  final Color color;
  final double normWidth;
  const InkStroke({required this.points, required this.color, required this.normWidth});

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'color': color.value, 'normWidth': normWidth,
  };

  factory InkStroke.fromJson(Map<String, dynamic> j) => InkStroke(
    points: (j['points'] as List).map((p) =>
        Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList(),
    color: Color(j['color'] as int),
    normWidth: (j['normWidth'] as num).toDouble(),
  );
}

class InkAnnotation {
  final String id;
  final int pageIndex;
  final List<InkStroke> strokes;
  const InkAnnotation({required this.id, required this.pageIndex, required this.strokes});

  InkAnnotation addStroke(InkStroke s) =>
      InkAnnotation(id: id, pageIndex: pageIndex, strokes: [...strokes, s]);

  Map<String, dynamic> toJson() => {
    'id': id, 'pageIndex': pageIndex,
    'strokes': strokes.map((s) => s.toJson()).toList(),
  };

  factory InkAnnotation.fromJson(Map<String, dynamic> j) => InkAnnotation(
    id: j['id'] as String, pageIndex: j['pageIndex'] as int,
    strokes: (j['strokes'] as List)
        .map((s) => InkStroke.fromJson(s as Map<String, dynamic>)).toList(),
  );
}

// ── Sticky note ───────────────────────────────────────────────────────────────

class StickyNote {
  final String id;
  final int pageIndex;
  final Offset normPosition;
  final String text;
  final Color color;
  bool isExpanded;
  StickyNote({
    required this.id, required this.pageIndex, required this.normPosition,
    required this.text, required this.color, this.isExpanded = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'pageIndex': pageIndex,
    'x': normPosition.dx, 'y': normPosition.dy,
    'text': text, 'color': color.value,
  };

  factory StickyNote.fromJson(Map<String, dynamic> j) => StickyNote(
    id: j['id'] as String, pageIndex: j['pageIndex'] as int,
    normPosition: Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
    text: j['text'] as String, color: Color(j['color'] as int),
  );
}

// ── Text stamp ────────────────────────────────────────────────────────────────

class TextStamp {
  final String id;
  final int pageIndex;
  Offset normPosition;
  final String text;
  final Color color;
  final double normFontSize;
  TextStamp({
    required this.id, required this.pageIndex, required this.normPosition,
    required this.text, required this.color, this.normFontSize = 0.022,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'pageIndex': pageIndex,
    'x': normPosition.dx, 'y': normPosition.dy,
    'text': text, 'color': color.value, 'normFontSize': normFontSize,
  };

  factory TextStamp.fromJson(Map<String, dynamic> j) => TextStamp(
    id: j['id'] as String, pageIndex: j['pageIndex'] as int,
    normPosition: Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
    text: j['text'] as String, color: Color(j['color'] as int),
    normFontSize: (j['normFontSize'] as num?)?.toDouble() ?? 0.022,
  );
}

// ── Redaction ─────────────────────────────────────────────────────────────────

class RedactionRect {
  final String id;
  final int pageIndex;
  final Rect normRect;
  const RedactionRect({required this.id, required this.pageIndex, required this.normRect});

  Map<String, dynamic> toJson() => {
    'id': id, 'pageIndex': pageIndex,
    'l': normRect.left, 't': normRect.top,
    'r': normRect.right, 'b': normRect.bottom,
  };

  factory RedactionRect.fromJson(Map<String, dynamic> j) => RedactionRect(
    id: j['id'] as String, pageIndex: j['pageIndex'] as int,
    normRect: Rect.fromLTRB((j['l'] as num).toDouble(), (j['t'] as num).toDouble(),
        (j['r'] as num).toDouble(), (j['b'] as num).toDouble()),
  );
}

// ── Clause bookmark ───────────────────────────────────────────────────────────

class ClauseBookmark {
  final String id;
  final int pageIndex;
  final Rect normRect;
  final String label;
  final Color color;
  const ClauseBookmark({
    required this.id, required this.pageIndex, required this.normRect,
    required this.label, required this.color,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'pageIndex': pageIndex,
    'l': normRect.left, 't': normRect.top,
    'r': normRect.right, 'b': normRect.bottom,
    'label': label, 'color': color.value,
  };

  factory ClauseBookmark.fromJson(Map<String, dynamic> j) => ClauseBookmark(
    id: j['id'] as String, pageIndex: j['pageIndex'] as int,
    normRect: Rect.fromLTRB((j['l'] as num).toDouble(), (j['t'] as num).toDouble(),
        (j['r'] as num).toDouble(), (j['b'] as num).toDouble()),
    label: j['label'] as String, color: Color(j['color'] as int),
  );
}

// ── Signature overlay ─────────────────────────────────────────────────────────

class SignatureOverlay {
  final String id;
  final Uint8List imageBytes;
  final int pageIndex;
  Offset normPosition;
  Size normSize;
  final bool isInitials;
  final String? slotId;
  final String? signerName;
  SignatureOverlay({
    required this.id, required this.imageBytes, required this.pageIndex,
    required this.normPosition,
    this.normSize = const Size(0.35, 0.07),
    this.isInitials = false, this.slotId, this.signerName,
  });
}

// ── Text Edit Annotation ─────────────────────────────────────────────────────────────────
class TextEditAnnotation {
  final String id;
  final int pageIndex;
  final Offset normPosition;
  final String text;
  final Color color;
  final double fontSize;
  final bool isBold;
  final bool isItalic;
  final String fontFamily;
  
  TextEditAnnotation({
    required this.id,
    required this.pageIndex,
    required this.normPosition,
    required this.text,
    required this.color,
    this.fontSize = 14,
    this.isBold = false,
    this.isItalic = false,
    this.fontFamily = 'Inter',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'pageIndex': pageIndex,
    'x': normPosition.dx,
    'y': normPosition.dy,
    'text': text,
    'color': color.value,
    'fontSize': fontSize,
    'isBold': isBold,
    'isItalic': isItalic,
    'fontFamily': fontFamily,
  };

  factory TextEditAnnotation.fromJson(Map<String, dynamic> j) => TextEditAnnotation(
    id: j['id'] as String,
    pageIndex: j['pageIndex'] as int,
    normPosition: Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
    text: j['text'] as String,
    color: Color(j['color'] as int),
    fontSize: (j['fontSize'] as num?)?.toDouble() ?? 14,
    isBold: j['isBold'] as bool? ?? false,
    isItalic: j['isItalic'] as bool? ?? false,
    fontFamily: j['fontFamily'] as String? ?? 'Inter',
  );
}

// ── Other models (no persistence needed) ────────────────────────────────────

class DetectedField {
  final int pageIndex;
  final double normX, normY, normWidth;
  final String label;
  const DetectedField({
    required this.pageIndex, required this.normX, required this.normY,
    required this.normWidth, this.label = 'Signature',
  });
}

class ExpiryDate {
  final String rawText;
  final DateTime? parsed;
  final int pageIndex;
  const ExpiryDate({required this.rawText, this.parsed, required this.pageIndex});
}

class SignatureSlot {
  final String id;
  final String role;
  final Color color;
  bool isSigned;
  SignatureSlot({required this.id, required this.role, required this.color, this.isSigned = false});
}