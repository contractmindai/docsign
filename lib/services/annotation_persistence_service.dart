import 'dart:convert';
import 'dart:typed_data';

import '../models/annotation.dart';
import '../utils/platform_file_service.dart';

class AnnotationSnapshot {
  final Map<int, List<RectAnnotation>>   rects;
  final Map<int, InkAnnotation?>         ink;
  final Map<int, List<StickyNote>>       notes;
  final Map<int, List<TextStamp>>        stamps;
  final Map<int, List<RedactionRect>>    redactions;
  final Map<int, List<ClauseBookmark>>   bookmarks;
  final Map<int, List<TextEditAnnotation>> textEdits; // ✅ Added

  const AnnotationSnapshot({
    required this.rects,  required this.ink,       required this.notes,
    required this.stamps, required this.redactions, required this.bookmarks,
    required this.textEdits, // ✅ Added
  });

  bool get isEmpty =>
      rects.isEmpty && ink.isEmpty && notes.isEmpty &&
      stamps.isEmpty && redactions.isEmpty && bookmarks.isEmpty &&
      textEdits.isEmpty; // ✅ Added
}

class AnnotationPersistenceService {

  static String _sidecarPath(String pdfPath) {
    final base = pdfPath.contains('.')
        ? pdfPath.substring(0, pdfPath.lastIndexOf('.'))
        : pdfPath;
    return '$base.annotations.json';
  }

  static Future<void> save({
    required String pdfPath,
    required Map<int, List<RectAnnotation>>   rects,
    required Map<int, InkAnnotation>          ink,
    required Map<int, List<StickyNote>>       notes,
    required Map<int, List<TextStamp>>        stamps,
    required Map<int, List<RedactionRect>>    redactions,
    required Map<int, List<ClauseBookmark>>   bookmarks,
    required Map<int, List<TextEditAnnotation>> textEdits, // ✅ Added
  }) async {
    try {
      final data = jsonEncode({
        'rects':      rects.map((k, v) => MapEntry(k.toString(), v.map((r) => r.toJson()).toList())),
        'ink':        ink.map((k, v) => MapEntry(k.toString(), v.toJson())),
        'notes':      notes.map((k, v) => MapEntry(k.toString(), v.map((n) => n.toJson()).toList())),
        'stamps':     stamps.map((k, v) => MapEntry(k.toString(), v.map((s) => s.toJson()).toList())),
        'redactions': redactions.map((k, v) => MapEntry(k.toString(), v.map((r) => r.toJson()).toList())),
        'bookmarks':  bookmarks.map((k, v) => MapEntry(k.toString(), v.map((b) => b.toJson()).toList())),
        'textEdits':  textEdits.map((k, v) => MapEntry(k.toString(), v.map((t) => t.toJson()).toList())), // ✅ Added
      });
      final path  = _sidecarPath(pdfPath);
      await PlatformFileService.writeBytes(path, Uint8List.fromList(data.codeUnits));
    } catch (_) {}
  }

  static Future<AnnotationSnapshot?> load(String pdfPath) async {
    try {
      final path  = _sidecarPath(pdfPath);
      final bytes = await PlatformFileService.readBytes(path);
      if (bytes == null || bytes.isEmpty) return null;

      final raw  = String.fromCharCodes(bytes);
      final data = jsonDecode(raw) as Map<String, dynamic>;

      Map<int, List<T>> _parseList<T>(
          String key, T Function(Map<String, dynamic>) fromJson) =>
          (data[key] as Map<String, dynamic>? ?? {}).map((k, v) =>
              MapEntry(int.parse(k),
                  (v as List).map((e) => fromJson(e as Map<String, dynamic>)).toList()));

      final rects = _parseList('rects', RectAnnotation.fromJson);
      final notes = _parseList('notes', StickyNote.fromJson);
      final stamps = _parseList('stamps', TextStamp.fromJson);
      final redactions = _parseList('redactions', RedactionRect.fromJson);
      final bookmarks = _parseList('bookmarks', ClauseBookmark.fromJson);
      final textEdits = _parseList('textEdits', TextEditAnnotation.fromJson); // ✅ Added

      final inkRaw = data['ink'] as Map<String, dynamic>? ?? {};
      final ink    = inkRaw.map((k, v) =>
          MapEntry(int.parse(k),
              InkAnnotation.fromJson(v as Map<String, dynamic>) as InkAnnotation?));

      return AnnotationSnapshot(
          rects: rects, ink: ink, notes: notes,
          stamps: stamps, redactions: redactions, bookmarks: bookmarks,
          textEdits: textEdits); // ✅ Added
    } catch (_) { return null; }
  }
}