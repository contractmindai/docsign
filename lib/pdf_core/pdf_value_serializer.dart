import 'lexer.dart';
import 'object_parser.dart';

class PdfValueSerializer {
  static String serialize(dynamic v) {
    if (v == null) return 'null';
    if (v is bool) return v ? 'true' : 'false';

    if (v is int) return v.toString();

    if (v is double) {
      return v == v.roundToDouble()
          ? v.toInt().toString()
          : v.toString();
    }

    if (v is num) return v.toString();

    if (v is PdfRawString) {
      return '(' + _escapeBytes(v.bytes) + ')';
    }

    if (v is String) return v;

    if (v is PdfIndirectReference) {
      return '${v.objectId} ${v.generation} R';
    }

    if (v is List) {
      final buf = StringBuffer('[');
      for (int i = 0; i < v.length; i++) {
        if (i > 0) buf.write(' ');
        buf.write(serialize(v[i]));
      }
      buf.write(']');
      return buf.toString();
    }

    if (v is Map) {
      final buf = StringBuffer('<<');
      v.forEach((k, val) {
        buf.write('\n$k ${serialize(val)}');
      });
      buf.write('\n>>');
      return buf.toString();
    }

    return 'null';
  }

  static String _escapeBytes(List<int> bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      if (b == 0x28 || b == 0x29 || b == 0x5C) {
        buf.write('\\');
        buf.writeCharCode(b);
      } else if (b < 32 || b > 126) {
        buf.write('\\');
        buf.write(b.toRadixString(8).padLeft(3, '0'));
      } else {
        buf.writeCharCode(b);
      }
    }
    return buf.toString();
  }
}