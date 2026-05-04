import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/annotation.dart';

// AnnotationPainter — renders ALL annotation layers over a PDF page.
// Coordinates are NORMALISED [0,1]; painter denormalises using canvas size.

class AnnotationPainter extends CustomPainter {
  final List<RectAnnotation>  rects;
  final InkAnnotation?        ink;
  final InkStroke?            activeStroke;
  final List<StickyNote>      notes;
  final List<TextStamp>       textStamps;
  final List<RedactionRect>   redactions;
  final List<ClauseBookmark>  clauseBookmarks;

  // Draft overlays while user is dragging
  final Rect?             draftRect;
  final AnnotationType?   draftType;
  final Color             draftColor;

  const AnnotationPainter({
    required this.rects,
    required this.ink,
    this.activeStroke,
    required this.notes,
    required this.textStamps,
    required this.redactions,
    required this.clauseBookmarks,
    this.draftRect,
    this.draftType,
    this.draftColor = Colors.yellow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    _drawRedactions(canvas, w, h);
    _drawRects(canvas, w, h);
    if (draftRect != null && draftType != null) {
      _drawOneRect(canvas, draftRect!, draftColor, draftType!, w, h, opacity: 0.5);
    }
    _drawInk(canvas, w, h);
    if (activeStroke != null) _drawStroke(canvas, activeStroke!, w, h);
    _drawTextStamps(canvas, w, h);
    _drawClauseBookmarks(canvas, w, h);
    _drawNoteIcons(canvas, w, h);
  }

  // ── Redactions ────────────────────────────────────────────────────────────

  void _drawRedactions(Canvas canvas, double w, double h) {
    for (final r in redactions) {
      final rect = _dn(r.normRect, w, h);
      canvas.drawRect(rect, Paint()..color = Colors.black);
      // White REDACTED label
      (TextPainter(
        text: const TextSpan(text: 'REDACTED',
            style: TextStyle(color: Colors.white54, fontSize: 10,
                fontWeight: FontWeight.bold, letterSpacing: 1)),
        textDirection: TextDirection.ltr,
      )..layout()).paint(canvas,
          Offset(rect.left + 4, rect.top + (rect.height - 12) / 2));
    }
  }

  // ── Rect annotations ──────────────────────────────────────────────────────

  void _drawRects(Canvas canvas, double w, double h) {
    for (final ann in rects) {
      _drawOneRect(canvas, ann.normRect, ann.color, ann.type, w, h);
    }
  }

  void _drawOneRect(Canvas canvas, Rect norm, Color color, AnnotationType type,
      double w, double h, {double opacity = 1.0}) {
    final rect = _dn(norm, w, h);
    switch (type) {
      case AnnotationType.highlight:
        canvas.drawRect(rect, Paint()..color = color.withOpacity(0.38 * opacity));
      case AnnotationType.underline:
        canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.right, rect.bottom),
            Paint()..color = color.withOpacity(opacity)..strokeWidth = w * 0.004
                  ..strokeCap = ui.StrokeCap.round);
      case AnnotationType.strikethrough:
        canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy),
            Paint()..color = color.withOpacity(opacity)..strokeWidth = w * 0.004
                  ..strokeCap = ui.StrokeCap.round);
      default: break;
    }
  }

  // ── Ink ───────────────────────────────────────────────────────────────────

  void _drawInk(Canvas canvas, double w, double h) {
    if (ink == null) return;
    for (final stroke in ink!.strokes) _drawStroke(canvas, stroke, w, h);
  }

  void _drawStroke(Canvas canvas, InkStroke stroke, double w, double h) {
    if (stroke.points.length < 2) return;
    final path = Path();
    final f = stroke.points.first;
    path.moveTo(f.dx * w, f.dy * h);
    for (int i = 1; i < stroke.points.length - 1; i++) {
      final cur  = stroke.points[i];
      final next = stroke.points[i + 1];
      path.quadraticBezierTo(
        cur.dx * w, cur.dy * h,
        (cur.dx + next.dx) / 2 * w, (cur.dy + next.dy) / 2 * h,
      );
    }
    final l = stroke.points.last;
    path.lineTo(l.dx * w, l.dy * h);
    canvas.drawPath(path, Paint()
      ..color       = stroke.color
      ..strokeWidth = stroke.normWidth * w
      ..strokeCap   = ui.StrokeCap.round
      ..strokeJoin  = ui.StrokeJoin.round
      ..style       = ui.PaintingStyle.stroke);
  }

  // ── Text stamps ───────────────────────────────────────────────────────────

  void _drawTextStamps(Canvas canvas, double w, double h) {
    for (final stamp in textStamps) {
      (TextPainter(
        text: TextSpan(text: stamp.text,
            style: TextStyle(color: stamp.color,
                fontSize: stamp.normFontSize * h, fontWeight: FontWeight.w500)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w * 0.6)).paint(canvas,
          Offset(stamp.normPosition.dx * w, stamp.normPosition.dy * h));
    }
  }

  // ── Clause bookmarks ──────────────────────────────────────────────────────

  void _drawClauseBookmarks(Canvas canvas, double w, double h) {
    for (final clause in clauseBookmarks) {
      final rect = _dn(clause.normRect, w, h);
      canvas.drawRect(rect,
          Paint()..color = clause.color.withOpacity(0.10)..style = ui.PaintingStyle.fill);
      canvas.drawRect(rect,
          Paint()..color = clause.color..style = ui.PaintingStyle.stroke..strokeWidth = 1.8);
      // Label badge
      final tp = TextPainter(
        text: TextSpan(text: '  ${clause.label}  ',
            style: TextStyle(color: Colors.white, fontSize: w * 0.022,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top - tp.height - 2, tp.width, tp.height + 4),
          const Radius.circular(3)),
        Paint()..color = clause.color);
      tp.paint(canvas, Offset(rect.left, rect.top - tp.height - 2));
    }
  }

  // ── Sticky note icons ─────────────────────────────────────────────────────

  void _drawNoteIcons(Canvas canvas, double w, double h) {
    for (final note in notes) {
      final sz = 0.05 * w;
      final x  = note.normPosition.dx * w;
      final y  = note.normPosition.dy * h;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, sz, sz), Radius.circular(sz * 0.22)),
        Paint()..color = note.color);
      final lp = Paint()..color = Colors.white.withOpacity(0.85)
                        ..strokeWidth = sz * 0.11..strokeCap = ui.StrokeCap.round;
      for (int i = 0; i < 3; i++) {
        final ly = y + sz * (0.28 + i * 0.23);
        canvas.drawLine(Offset(x + sz * 0.2, ly), Offset(x + sz * 0.8, ly), lp);
      }
      // Expanded tooltip
      if (note.isExpanded && note.text.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(text: note.text,
              style: TextStyle(color: Colors.white, fontSize: w * 0.022)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: w * 0.35);
        final pad = 6.0;
        final bx = (x + sz + 4).clamp(0.0, w - tp.width - pad * 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bx - pad, y - pad, tp.width + pad * 2, tp.height + pad * 2),
            const Radius.circular(6)),
          Paint()..color = note.color.withOpacity(0.92));
        tp.paint(canvas, Offset(bx, y));
      }
    }
  }

  Rect _dn(Rect n, double w, double h) =>
      Rect.fromLTWH(n.left * w, n.top * h, n.width * w, n.height * h);

  @override
  bool shouldRepaint(AnnotationPainter o) => true;
}
