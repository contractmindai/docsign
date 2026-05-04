import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'ds.dart';

class ThumbnailStrip extends StatefulWidget {
  final PdfDocument document;
  final int pageCount;
  final int currentPage;
  final bool darkMode;
  final Map<int, int> annotationCounts;
  final ValueChanged<int> onPageSelected;

  const ThumbnailStrip({
    super.key,
    required this.document,
    required this.pageCount,
    required this.currentPage,
    required this.darkMode,
    required this.annotationCounts,
    required this.onPageSelected,
  });

  @override
  State<ThumbnailStrip> createState() => _ThumbnailStripState();
}

class _ThumbnailStripState extends State<ThumbnailStrip> {
  static const _thumbW = 56.0;
  static const _spacing = 8.0;
  static const _maxCacheSize = 100;
  static const _maxLoadingConcurrent = 3;
  
  final _ThumbnailCache _cache = _ThumbnailCache(maxSize: _maxCacheSize);
  final Set<int> _loading = {};
  int _activeLoads = 0;
  final _scroll = ScrollController();
  final List<int> _pendingLoads = [];

  bool _isWideScreen() {
    final width = MediaQuery.of(context).size.width;
    return width > 700;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cache.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(ThumbnailStrip old) {
    super.didUpdateWidget(old);
    if (old.currentPage != widget.currentPage) {
      _scrollToCurrent();
    }
    if (old.pageCount != widget.pageCount) {
      for (int i = widget.pageCount; i < old.pageCount; i++) {
        _cache.remove(i);
      }
    }
  }

  Future<void> _loadThumb(int pageIndex) async {
    if (_cache.contains(pageIndex) || _loading.contains(pageIndex)) return;
    
    if (_activeLoads >= _maxLoadingConcurrent) {
      if (!_pendingLoads.contains(pageIndex)) {
        _pendingLoads.add(pageIndex);
      }
      return;
    }

    _loading.add(pageIndex);
    _activeLoads++;

    try {
      final page = widget.document.pages[pageIndex];
      final h = _thumbW / (page.width / page.height);
      final renderScale = (page.width * page.height) > 2000000 ? 1.0 : 2.0;

      final pdfImg = await page.render(
        fullWidth: _thumbW * renderScale,
        fullHeight: h * renderScale,
        backgroundColor: Colors.white,
      );

      if (pdfImg == null || !mounted) return;

      ui.Image? uiImg;
      try {
        final pixels = pdfImg.pixels;
        final convertedPixels = Uint8List(pixels.length);
        
        for (int i = 0; i < pixels.length; i += 4) {
          convertedPixels[i] = pixels[i + 2];
          convertedPixels[i + 1] = pixels[i + 1];
          convertedPixels[i + 2] = pixels[i];
          convertedPixels[i + 3] = pixels[i + 3];
        }

        final comp = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          convertedPixels,
          pdfImg.width,
          pdfImg.height,
          ui.PixelFormat.rgba8888,
          (img) => comp.complete(img),
        );
        uiImg = await comp.future;

        final bd = await uiImg.toByteData(format: ui.ImageByteFormat.png);
        if (bd != null && mounted) {
          final sizeKB = bd.lengthInBytes / 1024;
          if (sizeKB <= 500) {
            setState(() {
              _cache.set(pageIndex, bd.buffer.asUint8List());
            });
          }
        }
      } finally {
        uiImg?.dispose();
      }
    } catch (e) {
      debugPrint('Thumbnail load failed: $e');
    } finally {
      _loading.remove(pageIndex);
      _activeLoads--;
      
      if (_pendingLoads.isNotEmpty && mounted) {
        final next = _pendingLoads.removeAt(0);
        _loadThumb(next);
      }
    }
  }

  void _scrollToCurrent() {
    if (!_scroll.hasClients) return;
    final isWide = _isWideScreen();
    if (isWide) {
      final offset = (widget.currentPage - 1) * 120.0;
      _scroll.animateTo(
        offset.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      final offset = (widget.currentPage - 1) * (_thumbW + _spacing) -
          MediaQuery.of(context).size.width / 2 + _thumbW / 2;
      _scroll.animateTo(
        offset.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pageCount <= 0) return const SizedBox.shrink();
    
    final isWide = _isWideScreen();
    
    return Container(
      height: isWide ? double.infinity : 80,
      color: widget.darkMode ? const Color(0xFF1A1A1A) : Colors.white,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: isWide ? Axis.vertical : Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: widget.pageCount,
        itemBuilder: (_, i) {
          _loadThumb(i);
          final isActive = i + 1 == widget.currentPage;
          final annCount = widget.annotationCounts[i] ?? 0;
          final bytes = _cache.get(i);
          final thumbSize = isWide ? 100.0 : 56.0;

          return GestureDetector(
            onTap: () => widget.onPageSelected(i + 1),
            child: Container(
              width: isWide ? double.infinity : thumbSize,
              height: isWide ? thumbSize + 20 : 64,
              margin: isWide 
                  ? const EdgeInsets.only(bottom: 6) 
                  : const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive ? DS.indigo : Colors.grey.withOpacity(0.2),
                  width: isActive ? 2.5 : 1,
                ),
              ),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.cover, 
                          width: isWide ? double.infinity : thumbSize, 
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[100], 
                            child: const Center(child: Icon(Icons.broken_image, size: 16, color: Colors.grey)),
                          ))
                      : Container(
                          color: Colors.grey[100], 
                          child: const Center(child: SizedBox(
                            width: 12, height: 12, 
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: DS.indigo),
                          )),
                        ),
                ),
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ),
                if (annCount > 0)
                  Positioned(
                    bottom: 3,
                    left: 3,
                    child: Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(color: DS.indigo, shape: BoxShape.circle),
                      child: Center(child: Text('$annCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// LRU Cache
// ═══════════════════════════════════════════════════════════

class _ThumbnailCache {
  final int maxSize;
  final Map<int, _CacheEntry> _cache = {};
  
  _ThumbnailCache({required this.maxSize});
  
  Uint8List? get(int pageIndex) {
    final entry = _cache[pageIndex];
    if (entry != null) {
      entry.lastAccess = DateTime.now();
      return entry.data;
    }
    return null;
  }
  
  void set(int pageIndex, Uint8List data) {
    if (_cache.containsKey(pageIndex)) {
      _cache[pageIndex] = _CacheEntry(data: data, lastAccess: DateTime.now());
      return;
    }
    if (_cache.length >= maxSize) _evictOldest();
    _cache[pageIndex] = _CacheEntry(data: data, lastAccess: DateTime.now());
  }
  
  bool contains(int pageIndex) => _cache.containsKey(pageIndex);
  void remove(int pageIndex) => _cache.remove(pageIndex);
  void clear() => _cache.clear();
  int get size => _cache.length;
  
  double get estimatedMemoryKB {
    double total = 0;
    for (final entry in _cache.values) {
      total += entry.data.lengthInBytes / 1024;
    }
    return total;
  }
  
  void _evictOldest() {
    if (_cache.isEmpty) return;
    int? oldestKey;
    DateTime? oldestTime;
    for (final entry in _cache.entries) {
      if (oldestTime == null || entry.value.lastAccess.isBefore(oldestTime)) {
        oldestTime = entry.value.lastAccess;
        oldestKey = entry.key;
      }
    }
    if (oldestKey != null) _cache.remove(oldestKey);
  }
}

class _CacheEntry {
  final Uint8List data;
  DateTime lastAccess;
  _CacheEntry({required this.data, required this.lastAccess});
}