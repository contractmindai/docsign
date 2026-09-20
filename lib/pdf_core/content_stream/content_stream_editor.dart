import 'dart:typed_data';
import 'content_stream_analyzer.dart';
import 'font_info.dart';

class FontEncodeException implements Exception {
  final String font;
  final String character;
  FontEncodeException(this.font, this.character);
  @override
  String toString() =>
      'Cannot encode "$character" with font $font (no glyph mapping)';
}

class ContentStreamEditor {
  final Uint8List _bytes;
  final Map<String, FontInfo> _fonts;
  ContentStreamEditor(this._bytes, this._fonts);

  /// Replace the visible text of [run] with [newText].
  ///
  /// Two cases:
  ///
  /// * **Single-operator run** (`run.constituents == null`) — [byteStart,
  ///   byteEnd) covers exactly one Tj/TJ operand+operator, so a direct
  ///   splice is safe.
  ///
  /// * **Merged run** (`run.constituents.length > 1`) — [byteStart, byteEnd)
  ///   spans several Tj/TJ operators *plus every operator sitting between
  ///   them* (colour changes, q/Q, Tm/Td, other graphics). Splicing the whole
  ///   range would silently delete those interstitial operators — including,
  ///   potentially, an unmatched q or Q, which unbalances the graphics-state
  ///   stack and can make a renderer abandon the page entirely.
  ///
  ///   Instead, each constituent is rewritten in place, the bytes *between*
  ///   constituents are copied through verbatim, and [newText] is distributed
  ///   across the constituents proportionally to their original decoded
  ///   length.
  Uint8List replaceRun(TextRun run, String newText,
      {bool preserveWidth = true}) {
    final constituents = run.constituents;

    assert(
      constituents == null ||
          constituents.every((c) => c.constituents == null),
      'constituents must be flat leaves (see ContentStreamAnalyzer._merge)',
    );

    if (constituents == null || constituents.length < 2) {
      final out = BytesBuilder(copy: false);
      out.add(_bytes.sublist(0, run.byteStart));
      out.add(_latin1(_buildReplacement(run, newText, preserveWidth)));
      out.add(_bytes.sublist(run.byteEnd));
      return out.takeBytes();
    }

    // Order by position in the content stream. _merge preserves stream order,
    // but sorting makes the splice robust regardless.
    final sorted = [...constituents]
      ..sort((a, b) => a.byteStart.compareTo(b.byteStart));

    final chunks = _distributeText(sorted, newText);

    final out = BytesBuilder(copy: false);
    int cursor = 0;
    for (int i = 0; i < sorted.length; i++) {
      final c = sorted[i];

      // Copy any interstitial operators untouched. Never delete these:
      // they are what keeps the graphics-state stack balanced.
      if (c.byteStart > cursor) {
        out.add(_bytes.sublist(cursor, c.byteStart));
      }

      final chunk = chunks[i];
      if (chunk.isEmpty) {
        // Keep the operator slot present but empty. This preserves text-matrix
        // bookkeeping for anything downstream that depends on it.
        out.add(_latin1('() Tj'));
      } else {
        out.add(_latin1(_buildReplacement(c, chunk, preserveWidth)));
      }

      if (c.byteEnd > cursor) cursor = c.byteEnd;
    }
    if (cursor < _bytes.length) {
      out.add(_bytes.sublist(cursor));
    }
    return out.takeBytes();
  }

  /// Split [newText] across [parts] proportionally to their original decoded
  /// character counts. The final part absorbs any rounding remainder, so the
  /// concatenation of the result is always exactly [newText].
  ///
  /// Note: the merged run's `text` may contain synthetic spaces inserted by
  /// `_merge`; those are not present in any constituent's `text`, so they get
  /// absorbed into whichever chunk they fall into. For a text-overlay editor
  /// that's the desired behaviour.
  static List<String> _distributeText(List<TextRun> parts, String newText) {
    final out = <String>[];
    if (parts.isEmpty) return out;

    final oldTotal = parts.fold<int>(0, (s, p) => s + p.text.length);
    if (oldTotal <= 0) {
      // Degenerate: no historical lengths to weight by. Give everything to the
      // first constituent and blank the rest.
      out.add(newText);
      for (int i = 1; i < parts.length; i++) {
        out.add('');
      }
      return out;
    }

    int consumed = 0;
    for (int i = 0; i < parts.length - 1; i++) {
      final share =
          ((newText.length * parts[i].text.length) / oldTotal).round();
      final end = (consumed + share).clamp(consumed, newText.length).toInt();
      out.add(newText.substring(consumed, end));
      consumed = end;
    }
    out.add(newText.substring(consumed));
    return out;
  }

  String _buildReplacement(TextRun run, String newText, bool preserveWidth) {
    final info = _fonts[run.fontRef];
    if (info == null) throw FontEncodeException(run.fontRef, '(unknown font)');

    final encoded = info.encode(newText);
    if (encoded == null) {
      String missing = '?';
      for (final r in newText.runes) {
        if (info.cmap?.lookupReverse(r) == null &&
            !(info.isSimpleWinAnsi && r < 256)) {
          missing = String.fromCharCode(r);
          break;
        }
      }
      throw FontEncodeException(run.fontRef, missing);
    }

    final escaped = _escapeLiteral(encoded.toList());
    final newWidthEm = info.widthEm(encoded.toList());

    final kern = run.kerning;
    if (kern != null &&
        kern.isNotEmpty &&
        run.widthEm > 0 &&
        (newText.length - run.text.length).abs() <=
            (run.text.length * 0.5).ceil() + 2) {
      return _buildTJReplacement(run, encoded, kern, newWidthEm, preserveWidth);
    }
    return _buildTjReplacement(run, escaped, newWidthEm, preserveWidth);
  }

  String _buildTjReplacement(TextRun run, String escaped, double newWidthEm,
      bool preserveWidth) {
    if (preserveWidth && run.widthEm > 0 && newWidthEm > 0) {
      final ratio = run.widthEm / newWidthEm;
      final scaled = (run.originalHz * ratio).round().clamp(20, 400);
      if ((scaled - run.originalHz).abs() >= 1) {
        final reset = run.originalHz.round();
        return '$scaled Tz ($escaped) Tj $reset Tz';
      }
    }
    return '($escaped) Tj';
  }

  String _buildTJReplacement(TextRun run, Uint8List encoded,
      List<KernPair> kern, double newWidthEm, bool preserveWidth) {
    final info = _fonts[run.fontRef]!;
    final decodedNew = info.decode(encoded.toList());
    final oldLen = run.text.length;
    final newLen = decodedNew.length;
    final entries = <({int at, double adj})>[];

    for (final k in kern) {
      if (oldLen <= 0) continue;
      final scaled = ((k.charIndex * newLen) / oldLen).round();
      if (scaled <= 0 || scaled >= newLen) continue;
      entries.add((at: scaled, adj: k.adjustment));
    }
    entries.sort((a, b) => a.at.compareTo(b.at));

    final buffer = StringBuffer('[');
    int cursor = 0;
    for (final e in entries) {
      final chunk = decodedNew.substring(cursor, e.at);
      final chunkBytes = info.encode(chunk);
      if (chunkBytes == null) {
        return '(${_escapeLiteral(encoded.toList())}) Tj';
      }
      buffer.write('(${_escapeLiteral(chunkBytes.toList())})');
      buffer.write(' ${_fmt(e.adj)} ');
      cursor = e.at;
    }
    final tail = decodedNew.substring(cursor);
    final tailBytes = info.encode(tail);
    if (tailBytes == null) {
      return '(${_escapeLiteral(encoded.toList())}) Tj';
    }
    buffer.write('(${_escapeLiteral(tailBytes.toList())})]');

    if (preserveWidth && run.widthEm > 0 && newWidthEm > 0) {
      final ratio = run.widthEm / newWidthEm;
      final scaled = (run.originalHz * ratio).round().clamp(20, 400);
      if ((scaled - run.originalHz).abs() >= 1) {
        final reset = run.originalHz.round();
        return '$scaled Tz ${buffer.toString()} TJ $reset Tz';
      }
    }
    return '${buffer.toString()} TJ';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  static Uint8List _latin1(String s) {
    final out = Uint8List(s.length);
    for (int i = 0; i < s.length; i++) out[i] = s.codeUnitAt(i) & 0xFF;
    return out;
  }

  static String _escapeLiteral(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      if (b == 0x28 || b == 0x29 || b == 0x5C) {
        buffer.write('\\');
        buffer.writeCharCode(b);
      } else if (b < 32 || b > 126) {
        buffer.write('\\');
        buffer.write(b.toRadixString(8).padLeft(3, '0'));
      } else {
        buffer.writeCharCode(b);
      }
    }
    return buffer.toString();
  }
}