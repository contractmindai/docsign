import 'dart:typed_data';
import 'cs_lexer.dart';

class ToUnicodeCMap {
  final Map<int, String> _forward = {};
  final Map<int, int> _reverse = {};

  String? lookup(int code) => _forward[code];
  int? lookupReverse(int unicodePoint) => _reverse[unicodePoint];

  void _add(int code, String text) {
    if (text.isEmpty) return;
    _forward[code] = text;
    for (final rune in text.runes) {
      _reverse.putIfAbsent(rune, () => code);
    }
  }

  static ToUnicodeCMap parse(Uint8List bytes) {
    final cmap = ToUnicodeCMap();
    final lexer = ContentStreamLexer(bytes);
    final pending = <ContentStreamToken>[];
    String? section;

    while (true) {
      final tok = lexer.nextToken();
      if (tok == null) break;
      if (tok.type == ContentStreamTokenType.operator) {
        final op = tok.value as String;
        if (op == 'beginbfchar') {
          section = 'bfchar'; pending.clear();
        } else if (op == 'endbfchar') {
          _bfChar(cmap, pending); section = null; pending.clear();
        } else if (op == 'beginbfrange') {
          section = 'bfrange'; pending.clear();
        } else if (op == 'endbfrange') {
          _bfRange(cmap, pending); section = null; pending.clear();
        }
      } else if (section != null) {
        pending.add(tok);
      }
    }
    return cmap;
  }

  static void _bfChar(ToUnicodeCMap cmap, List<ContentStreamToken> toks) {
    for (int i = 0; i + 1 < toks.length; i += 2) {
      final src = _hexInt(toks[i]);
      final dst = _hexString(toks[i + 1].value.toString());
      if (src != null && dst != null) cmap._add(src, dst);
    }
  }

  static void _bfRange(ToUnicodeCMap cmap, List<ContentStreamToken> toks) {
    int i = 0;
    while (i + 2 < toks.length) {
      final lo = _hexInt(toks[i]);
      final hi = _hexInt(toks[i + 1]);
      if (lo == null || hi == null) { i++; continue; }
      final dst = toks[i + 2];

      if (dst.type == ContentStreamTokenType.string) {
        final s = _hexString(dst.value.toString());
        if (s != null && s.isNotEmpty) {
          final start = s.runes.first;
          for (int c = lo; c <= hi; c++) {
            cmap._add(c, String.fromCharCode(start + (c - lo)));
          }
        }
      } else if (dst.type == ContentStreamTokenType.array) {
        final arr = dst.value as List<dynamic>;
        for (int j = 0; j < arr.length && lo + j <= hi; j++) {
          final el = arr[j];
          if (el is String) {
            final s = _hexString(el);
            if (s != null && s.isNotEmpty) cmap._add(lo + j, s);
          }
        }
      }
      i += 3;
    }
  }

  static int? _hexInt(ContentStreamToken t) {
    if (t.type != ContentStreamTokenType.string) return null;
    return int.tryParse(t.value.toString(), radix: 16);
  }

  static String? _hexString(String hex) {
    if (hex.isEmpty) return '';
    final padded = hex.length.isOdd ? '${hex}0' : hex;
    final buffer = StringBuffer();
    for (int i = 0; i < padded.length; i += 4) {
      final slice = padded.substring(i, (i + 4).clamp(0, padded.length));
      final code = int.tryParse(slice, radix: 16);
      if (code != null) buffer.writeCharCode(code);
    }
    return buffer.toString();
  }
}