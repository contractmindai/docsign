import 'dart:typed_data';
import 'dart:ui';

// ─────────────────────────────────────────────────────────────────────────────
// Annotation models — all include toJson/fromJson for persistence
// ─────────────────────────────────────────────────────────────────────────────

enum AnnotationTool {
  view,
  highlight,
  underline,
  strikethrough,
  ink,
  stickyNote,
  signature,
  initials,
  textStamp,
  redaction,
  clauseBookmark,
  textEdit, // ← new: free-form text placement / in-place replacement
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
    required this.id,
    required this.pageIndex,
    required this.normRect,
    required this.color,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'l': normRect.left,
        't': normRect.top,
        'r': normRect.right,
        'b': normRect.bottom,
        'color': color.value,
        'type': type.name,
      };

  factory RectAnnotation.fromJson(Map<String, dynamic> j) => RectAnnotation(
        id: j['id'] as String,
        pageIndex: j['pageIndex'] as int,
        normRect: Rect.fromLTRB(
          (j['l'] as num).toDouble(),
          (j['t'] as num).toDouble(),
          (j['r'] as num).toDouble(),
          (j['b'] as num).toDouble(),
        ),
        color: Color(j['color'] as int),
        type: AnnotationType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => AnnotationType.highlight,
        ),
      );
}

// ── Ink stroke ────────────────────────────────────────────────────────────────

class InkStroke {
  final List<Offset> points;
  final Color color;
  final double normWidth;
  const InkStroke({
    required this.points,
    required this.color,
    required this.normWidth,
  });

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'color': color.value,
        'normWidth': normWidth,
      };

  factory InkStroke.fromJson(Map<String, dynamic> j) => InkStroke(
        points: (j['points'] as List)
            .map((p) => Offset(
                  (p['x'] as num).toDouble(),
                  (p['y'] as num).toDouble(),
                ))
            .toList(),
        color: Color(j['color'] as int),
        normWidth: (j['normWidth'] as num).toDouble(),
      );
}

class InkAnnotation {
  final String id;
  final int pageIndex;
  final List<InkStroke> strokes;
  const InkAnnotation({
    required this.id,
    required this.pageIndex,
    required this.strokes,
  });

  InkAnnotation addStroke(InkStroke s) =>
      InkAnnotation(id: id, pageIndex: pageIndex, strokes: [...strokes, s]);

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory InkAnnotation.fromJson(Map<String, dynamic> j) => InkAnnotation(
        id: j['id'] as String,
        pageIndex: j['pageIndex'] as int,
        strokes: (j['strokes'] as List)
            .map((s) => InkStroke.fromJson(s as Map<String, dynamic>))
            .toList(),
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
    required this.id,
    required this.pageIndex,
    required this.normPosition,
    required this.text,
    required this.color,
    this.isExpanded = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'x': normPosition.dx,
        'y': normPosition.dy,
        'text': text,
        'color': color.value,
      };

  factory StickyNote.fromJson(Map<String, dynamic> j) => StickyNote(
        id: j['id'] as String,
        pageIndex: j['pageIndex'] as int,
        normPosition: Offset(
          (j['x'] as num).toDouble(),
          (j['y'] as num).toDouble(),
        ),
        text: j['text'] as String,
        color: Color(j['color'] as int),
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
    required this.id,
    required this.pageIndex,
    required this.normPosition,
    required this.text,
    required this.color,
    this.normFontSize = 0.022,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'x': normPosition.dx,
        'y': normPosition.dy,
        'text': text,
        'color': color.value,
        'normFontSize': normFontSize,
      };

  factory TextStamp.fromJson(Map<String, dynamic> j) => TextStamp(
        id: j['id'] as String,
        pageIndex: j['pageIndex'] as int,
        normPosition: Offset(
          (j['x'] as num).toDouble(),
          (j['y'] as num).toDouble(),
        ),
        text: j['text'] as String,
        color: Color(j['color'] as int),
        normFontSize: (j['normFontSize'] as num?)?.toDouble() ?? 0.022,
      );
}

// ── Redaction ─────────────────────────────────────────────────────────────────

class RedactionRect {
  final String id;
  final int pageIndex;
  final Rect normRect;
  const RedactionRect({
    required this.id,
    required this.pageIndex,
    required this.normRect,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'l': normRect.left,
        't': normRect.top,
        'r': normRect.right,
        'b': normRect.bottom,
      };

  factory RedactionRect.fromJson(Map<String, dynamic> j) => RedactionRect(
        id: j['id'] as String,
        pageIndex: j['pageIndex'] as int,
        normRect: Rect.fromLTRB(
          (j['l'] as num).toDouble(),
          (j['t'] as num).toDouble(),
          (j['r'] as num).toDouble(),
          (j['b'] as num).toDouble(),
        ),
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
    required this.id,
    required this.pageIndex,
    required this.normRect,
    required this.label,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'l': normRect.left,
        't': normRect.top,
        'r': normRect.right,
        'b': normRect.bottom,
        'label': label,
        'color': color.value,
      };

  factory ClauseBookmark.fromJson(Map<String, dynamic> j) => ClauseBookmark(
        id: j['id'] as String,
        pageIndex: j['pageIndex'] as int,
        normRect: Rect.fromLTRB(
          (j['l'] as num).toDouble(),
          (j['t'] as num).toDouble(),
          (j['r'] as num).toDouble(),
          (j['b'] as num).toDouble(),
        ),
        label: j['label'] as String,
        color: Color(j['color'] as int),
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
    required this.id,
    required this.imageBytes,
    required this.pageIndex,
    required this.normPosition,
    this.normSize = const Size(0.35, 0.07),
    this.isInitials = false,
    this.slotId,
    this.signerName,
  });
}

// ── Text edit annotation ──────────────────────────────────────────────────────

/// Represents free-form text the user typed on top of a page.
///
/// Two usages are supported by the same model:
///
///  * **Stamp mode** — [originalText] is empty; the annotation is pure
///    additional text placed at [normPosition].
///  * **Replace mode** — [originalText] holds the run of text that was
///    underneath the tap and [originalNormRect] is the box it occupied.
///    The writer then erases that box and writes [text] in its place,
///    keeping the replacement inside the original bounds if
///    [preserveWidth] is true.
class TextEditAnnotation {
  final String id;
  final int pageIndex;

  /// Where the text is anchored (top-left, y measured down from the top
  /// of the page and normalized to 0..1 like every other annotation).
  final Offset normPosition;

  /// The new text the user typed.
  final String text;

  /// Colour, size, and style for the new text.
  final Color color;
  final double fontSize;
  final bool isBold;
  final bool isItalic;
  final String fontFamily;

  /// The text that was under the tap when the edit was created.
  /// Empty when this annotation is a pure stamp (no original text).
  final String originalText;

  /// Bounding box of the original text run, normalized to 0..1.
  /// Null when this annotation is a pure stamp.
  final Rect? originalNormRect;

  /// Whether the writer should horizontally squeeze the new text to fit
  /// inside [originalNormRect] (only meaningful in replace mode).
  final bool preserveWidth;

  /// ARGB color used to cover the original text box before drawing the new
  /// text. Sampled from the page background at commit time so the cover
  /// blends into colored pages and images instead of showing a white patch.
  ///
  /// Defaults to opaque white (`0xFFFFFFFF`), which is exactly what the
  /// earlier hardcoded cover used — so annotations loaded from older
  /// sidecar files without this field still render correctly.
  final int coverColorValue;

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
    this.originalText = '',
    this.originalNormRect,
    this.preserveWidth = true,
    this.coverColorValue = 0xFFFFFFFF,
  });

  /// True when this annotation is meant to replace existing text.
  bool get isReplacement => originalNormRect != null && originalText.isNotEmpty;

  TextEditAnnotation copyWith({
    String? text,
    Color? color,
    double? fontSize,
    bool? isBold,
    bool? isItalic,
    String? fontFamily,
    Offset? normPosition,
    Rect? originalNormRect,
    String? originalText,
    bool? preserveWidth,
    int? coverColorValue,
  }) {
    return TextEditAnnotation(
      id: id,
      pageIndex: pageIndex,
      normPosition: normPosition ?? this.normPosition,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      fontFamily: fontFamily ?? this.fontFamily,
      originalText: originalText ?? this.originalText,
      originalNormRect: originalNormRect ?? this.originalNormRect,
      preserveWidth: preserveWidth ?? this.preserveWidth,
      coverColorValue: coverColorValue ?? this.coverColorValue,
    );
  }

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
        'originalText': originalText,
        if (originalNormRect != null) ...{
          'ol': originalNormRect!.left,
          'ot': originalNormRect!.top,
          'or': originalNormRect!.right,
          'ob': originalNormRect!.bottom,
        },
        'preserveWidth': preserveWidth,
        'coverColor': coverColorValue,
      };

  factory TextEditAnnotation.fromJson(Map<String, dynamic> j) {
    Rect? origRect;
    if (j['ol'] != null && j['ot'] != null &&
        j['or'] != null && j['ob'] != null) {
      origRect = Rect.fromLTRB(
        (j['ol'] as num).toDouble(),
        (j['ot'] as num).toDouble(),
        (j['or'] as num).toDouble(),
        (j['ob'] as num).toDouble(),
      );
    }
    return TextEditAnnotation(
      id: j['id'] as String,
      pageIndex: j['pageIndex'] as int,
      normPosition: Offset(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
      ),
      text: j['text'] as String,
      color: Color(j['color'] as int),
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 14,
      isBold: j['isBold'] as bool? ?? false,
      isItalic: j['isItalic'] as bool? ?? false,
      fontFamily: j['fontFamily'] as String? ?? 'Inter',
      originalText: j['originalText'] as String? ?? '',
      originalNormRect: origRect,
      preserveWidth: j['preserveWidth'] as bool? ?? true,
      coverColorValue: (j['coverColor'] as int?) ?? 0xFFFFFFFF,
    );
  }
}

// ── Other models (no persistence needed) ──────────────────────────────────────

class DetectedField {
  final int pageIndex;
  final double normX, normY, normWidth;
  final String label;
  const DetectedField({
    required this.pageIndex,
    required this.normX,
    required this.normY,
    required this.normWidth,
    this.label = 'Signature',
  });
}

class ExpiryDate {
  final String rawText;
  final DateTime? parsed;
  final int pageIndex;
  const ExpiryDate({
    required this.rawText,
    this.parsed,
    required this.pageIndex,
  });
}

class SignatureSlot {
  final String id;
  final String role;
  final Color color;
  bool isSigned;
  SignatureSlot({
    required this.id,
    required this.role,
    required this.color,
    this.isSigned = false,
  });
}