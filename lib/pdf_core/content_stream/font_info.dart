import 'dart:typed_data';
import 'cmap_parser.dart';
import 'glyph_names.dart';
import '../object_parser.dart';

class FontInfo {
  final Map<int, int> widths;
  final int defaultWidth;
  final ToUnicodeCMap? cmap;
  final int codeBytes;
  final bool isSimpleWinAnsi;

  /// Byte code → Unicode character, derived from the font's
  /// `/Encoding /Differences` array. This is what makes non-standard
  /// encodings — where a byte like 0x61 draws the digit "0" instead of "a" —
  /// decode correctly.
  ///
  /// `/ToUnicode` (when present) always wins over this map; differences are
  /// the second-priority source. The ASCII fallback is the last resort.
  final Map<int, String>? _differences;

  /// Reverse of [_differences]: Unicode character → byte code. Used when
  /// re-encoding a replacement string into the font's own encoding.
  final Map<String, int>? _reverseDifferences;

  FontInfo({
    required this.widths,
    required this.defaultWidth,
    this.cmap,
    this.codeBytes = 1,
    this.isSimpleWinAnsi = false,
    Map<int, String>? differences,
  })  : _differences = differences,
        _reverseDifferences = differences == null
            ? null
            : {
                // First-writer wins so a later entry doesn't clobber an
                // earlier, more specific mapping for the same character.
                for (final e in differences.entries)
                  if (!differences.values.take(0).contains(e.value))
                    e.value: e.key,
              };

  int widthOf(int code) => widths[code] ?? defaultWidth;

  double widthEm(List<int> bytes) {
    double total = 0;
    if (codeBytes == 1) {
      for (final b in bytes) total += widthOf(b) / 1000.0;
    } else {
      for (int i = 0; i + 1 < bytes.length; i += 2) {
        total += widthOf((bytes[i] << 8) | bytes[i + 1]) / 1000.0;
      }
    }
    return total;
  }

  /// Byte stream → text. Priority order:
  ///   1. `/ToUnicode` CMap
  ///   2. `/Encoding /Differences`
  ///   3. ASCII fallback (`String.fromCharCode`)
  String decode(List<int> bytes) {
    final buffer = StringBuffer();
    if (codeBytes == 1) {
      for (final b in bytes) {
        final ch = cmap?.lookup(b) ?? _differences?[b];
        buffer.write(ch ?? String.fromCharCode(b));
      }
    } else {
      for (int i = 0; i + 1 < bytes.length; i += 2) {
        final code = (bytes[i] << 8) | bytes[i + 1];
        final ch = cmap?.lookup(code) ?? _differences?[code];
        if (ch != null) buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// Text → byte stream. Priority order:
  ///   1. Reverse `/ToUnicode` CMap
  ///   2. Reverse `/Encoding /Differences`
  ///   3. Raw code-unit fallback (only for simple WinAnsi fonts)
  ///
  /// Returns null if any character in [text] has no representation in this
  /// font. The caller is expected to raise a user-visible error rather than
  /// silently emit garbage.
  Uint8List? encode(String text) {
    final out = <int>[];
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);

      int? code = cmap?.lookupReverse(rune);
      code ??= _reverseDifferences?[ch];

      // Only fall back to raw code units when the font is a simple WinAnsi
      // encoding AND the rune fits in a single byte. Anything else is a
      // missing glyph — bail out so the caller can warn the user.
      if (code == null) {
        if (isSimpleWinAnsi && codeBytes == 1 && rune < 256) {
          code = rune;
        } else {
          return null;
        }
      }

      if (codeBytes == 1) {
        out.add(code & 0xFF);
      } else {
        out.add((code >> 8) & 0xFF);
        out.add(code & 0xFF);
      }
    }
    return Uint8List.fromList(out);
  }

  static FontInfo fromFontDict(
    Map<String, dynamic> fontDict,
    dynamic Function(PdfIndirectReference) resolve,
  ) {
    final subtype = fontDict['/Subtype']?.toString() ?? '';
    final isComposite = subtype == '/Type0';
    final widths = <int, int>{};
    int defaultWidth = 500;

    if (!isComposite) {
      final firstChar = _int(fontDict['/FirstChar']);
      final wList = fontDict['/Widths'];
      if (firstChar != null && wList is List) {
        for (int i = 0; i < wList.length; i++) {
          final w = wList[i];
          if (w is num) widths[firstChar + i] = w.toInt();
        }
      }
      dynamic fd = fontDict['/FontDescriptor'];
      if (fd is PdfIndirectReference) fd = resolve(fd);
      if (fd is Map<String, dynamic>) {
        defaultWidth = _int(fd['/MissingWidth']) ?? defaultWidth;
      }
    } else {
      dynamic desc = fontDict['/DescendantFonts'];
      if (desc is PdfIndirectReference) desc = resolve(desc);
      if (desc is List && desc.isNotEmpty) {
        dynamic df = desc[0];
        if (df is PdfIndirectReference) df = resolve(df);
        if (df is Map<String, dynamic>) {
          defaultWidth = _int(df['/DW']) ?? 1000;
          _parseWArray(df['/W'], widths);
        }
      } else {
        defaultWidth = 1000;
      }
    }

    // ── Encoding ─────────────────────────────────────────────────────────
    //
    // A font's /Encoding is one of:
    //   * a name like /WinAnsiEncoding                → no differences
    //   * a dict with /BaseEncoding and /Differences  → parse differences
    //   * an indirect ref to either of the above      → resolve first
    final encodingRaw = fontDict['/Encoding'];
    final differences = _parseEncodingDifferences(encodingRaw, resolve);

    // A font is "simple WinAnsi" when it's a simple (non-composite) font with
    // no differences and either a WinAnsi base encoding or no encoding at all.
    // Differences always disqualify the ASCII fallback, because the byte
    // values no longer follow the WinAnsi standard.
    final baseEncodingName = _baseEncodingName(encodingRaw, resolve);
    final isWinAnsi = !isComposite &&
        (differences == null || differences.isEmpty) &&
        (encodingRaw == null ||
            baseEncodingName == '/WinAnsiEncoding' ||
            baseEncodingName == '/StandardEncoding' ||
            baseEncodingName == null);

    return FontInfo(
      widths: widths,
      defaultWidth: defaultWidth,
      codeBytes: isComposite ? 2 : 1,
      isSimpleWinAnsi: isWinAnsi,
      differences: differences,
    );
  }

  /// Returns the `/BaseEncoding` name of [encodingRaw] (resolving an indirect
  /// reference if needed), or null when there's no explicit base encoding.
  static String? _baseEncodingName(
    dynamic encodingRaw,
    dynamic Function(PdfIndirectReference) resolve,
  ) {
    dynamic enc = encodingRaw;
    if (enc is PdfIndirectReference) enc = resolve(enc);

    if (enc is String) {
      return enc.startsWith('/') ? enc : '/$enc';
    }
    if (enc is Map) {
      final base = enc['/BaseEncoding'];
      if (base is String) {
        return base.startsWith('/') ? base : '/$base';
      }
    }
    return null;
  }

  /// Parses a font's `/Encoding` entry, returning the effective byte-code →
  /// Unicode map from its `/Differences` array.
  ///
  /// Returns null when there are no differences to apply.
  static Map<int, String>? _parseEncodingDifferences(
    dynamic encodingRaw,
    dynamic Function(PdfIndirectReference) resolve,
  ) {
    dynamic enc = encodingRaw;
    if (enc is PdfIndirectReference) enc = resolve(enc);
    if (enc is! Map) return null;

    final diffs = enc['/Differences'];
    if (diffs is! List) return null;

    final out = <int, String>{};
    int currentCode = 0;

    for (final entry in diffs) {
      if (entry is num) {
        currentCode = entry.toInt();
      } else if (entry is String) {
        final name = entry.startsWith('/') ? entry.substring(1) : entry;
        final ch = kAdobeGlyphToUnicode[name];
        if (ch != null && ch.isNotEmpty) {
          out[currentCode] = ch;
        }
        // Advance the code regardless of whether we recognised the glyph
        // name — the PDF spec says /Differences entries are consumed
        // positionally, and skipping unnamed glyphs would desync every
        // subsequent mapping.
        currentCode++;
      }
    }

    return out.isEmpty ? null : out;
  }

  static void _parseWArray(dynamic w, Map<int, int> out) {
    if (w is! List) return;
    int i = 0;
    while (i < w.length) {
      final c1 = w[i];
      if (c1 is! num) {
        i++;
        continue;
      }
      if (i + 1 >= w.length) break;
      final next = w[i + 1];
      if (next is List) {
        for (int j = 0; j < next.length; j++) {
          final wv = next[j];
          if (wv is num) out[c1.toInt() + j] = wv.toInt();
        }
        i += 2;
      } else if (next is num) {
        if (i + 2 >= w.length) break;
        final wv = w[i + 2];
        if (wv is num) {
          for (int c = c1.toInt(); c <= next.toInt(); c++) {
            out[c] = wv.toInt();
          }
        }
        i += 3;
      } else {
        i++;
      }
    }
  }

  static int? _int(dynamic v) => v is num ? v.toInt() : null;
}