import 'object_parser.dart';

/// Deep-merges two resource dictionaries. Sub-dicts that PDF treats as
/// namespaces (`/Font`, `/XObject`, `/ExtGState`, …) are combined key-by-key;
/// every other key is copied through, with `overlay` winning on collision.
///
/// Use this when you need to add a `/Helv` font entry or a signature image
/// XObject to a page that already declares its own resources.
Map<String, dynamic> mergeResourceDicts(
  Map<String, dynamic> base,
  Map<String, dynamic> overlay,
) {
  final out = Map<String, dynamic>.from(base);

  for (final entry in overlay.entries) {
    final key = entry.key;
    final value = entry.value;

    const subDictKeys = {
      '/Font',
      '/XObject',
      '/ExtGState',
      '/ColorSpace',
      '/Pattern',
      '/Shading',
      '/Properties',
    };

    if (subDictKeys.contains(key) && value is Map<String, dynamic>) {
      final existing = out[key];
      if (existing is Map<String, dynamic>) {
        out[key] = <String, dynamic>{...existing, ...value};
      } else if (existing is PdfIndirectReference) {
        // Rare but legal: /Font may be an indirect ref. Caller must resolve
        // before passing to us, otherwise we can't merge and just overwrite.
        out[key] = value;
      } else {
        out[key] = value;
      }
    } else {
      out[key] = value;
    }
  }

  return out;
}

/// Returns the new `/Contents` value (a pre-serialized string) after
/// appending [newStreamId] to whatever [existing] currently is.
///
/// PDF permits `/Contents` to be either a single indirect ref or an array
/// of indirect refs; this normalises to an array when appending.
String appendContentsRef(dynamic existing, int newStreamId, int newGen) {
  final newRef = '$newStreamId $newGen R';

  if (existing == null) return '[$newRef]';

  if (existing is PdfIndirectReference) {
    return '[${existing.objectId} ${existing.generation} R $newRef]';
  }

  if (existing is List) {
    final parts = existing.map((e) {
      if (e is PdfIndirectReference) return '${e.objectId} ${e.generation} R';
      return e.toString();
    }).join(' ');
    return '[$parts $newRef]';
  }

  return '[$newRef]';
}