import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/web_download.dart';
import 'platform_io_stub.dart'
    if (dart.library.io) 'platform_io_impl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlatformFileService - THE single source of truth for all file operations
//
// Performance notes:
// - On mobile: NO in‑memory caching of file bytes (rely on disk)
// - On web: bounded LRU cache (max 5 files or 200 MB total)
// ─────────────────────────────────────────────────────────────────────────────

class PlatformFileService {
  // Web‑only cache with size limits
  static final Map<String, Uint8List> _webCache = {};
  static int _webCacheTotalBytes = 0;
  static const int _maxWebCacheBytes = 200 * 1024 * 1024; // 200 MB
  static const int _maxWebCacheEntries = 5;

  static void _addToWebCache(String path, Uint8List bytes) {
    if (!kIsWeb) return;
    
    // Remove oldest if needed (using insertion order – LinkedHashMap not needed,
    // but we'll evict by oldest key; simple approach: remove first key)
    while (_webCache.length >= _maxWebCacheEntries ||
           _webCacheTotalBytes + bytes.length > _maxWebCacheBytes) {
      if (_webCache.isEmpty) break;
      final oldestKey = _webCache.keys.first;
      final oldBytes = _webCache.remove(oldestKey)!;
      _webCacheTotalBytes -= oldBytes.length;
    }
    _webCache[path] = bytes;
    _webCacheTotalBytes += bytes.length;
  }

  static void cache(String path, Uint8List bytes) {
    if (kIsWeb) {
      _addToWebCache(path, bytes);
    }
    // On mobile: do nothing – no in‑memory cache
  }

  static Uint8List? getCached(String path) {
    if (kIsWeb) return _webCache[path];
    return null; // no caching on mobile
  }

  static void clearCache(String path) {
    if (kIsWeb) {
      final bytes = _webCache.remove(path);
      if (bytes != null) _webCacheTotalBytes -= bytes.length;
    }
  }

  // ── Pick files ─────────────────────────────────────────────────────────────

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
    final bytes = f.bytes;
    final path = kIsWeb ? f.name : (f.path ?? f.name);

    if (kIsWeb && bytes != null) {
      _addToWebCache(path, bytes);
    }

    return PickedFile(
      displayName: f.name,
      virtualPath: path,
      bytes: bytes,
      nativePath: kIsWeb ? null : f.path,
    );
  }

  // ── Read file bytes ────────────────────────────────────────────────────────

  static Future<Uint8List?> readBytes(String path) async {
    if (kIsWeb) {
      // Web: only from cache (no disk access)
      return _webCache[path];
    } else {
      // Mobile: always read from disk, ignore cache
      return await ioReadBytes(path);
    }
  }

  static Future<String?> readText(String path) async {
    final bytes = await readBytes(path);
    if (bytes == null) return null;
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }

  // ── Write file bytes ───────────────────────────────────────────────────────

  static Future<void> writeBytes(String path, Uint8List bytes,
      {bool download = false}) async {
    if (kIsWeb) {
      _addToWebCache(path, bytes);
      if (download || path.endsWith('.pdf')) {
        final name = path.contains('/') ? path.split('/').last
            : path.contains('\\') ? path.split('\\').last : path;
        downloadFile(name, bytes);
      }
    } else {
      // Mobile: write to disk, do NOT cache in memory
      await ioWriteBytes(path, bytes);
    }
  }

  // ── Generate output path ───────────────────────────────────────────────────

  static Future<String> outputPath(String filename) async {
    if (kIsWeb) return filename;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$filename';
  }

  // ── Check existence ────────────────────────────────────────────────────────

  static bool exists(String path) {
    if (kIsWeb) return _webCache.containsKey(path);
    return ioExists(path);
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  static Future<void> delete(String path) async {
    if (kIsWeb) {
      final bytes = _webCache.remove(path);
      if (bytes != null) _webCacheTotalBytes -= bytes.length;
    } else {
      await ioDelete(path);
    }
  }
}

// ── Result types ──────────────────────────────────────────────────────────────

class PickedFile {
  final String displayName;
  final String virtualPath;
  final Uint8List? bytes;
  final String? nativePath;

  const PickedFile({
    required this.displayName,
    required this.virtualPath,
    required this.bytes,
    required this.nativePath,
  });

  bool get hasBytesInMemory => bytes != null;
  bool get hasNativePath => nativePath != null;
}