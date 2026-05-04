import '../models/annotation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExpiryDetector
//
// Scans raw PDF text (extracted by the caller from pdfx) for date strings
// near keywords like "expires", "valid until", "termination date", etc.
// Returns a list of ExpiryDate objects sorted by proximity to today.
// ─────────────────────────────────────────────────────────────────────────────

class ExpiryDetector {
  static const _kKeywords = [
    'expires', 'expiration', 'expiry', 'valid until', 'valid through',
    'termination date', 'end date', 'effective through', 'term ends',
    'renewal date', 'due date', 'deadline',
  ];

  // Matches: 01/15/2026  |  01-15-2026  |  January 15, 2026  |  2026-01-15
  static final _datePattern = RegExp(
    r'(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2,4})'          // MM/DD/YY(YY)
    r'|'
    r'(January|February|March|April|May|June|July|August|'
    r'September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})'
    r'|'
    r'(\d{4})[\/\-](\d{2})[\/\-](\d{2})',                     // YYYY-MM-DD
    caseSensitive: false,
  );

  static List<ExpiryDate> detect(String pageText, int pageIndex) {
    final lower = pageText.toLowerCase();
    final results = <ExpiryDate>[];
    final seen = <String>{};

    for (final keyword in _kKeywords) {
      int pos = 0;
      while (true) {
        final idx = lower.indexOf(keyword, pos);
        if (idx == -1) break;
        pos = idx + 1;

        // Look for a date within 120 characters after the keyword
        final window = pageText.substring(
          idx,
          (idx + 120).clamp(0, pageText.length),
        );

        final match = _datePattern.firstMatch(window);
        if (match == null) continue;

        final raw = match.group(0)!;
        if (seen.contains(raw)) continue;
        seen.add(raw);

        results.add(ExpiryDate(
          rawText: raw,
          parsed: _parseDate(match),
          pageIndex: pageIndex,
        ));
      }
    }

    // Sort: soonest future date first, then past dates, nulls last
    final now = DateTime.now();
    results.sort((a, b) {
      final pa = a.parsed, pb = b.parsed;
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1;
      if (pb == null) return -1;
      // Future dates sort before past dates
      final aFuture = pa.isAfter(now);
      final bFuture = pb.isAfter(now);
      if (aFuture != bFuture) return aFuture ? -1 : 1;
      return pa.compareTo(pb);
    });

    return results;
  }

  static DateTime? _parseDate(RegExpMatch m) {
    try {
      // YYYY-MM-DD group (groups 8,9,10)
      if (m.group(8) != null) {
        return DateTime(
          int.parse(m.group(8)!),
          int.parse(m.group(9)!),
          int.parse(m.group(10)!),
        );
      }
      // Month DD, YYYY group (groups 4,5,6)
      if (m.group(4) != null) {
        return DateTime(
          int.parse(m.group(6)!),
          _monthNum(m.group(4)!),
          int.parse(m.group(5)!),
        );
      }
      // MM/DD/YY(YY) group (groups 1,2,3)
      if (m.group(1) != null) {
        int year = int.parse(m.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, int.parse(m.group(1)!), int.parse(m.group(2)!));
      }
    } catch (_) {}
    return null;
  }

  static int _monthNum(String name) {
    const months = [
      'january','february','march','april','may','june',
      'july','august','september','october','november','december',
    ];
    return months.indexWhere((m) => name.toLowerCase().startsWith(m)) + 1;
  }

  /// Days until expiry (negative = already expired).
  static int? daysUntil(ExpiryDate e) {
    if (e.parsed == null) return null;
    return e.parsed!.difference(DateTime.now()).inDays;
  }

  /// Returns a human-readable urgency label.
  static String urgencyLabel(ExpiryDate e) {
    final days = daysUntil(e);
    if (days == null) return 'Unknown date';
    if (days < 0)   return 'Expired ${(-days)} day${(-days)==1?'':'s'} ago';
    if (days == 0)  return 'Expires TODAY';
    if (days <= 7)  return 'Expires in $days day${days==1?'':'s'} ⚠️';
    if (days <= 30) return 'Expires in $days days';
    return 'Expires ${e.rawText}';
  }
}
