import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

// Conditional dart:io import - only on non-web
import '../utils/web_download.dart';
import 'platform_io_stub.dart'
    if (dart.library.io) 'platform_io_impl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlatformFileService - THE single source of truth for all file operations
//
// Rule: NEVER access PlatformFile.path, File(), or dart:io directly.
// Use this service everywhere instead.
// ─────────────────────────────────────────────────────────────────────────────

class PlatformFileService {

  // In-memory cache: virtual path → bytes (used on web)
  static final _cache = <String, Uint8List>{};

  static void cache(String path, Uint8List bytes) => _cache[path] = bytes;
  static Uint8List? getCached(String path) => _cache[path];
  static void clearCache(String path) => _cache.remove(path);

  // ── Pick files ─────────────────────────────────────────────────────────────

  /// Pick a PDF file. Returns null if cancelled.
  static Future<PickedFile?> pickPdf({String? password}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb,       // web MUST have bytes; mobile uses path
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return _fromPlatformFile(result.files.first);
  }

  /// Pick a document file (docx, txt, etc.)
  static Future<PickedFile?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['qldoc', 'docx', 'doc', 'txt', 'json'],
      withData: kIsWeb,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return _fromPlatformFile(result.files.first);
  }

  /// Pick an image file
  static Future<PickedFile?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: kIsWeb,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return _fromPlatformFile(result.files.first);
  }

  static PickedFile _fromPlatformFile(PlatformFile f) {
    // ✅ On web: use f.bytes, NEVER f.path (throws on web)
    // ✅ On mobile: use f.path, bytes may be null (not loaded)
    final bytes = f.bytes;
    final path  = kIsWeb ? f.name : (f.path ?? f.name);

    if (kIsWeb && bytes != null) {
      _cache[path] = bytes;
    }

    return PickedFile(
      displayName: f.name,
      virtualPath:  path,
      bytes:         bytes,
      nativePath:    kIsWeb ? null : f.path,
    );
  }

  // ── Read file bytes ────────────────────────────────────────────────────────

  /// Read bytes from a file path or virtual path.
  static Future<Uint8List?> readBytes(String path) async {
    // Check cache first (always works on web and mobile)
    final cached = _cache[path];
    if (cached != null) return cached;

    if (kIsWeb) {
      // Web: can only serve from cache
      return null;
    } else {
      // Mobile: read from disk
      return ioReadBytes(path);
    }
  }

  /// Read text from a file.
  static Future<String?> readText(String path) async {
    final bytes = await readBytes(path);
    if (bytes == null) return null;
    try { return String.fromCharCodes(bytes); } catch (_) { return null; }
  }

  // ── Write file bytes ───────────────────────────────────────────────────────

  /// Write bytes to a file.
  /// Web: stores in memory cache. PDF files also trigger browser download.
  /// Mobile: writes to disk.
  static Future<void> writeBytes(String path, Uint8List bytes,
      {bool download = false}) async {
    _cache[path] = bytes; // always cache
    if (kIsWeb) {
      // Auto-download PDFs saved via templates / create PDF
      if (download || path.endsWith('.pdf')) {
        final name = path.contains('/') ? path.split('/').last
            : path.contains('\\') ? path.split('\\').last : path;
        downloadFile(name, bytes);
      }
    } else {
      await ioWriteBytes(path, bytes);
    }
  }

  // ── Generate output path ───────────────────────────────────────────────────

  /// Get a writable output path for a new file.
  static Future<String> outputPath(String filename) async {
    if (kIsWeb) return filename; // virtual path on web
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$filename';
  }

  // ── Check existence ────────────────────────────────────────────────────────

  static bool exists(String path) {
    if (kIsWeb) return _cache.containsKey(path);
    return ioExists(path);
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  static Future<void> delete(String path) async {
    _cache.remove(path);
    if (!kIsWeb) await ioDelete(path);
  }
}

// ── Result types ──────────────────────────────────────────────────────────────

class PickedFile {
  final String displayName;
  final String virtualPath;   // use everywhere as the "path" key
  final Uint8List? bytes;     // available on web, may be null on mobile
  final String? nativePath;   // only on mobile

  const PickedFile({
    required this.displayName,
    required this.virtualPath,
    required this.bytes,
    required this.nativePath,
  });

  bool get hasBytesInMemory => bytes != null;
  bool get hasNativePath => nativePath != null;
}
