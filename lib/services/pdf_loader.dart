import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdfrx/pdfrx.dart';

import '../utils/platform_file_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PdfLoader — unified PDF loading for web + mobile
// ─────────────────────────────────────────────────────────────────────────────

class PdfLoader {

  /// Pick + open a PDF from device. Returns null if cancelled.
  static Future<PdfFileResult?> pick({String? password}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    // ✅ NEVER access file.path on web
    final bytes = file.bytes;
    final path  = kIsWeb ? file.name : (file.path ?? file.name);
    if (kIsWeb && bytes != null) PlatformFileService.cache(path, bytes);

    return _openInternal(
        path: kIsWeb ? null : file.path,
        bytes: bytes, name: file.name, password: password);
  }

  static Future<PdfFileResult> _openInternal({
    String? path, Uint8List? bytes,
    required String name, String? password,
  }) async {
    final PdfPasswordProvider? pwProvider = _makePwProvider(password);
    late PdfDocument doc;
    if (kIsWeb) {
      if (bytes == null) throw Exception('No bytes on web');
      doc = await PdfDocument.openData(bytes,
          sourceName: name, passwordProvider: pwProvider);
    } else {
      if (path == null) throw Exception('No path on mobile');
      doc = await PdfDocument.openFile(path, passwordProvider: pwProvider);
    }
    return PdfFileResult(displayPath: path ?? name, bytes: bytes, document: doc);
  }

  /// Open for viewing — used by PdfViewerScreen.
  static Future<PdfDocument> openForViewing({
    required String path,
    Uint8List? bytes,
    String? password,
  }) async {
    final PdfPasswordProvider? pwProvider = _makePwProvider(password);
    if (kIsWeb) {
      final b = bytes ?? PlatformFileService.getCached(path);
      if (b == null) throw Exception('No bytes for: $path — open from home screen first');
      return PdfDocument.openData(b,
          sourceName: path.split('/').last.split('\\').last,
          passwordProvider: pwProvider);
    } else {
      return PdfDocument.openFile(path, passwordProvider: pwProvider);
    }
  }

  /// ✅ Correct PdfPasswordProvider signature for pdfrx 1.3.x
  /// Type must be: FutureOr<String?> Function(PdfPasswordException?)?
  static PdfPasswordProvider? _makePwProvider(String? password) {
    if (password == null || password.isEmpty) return null;
    // Explicit type annotation satisfies Dart's type checker
    final PdfPasswordProvider provider =
        () async => password;
    return provider;
  }

  static Uint8List? getCached(String path) =>
      PlatformFileService.getCached(path);
}

class PdfFileResult {
  final String displayPath;
  final Uint8List? bytes;
  final PdfDocument document;
  const PdfFileResult({
      required this.displayPath, required this.document, this.bytes});
}
