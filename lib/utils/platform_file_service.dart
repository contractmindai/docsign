import 'dart:typed_data';
// NOTE: `dart:io` is imported unconditionally for `io.File` and `io.Platform`.
// Every `io.*` reference in this file is guarded by a `kIsWeb` check. If you
// add new `io.*` calls, keep them behind the same guard — an unguarded call
// throws `UnsupportedError` on web at runtime and is hard to trace.
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/widgets.dart'
    show BuildContext, MediaQuery, Rect, Overlay;
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/web_download.dart';
import 'platform_io_stub.dart'
    if (dart.library.io) 'platform_io_impl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlatformFileService — THE single source of truth for all file operations
//
// Performance notes:
// - On mobile: NO in-memory caching of file bytes (rely on disk).
// - On web:    bounded LRU cache (max 5 files or 200 MB total).
// ─────────────────────────────────────────────────────────────────────────────

class PlatformFileService {
  // ── Web-only LRU cache ─────────────────────────────────────────────────
  static final Map<String, Uint8List> _webCache = {};
  static int _webCacheTotalBytes = 0;
  static const int _maxWebCacheBytes = 200 * 1024 * 1024; // 200 MB
  static const int _maxWebCacheEntries = 5;

  /// Insert [bytes] into the LRU, evicting as needed.
  ///
  /// If [path] already exists, its old bytes are subtracted before the new
  /// ones are added — this prevents the running total from drifting upward
  /// across re-saves of the same filename (a bug in the previous version
  /// that caused legitimate entries to be dropped after a few edits).
  static void _addToWebCache(String path, Uint8List bytes) {
    if (!kIsWeb) return;

    // Remove any existing entry for this path first, subtracting its size.
    final existing = _webCache.remove(path);
    if (existing != null) {
      _webCacheTotalBytes -= existing.length;
    }

    // Evict oldest entries until we fit both limits.
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
    // On mobile: do nothing — no in-memory cache.
  }

  /// Look up a cached entry. On web, a hit is promoted to the tail of the
  /// insertion order so the map behaves as an actual LRU rather than FIFO.
  static Uint8List? getCached(String path) {
    if (!kIsWeb) return null;
    final v = _webCache.remove(path);
    if (v == null) return null;
    // Re-insert at the tail (Dart's Map is insertion-ordered).
    _webCache[path] = v;
    return v;
  }

  // ── Pick files ─────────────────────────────────────────────────────────

  static Future<PickedFile?> pickPdf({String? password}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb, // web MUST have bytes; mobile uses path
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

  // ── Read file bytes ────────────────────────────────────────────────────

  static Future<Uint8List?> readBytes(String path) async {
    if (kIsWeb) {
      // Web: only from cache (no disk access).
      return getCached(path);
    }
    // Mobile: always read from disk, ignore cache.
    return await ioReadBytes(path);
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

  // ── Write file bytes ───────────────────────────────────────────────────

  static Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    bool download = false,
  }) async {
    if (kIsWeb) {
      // Note: _addToWebCache is idempotent per path now, so calling it here
      // even after a prior `cache()` call is safe — the total byte count
      // stays consistent.
      _addToWebCache(path, bytes);
      if (download || path.endsWith('.pdf')) {
        final name = path.contains('/')
            ? path.split('/').last
            : path.contains('\\')
                ? path.split('\\').last
                : path;
        downloadFile(name, bytes);
      }
    } else {
      // Mobile: write to disk, do NOT cache in memory.
      await ioWriteBytes(path, bytes);
    }
  }

  // ── Share multiple generic files together ──────────────────────────────
  //
  // Web:    each file triggers its own browser download (sequential).
  // Mobile: all files are handed to the OS share sheet together, so the user
  //         can save them all to Photos/Files in one action.

  static Future<void> shareFiles(
    List<MapEntry<String, Uint8List>> files, {
    BuildContext? context,
    Rect? sharePositionOrigin,
    String? subject,
  }) async {
    if (files.isEmpty) return;

    if (kIsWeb) {
      for (final f in files) {
        downloadFile(f.key, f.value);
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final xfiles = <XFile>[];

    // Prefix each filename with its index so identical keys never collide
    // on disk (the previous version overwrote when two entries shared a key,
    // silently losing content).
    int index = 0;
    for (final f in files) {
      final uniqueName = '${index++}_${f.key}';
      final file = io.File('${dir.path}/$uniqueName');
      await file.writeAsBytes(f.value, flush: true);
      xfiles.add(XFile(file.path));
    }

    final Rect? anchor = _resolveAnchor(context, sharePositionOrigin);

    await Share.shareXFiles(
      xfiles,
      subject: subject,
      sharePositionOrigin: io.Platform.isIOS ? anchor : null,
    );
  }

  // ── Generate output path ───────────────────────────────────────────────

  static Future<String> outputPath(String filename) async {
    if (kIsWeb) return filename;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$filename';
  }

  // ── Check existence ────────────────────────────────────────────────────

  static bool exists(String path) {
    if (kIsWeb) return _webCache.containsKey(path);
    return ioExists(path);
  }

  // ── Delete ─────────────────────────────────────────────────────────────

  static Future<void> delete(String path) async {
    if (kIsWeb) {
      final bytes = _webCache.remove(path);
      if (bytes != null) _webCacheTotalBytes -= bytes.length;
    } else {
      await ioDelete(path);
    }
  }

  static Future<void> clearCache() async {
    if (!kIsWeb) return;
    _webCache.clear();
    _webCacheTotalBytes = 0;
  }

  static void clearCacheEntry(String path) {
    if (!kIsWeb) return;
    final bytes = _webCache.remove(path);
    if (bytes != null) _webCacheTotalBytes -= bytes.length;
  }

  // ── Share-sheet anchor (iOS) ───────────────────────────────────────────

  /// Resolve the best share-sheet anchor rect for iOS.
  ///
  /// Priority:
  ///   1. Caller-supplied [origin] if non-null and non-empty.
  ///   2. Centre-bottom of the screen derived from [context]'s MediaQuery.
  ///   3. Centre-bottom derived from the Overlay if MediaQuery is unavailable.
  ///   4. Safe hard-coded fallback (only reached in unusual embedding cases).
  static Rect? _resolveAnchor(BuildContext? context, Rect? origin) {
    // Never touch io.Platform on web — even though the caller guards this,
    // keeping the check here makes the helper safe to call from anywhere.
    if (kIsWeb) return null;
    if (!io.Platform.isIOS) return null;

    // Caller supplied a valid rect.
    if (origin != null && origin.width > 0 && origin.height > 0) {
      return origin;
    }

    // Device-agnostic fallback via MediaQuery (works on iPad, iPhone, etc.).
    if (context != null) {
      final mq = MediaQuery.maybeOf(context);
      if (mq != null && mq.size.width > 0 && mq.size.height > 0) {
        return Rect.fromLTWH(
          mq.size.width / 2 - 1,
          mq.size.height - 100,
          2,
          50,
        );
      }
    }

    // Fall back to the Overlay bounds if there's no MediaQuery ancestor.
    if (context != null) {
      try {
        final overlay = Overlay.of(context);
        final box = overlay.context.findRenderObject();
        if (box != null && box.paintBounds.width > 0) {
          final b = box.paintBounds;
          return Rect.fromLTWH(
            b.width / 2 - 1,
            b.height - 100,
            2,
            50,
          );
        }
      } catch (_) {}
    }

    // Last-resort hard-coded fallback. Only reached when neither MediaQuery
    // nor Overlay is available — essentially never in a Flutter app.
    return const Rect.fromLTWH(195, 744, 2, 50);
  }
}

// ── Result types ──────────────────────────────────────────────────────────

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