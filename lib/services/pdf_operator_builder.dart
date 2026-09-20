import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibEncoder;
import 'package:flutter/material.dart' show Color;
import 'package:image/image.dart' as img;

import '../models/annotation.dart';
import '../pdf_core/incremental_writer.dart';

/// Builds PDF content-stream operators for every annotation type that can be
/// expressed without an image XObject.
///
/// Coordinate conventions:
///   * All annotation models store normalised, top-down coordinates
///     (0..1 from the top-left of the page).
///   * PDF operators use bottom-up coordinates in points.
///   * Every builder here performs the Y flip.
class PdfOperatorBuilder {
  static String buildPageOperators({
    required double pageW,
    required double pageH,
    required List<RectAnnotation> rects,
    required InkAnnotation? ink,
    required List<TextStamp> stamps,
    required List<RedactionRect> redactions,
    required List<ClauseBookmark> bookmarks,
    required List<TextEditAnnotation> textEdits,
  }) {
    final b = StringBuffer();
    b.write(_rectOps(rects, pageW, pageH));
    b.write(_inkOps(ink, pageW, pageH));
    b.write(_redactionOps(redactions, pageW, pageH));
    b.write(_bookmarkOps(bookmarks, pageW, pageH));
    b.write(_textStampOps(stamps, pageW, pageH));
    b.write(_textEditOps(textEdits, pageW, pageH));
    return b.toString();
  }

  static ({IncrementalUpdatePayload payload, String name, String ops})
      buildSignatureImage({
    required int newObjectId,
    required SignatureOverlay sig,
    required double pageW,
    required double pageH,
  }) {
    final decoded = img.decodePng(sig.imageBytes);
    if (decoded == null) {
      throw StateError('Failed to decode signature image as PNG');
    }

    final w = decoded.width;
    final h = decoded.height;

    final rgb = Uint8List(w * h * 3);
    int dst = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = decoded.getPixel(x, y);
        rgb[dst++] = p.r.toInt();
        rgb[dst++] = p.g.toInt();
        rgb[dst++] = p.b.toInt();
      }
    }

    final compressed = ZLibEncoder().encode(rgb);

    final header = '<< /Type /XObject /Subtype /Image '
        '/Width $w /Height $h /ColorSpace /DeviceRGB '
        '/BitsPerComponent 8 /Filter /FlateDecode '
        '/Length ${compressed.length} >>\nstream\n';
    final trailer = '\nendstream';

    final buf = BytesBuilder(copy: false)
      ..add(_latin1(header))
      ..add(compressed)
      ..add(_latin1(trailer));

    final name = '/SigX$newObjectId';
    final payload = IncrementalUpdatePayload(newObjectId, 0, buf.takeBytes());

    final x = sig.normPosition.dx * pageW;
    final yTop = (1.0 - sig.normPosition.dy) * pageH;
    final sw = sig.normSize.width * pageW;
    final sh = sig.normSize.height * pageH;
    final yBottom = yTop - sh;

    final ops =
        'q ${_f(sw)} 0 0 ${_f(sh)} ${_f(x)} ${_f(yBottom)} cm $name Do Q\n';

    return (payload: payload, name: name, ops: ops);
  }

  // ── Individual operator blocks ──────────────────────────────────────────

  static String _rectOps(
      List<RectAnnotation> rects, double pageW, double pageH) {
    if (rects.isEmpty) return '';
    final b = StringBuffer();

    for (final r in rects) {
      final x1 = r.normRect.left * pageW;
      final x2 = (r.normRect.left + r.normRect.width) * pageW;
      final yTop = (1.0 - r.normRect.top) * pageH;
      final yBottom = (1.0 - r.normRect.top - r.normRect.height) * pageH;
      final w = x2 - x1;
      final h = yTop - yBottom;

      switch (r.type) {
        case AnnotationType.highlight:
          final rv = ((r.color.value >> 16) & 0xFF) / 255.0;
          final gv = ((r.color.value >> 8) & 0xFF) / 255.0;
          final bv = (r.color.value & 0xFF) / 255.0;
          const a = 0.4;
          final lr = (rv * a + 1.0 * (1 - a)).toStringAsFixed(3);
          final lg = (gv * a + 1.0 * (1 - a)).toStringAsFixed(3);
          final lb = (bv * a + 1.0 * (1 - a)).toStringAsFixed(3);
          b.writeln('q $lr $lg $lb rg '
              '${_f(x1)} ${_f(yBottom)} ${_f(w)} ${_f(h)} re f Q');
          break;
        case AnnotationType.underline:
          b.writeln('q ${_rgb(r.color)} RG 1 w '
              '${_f(x1)} ${_f(yBottom + 1)} m '
              '${_f(x2)} ${_f(yBottom + 1)} l S Q');
          break;
        case AnnotationType.strikethrough:
          final midY = (yTop + yBottom) / 2;
          b.writeln('q ${_rgb(r.color)} RG 1 w '
              '${_f(x1)} ${_f(midY)} m '
              '${_f(x2)} ${_f(midY)} l S Q');
          break;
        case AnnotationType.ink:
        case AnnotationType.stickyNote:
          break;
      }
    }
    return b.toString();
  }

  static String _inkOps(InkAnnotation? ink, double pageW, double pageH) {
    if (ink == null || ink.strokes.isEmpty) return '';
    final b = StringBuffer();

    for (final stroke in ink.strokes) {
      final pts = stroke.points;
      if (pts.isEmpty) continue;

      final rgb = _rgb(stroke.color);
      final lw = (stroke.normWidth > 1.0)
          ? stroke.normWidth.clamp(0.5, 12.0)
          : (stroke.normWidth * pageW / 72).clamp(0.5, 12.0);

      final xs = pts.map((p) => p.dx * pageW).toList();
      final ys = pts.map((p) => (1.0 - p.dy) * pageH).toList();

      if (pts.length == 1) {
        final d = lw;
        b.writeln('q $rgb rg ${_f(xs[0] - d / 2)} ${_f(ys[0] - d / 2)} '
            '${_f(d)} ${_f(d)} re f Q');
      } else {
        b.write('q $rgb RG ${_f(lw)} w 1 J 1 j '
            '${_f(xs[0])} ${_f(ys[0])} m');
        for (int i = 1; i < xs.length; i++) {
          b.write(' ${_f(xs[i])} ${_f(ys[i])} l');
        }
        b.writeln(' S Q');
      }
    }
    return b.toString();
  }

  static String _redactionOps(
      List<RedactionRect> redactions, double pageW, double pageH) {
    if (redactions.isEmpty) return '';
    final b = StringBuffer();
    for (final r in redactions) {
      final x1 = r.normRect.left * pageW;
      final yTop = (1.0 - r.normRect.top) * pageH;
      final yBottom = (1.0 - r.normRect.top - r.normRect.height) * pageH;
      final w = r.normRect.width * pageW;
      final h = yTop - yBottom;
      b.writeln('q 0 g ${_f(x1)} ${_f(yBottom)} ${_f(w)} ${_f(h)} re f Q');
    }
    return b.toString();
  }

  static String _bookmarkOps(
      List<ClauseBookmark> bookmarks, double pageW, double pageH) {
    if (bookmarks.isEmpty) return '';
    final b = StringBuffer();
    for (final bk in bookmarks) {
      final x1 = bk.normRect.left * pageW;
      final yTop = (1.0 - bk.normRect.top) * pageH;
      final yBottom = (1.0 - bk.normRect.top - bk.normRect.height) * pageH;
      final w = bk.normRect.width * pageW;
      final h = yTop - yBottom;
      b.writeln('q ${_rgb(bk.color)} RG 1.5 w '
          '${_f(x1)} ${_f(yBottom)} ${_f(w)} ${_f(h)} re S Q');
    }
    return b.toString();
  }

  static String _textStampOps(
      List<TextStamp> stamps, double pageW, double pageH) {
    if (stamps.isEmpty) return '';
    final b = StringBuffer();
    const fontRes = '/Helv';

    for (final s in stamps) {
      final x = s.normPosition.dx * pageW;
      final yTop = (1.0 - s.normPosition.dy) * pageH;
      const fs = 12.0;
      final yBaseline = yTop - fs * 0.8;
      b.writeln('q BT 0 Tr ${_rgb(s.color)} rg '
          '$fontRes ${_f(fs)} Tf '
          '${_f(x)} ${_f(yBaseline)} Td (${_escape(s.text)}) Tj ET Q');
    }
    return b.toString();
  }

  static String _textEditOps(
      List<TextEditAnnotation> edits, double pageW, double pageH) {
    if (edits.isEmpty) return '';
    final b = StringBuffer();

    for (final t in edits) {
      final fontRes = _fontResFor(t.fontFamily);

      if (t.isReplacement && t.originalNormRect != null) {
        final r = t.originalNormRect!;
        final x1 = r.left * pageW;
        final yTop = (1.0 - r.top) * pageH;
        final yBottom = (1.0 - r.top - r.height) * pageH;
        final w = r.width * pageW;
        final h = yTop - yBottom;

        // Cover rectangle, colored with the annotation's sampled
        // background so it blends with the page.
        final cv = t.coverColorValue;
        final cr = ((cv >> 16) & 0xFF) / 255.0;
        final cg = ((cv >> 8) & 0xFF) / 255.0;
        final cb = (cv & 0xFF) / 255.0;

        const coverPad = 3.0;
        b.writeln('q ${cr.toStringAsFixed(3)} ${cg.toStringAsFixed(3)} '
            '${cb.toStringAsFixed(3)} rg '
            '${_f(x1 - coverPad)} ${_f(yBottom - coverPad)} '
            '${_f(w + coverPad * 2)} ${_f(h + coverPad * 2)} re f Q');

        final double fitted = t.fontSize > 0
            ? t.fontSize
            : _fitFontSize(t.text, h * 0.75, w, h);

        final yCenter = (yTop + yBottom) / 2;
        final yBaseline = yCenter - fitted * 0.35;

        b.writeln('q BT 0 Tr ${_rgb(t.color)} rg '
            '$fontRes ${_f(fitted)} Tf '
            '${_f(x1)} ${_f(yBaseline)} Td (${_escape(t.text)}) Tj ET Q');
      } else {
        final x = t.normPosition.dx * pageW;
        final yTop = (1.0 - t.normPosition.dy) * pageH;
        final size = t.fontSize > 0 ? t.fontSize : 14.0;
        final yBaseline = yTop - size * 0.8;
        b.writeln('q BT 0 Tr ${_rgb(t.color)} rg '
            '$fontRes ${_f(size)} Tf '
            '${_f(x)} ${_f(yBaseline)} Td (${_escape(t.text)}) Tj ET Q');
      }
    }
    return b.toString();
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static String _fontResFor(String family) {
    switch (family.toLowerCase().trim()) {
      case 'times new roman':
      case 'times':
      case 'georgia':
      case 'serif':
        return '/TiRo';
      case 'courier':
      case 'monospace':
        return '/Cour';
      case 'inter':
      case 'helvetica':
      case 'arial':
      case 'sans-serif':
      default:
        return '/Helv';
    }
  }

  static String _rgb(Color c) {
    final r = ((c.value >> 16) & 0xFF) / 255.0;
    final g = ((c.value >> 8) & 0xFF) / 255.0;
    final b = (c.value & 0xFF) / 255.0;
    return '${r.toStringAsFixed(3)} ${g.toStringAsFixed(3)} '
        '${b.toStringAsFixed(3)}';
  }

  static String _escape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');

  static String _f(double n) => n == n.roundToDouble()
      ? n.toInt().toString()
      : n.toStringAsFixed(2);

  static Uint8List _latin1(String s) {
    final out = Uint8List(s.length);
    for (int i = 0; i < s.length; i++) out[i] = s.codeUnitAt(i) & 0xFF;
    return out;
  }

  static double _fitFontSize(
      String text, double desired, double boxW, double boxH) {
    if (text.isEmpty || boxW <= 0 || boxH <= 0 || desired <= 0) {
      return desired > 0 ? desired : 10;
    }
    final heightLimit = boxH / 1.20;
    const avgGlyphEm = 0.58;
    final widthLimit = boxW / (text.length * avgGlyphEm);
    final fitted = heightLimit < widthLimit ? heightLimit : widthLimit;
    return (fitted < desired ? fitted : desired).clamp(4.0, desired);
  }
}