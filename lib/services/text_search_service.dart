import 'dart:convert';
import 'dart:typed_data';

import '../utils/platform_file_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TextSearchService — BT/ET text extraction from raw PDF bytes
// 100% pure Dart — works on web and mobile (no dart:io)
// ─────────────────────────────────────────────────────────────────────────────

class SearchMatch {
  final int    pageIndex;
  final String matchText;
  final String context;
  final double approxNormY;
  const SearchMatch({required this.pageIndex, required this.matchText,
      required this.context, required this.approxNormY});
}

class TextSearchService {

  static Future<List<SearchMatch>> search({
    required String pdfPath,
    required String query,
    Uint8List? bytes,
  }) async {
    if (query.trim().isEmpty) return [];
    try {
      final raw = bytes ?? await PlatformFileService.readBytes(pdfPath);
      if (raw == null || raw.isEmpty) return [];
      final text    = latin1.decode(raw, allowInvalid: true);
      final pages   = _extractPages(_stripBinary(text));
      final results = <SearchMatch>[];
      final q       = query.toLowerCase();
      pages.forEach((pageIdx, pageText) {
        final lower = pageText.toLowerCase();
        int pos = 0;
        while (true) {
          final idx = lower.indexOf(q, pos);
          if (idx < 0) break;
          results.add(SearchMatch(
            pageIndex:   pageIdx,
            matchText:   pageText.substring(idx, idx + q.length),
            context:     _ctx(pageText, idx, 40),
            approxNormY: (idx / pageText.length).clamp(0.0, 1.0),
          ));
          pos = idx + 1;
          if (results.length > 200) break;
        }
        if (results.length > 200) return;
      });
      return results;
    } catch (_) { return []; }
  }

  static Future<Map<int, String>> extractAllText(String pdfPath,
      {Uint8List? bytes}) async {
    try {
      final raw = bytes ?? await PlatformFileService.readBytes(pdfPath);
      if (raw == null || raw.isEmpty) return {};
      final text = latin1.decode(raw, allowInvalid: true);
      return _extractPages(_stripBinary(text));
    } catch (_) { return {}; }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static String _stripBinary(String text) {
    // Remove binary stream data
    return text.replaceAll(
        RegExp(r'stream[\s\S]*?endstream', multiLine: true), ' ');
  }

  static Map<int, String> _extractPages(String stripped) {
    final result = <int, String>{};
    // Split by PDF page markers
    final pages = stripped.split(RegExp(r'/Type\s*/Page\b'));
    for (int i = 0; i < pages.length - 1; i++) {
      final page = pages[i + 1];
      // Extract text between BT and ET operators
      final btMatches = RegExp(r'BT\s*([\s\S]*?)\s*ET').allMatches(page);
      final buf = StringBuffer();
      for (final m in btMatches) {
        // Extract string content from Tj, TJ, ' operators
        final block = m.group(1) ?? '';
        // Extract strings in parentheses
        for (final s in RegExp(r'\(([^)]*)\)').allMatches(block)) {
          buf.write(s.group(1) ?? '');
          buf.write(' ');
        }
        // Extract hex strings
        for (final s in RegExp(r'<([0-9a-fA-F]+)>').allMatches(block)) {
          try {
            final hex = s.group(1)!;
            for (int j = 0; j < hex.length - 1; j += 2) {
              final code = int.parse(hex.substring(j, j + 2), radix: 16);
              if (code >= 32 && code < 127) buf.writeCharCode(code);
            }
            buf.write(' ');
          } catch (_) {}
        }
      }
      final t = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) result[i] = t;
    }
    return result;
  }

  static String _ctx(String text, int idx, int window) {
    final s = (idx - window).clamp(0, text.length);
    final e = (idx + window).clamp(0, text.length);
    return '${s > 0 ? "…" : ""}${text.substring(s, e)}${e < text.length ? "…" : ""}';
  }
}
