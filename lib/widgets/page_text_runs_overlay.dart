import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../pdf_core/content_stream/content_stream_analyzer.dart';
import '../pdf_core/pdf_text_editor.dart';
import '../services/pdf_ocr_service.dart';
import '../widgets/ds.dart';
import '../widgets/text_editor_overlay.dart';

// ────────────────────────────────────────────────────────────────────────────
// compute() message types and top-level worker functions.
// ────────────────────────────────────────────────────────────────────────────

class _ExtractRequest {
  final Uint8List bytes;
  final int pageIndex;
  final int maxChars;
  final int maxConst;
  const _ExtractRequest(
      this.bytes, this.pageIndex, this.maxChars, this.maxConst);
}

class _ExtractResult {
  final List<TextRun> editable;
  final List<TextRun> skipped;
  const _ExtractResult(this.editable, this.skipped);
}

_ExtractResult _extractRunsWorker(_ExtractRequest req) {
  final editor = PdfTextEditor(req.bytes);
  final all = editor.extractPageRuns(req.pageIndex);

  final editable = <TextRun>[];
  final skipped = <TextRun>[];
  for (final r in all) {
    final t = r.text.trim();
    final tooLong = t.isEmpty || t.length > req.maxChars;
    final tooManyParts =
        r.constituents != null && r.constituents!.length > req.maxConst;
    (tooLong || tooManyParts ? skipped : editable).add(r);
  }
  return _ExtractResult(editable, skipped);
}

// ────────────────────────────────────────────────────────────────────────────
// Widget
// ────────────────────────────────────────────────────────────────────────────

class PageTextRunsOverlay extends StatefulWidget {
  final Uint8List sourceBytes;
  final int pageIndex;
  final int pageCount;
  final int revision;
  final double displayWidth;
  final double displayHeight;
  final double pageWidthPt;
  final double pageHeightPt;
  final void Function(TextEditAnnotation edit) onEditCommitted;
  final void Function(Uint8List newSourceBytes)? onSourceBytesUpdated;

  /// Returns the rendered page's raw pixels for OCR, or null if the render
  /// hasn't finished yet. Only used when content-stream extraction finds
  /// nothing (scanned / rasterized pages).
  final OcrPageSource? Function()? ocrSourceProvider;

  final Future<int> Function(Rect normRect)? sampleBackground;

  final int maxEditableChars;
  final int maxConstituents;
  final Duration isolateTimeout;

  const PageTextRunsOverlay({
    super.key,
    required this.sourceBytes,
    required this.pageIndex,
    required this.pageCount,
    required this.revision,
    required this.displayWidth,
    required this.displayHeight,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.onEditCommitted,
    this.onSourceBytesUpdated,
    this.ocrSourceProvider,
    this.sampleBackground,
    this.maxEditableChars = 200,
    this.maxConstituents = 8,
    this.isolateTimeout = const Duration(seconds: 30),
  });

  @override
  State<PageTextRunsOverlay> createState() => _PageTextRunsOverlayState();
}

class _PageTextRunsOverlayState extends State<PageTextRunsOverlay> {
  List<TextRun>? _runs;
  List<TextRun>? _skippedRuns;
  bool _loading = false;
  bool _ocrLoading = false;
  bool _ocrAttempted = false;
  bool _ocrSourceUnavailable = false;
  String? _error;

  int _loadGeneration = 0;
  bool _editInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PageTextRunsOverlay old) {
    super.didUpdateWidget(old);
    if (old.sourceBytes != widget.sourceBytes ||
        old.revision != widget.revision ||
        old.pageIndex != widget.pageIndex) {
      _ocrAttempted = false;
      _ocrSourceUnavailable = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;

    if (widget.pageIndex < 0 || widget.pageIndex >= widget.pageCount) {
      if (mounted) {
        setState(() {
          _error = 'Page index ${widget.pageIndex} out of range '
              '(document has ${widget.pageCount} page(s))';
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _ocrLoading = false;
        _ocrSourceUnavailable = false;
        _error = null;
      });
    }

    await Future.delayed(Duration.zero);

    final request = _ExtractRequest(
      widget.sourceBytes,
      widget.pageIndex,
      widget.maxEditableChars,
      widget.maxConstituents,
    );

    var stage = 'extract';
    try {
      final result = await compute(_extractRunsWorker, request)
          .timeout(widget.isolateTimeout);

      if (!mounted || generation != _loadGeneration) return;

      if (result.editable.isNotEmpty || result.skipped.isNotEmpty) {
        setState(() {
          _runs = result.editable;
          _skippedRuns = result.skipped;
          _loading = false;
        });
        return;
      }

      // Nothing in the content stream — try OCR if available.
      await _tryOcr(generation);
    } on TimeoutException {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = 'Text scan timed out after '
            '${widget.isolateTimeout.inSeconds}s '
            '(stage=$stage, page=${widget.pageIndex})';
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[PageTextRuns] scan failed at stage=$stage: $e\n$st');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = '$e (stage=$stage)';
        _loading = false;
      });
    }
  }

  /// Runs ML Kit OCR on the rendered page pixels. Must be on the main
  /// isolate — ML Kit uses platform channels and rejects background calls.
  ///
  /// The page render and this overlay build at the same time, so on first
  /// entry the pixel data usually isn't ready yet. We poll for up to 5
  /// seconds before giving up. Without the poll, a scanned PDF would
  /// permanently show "no editable text" even though OCR is available.
  Future<void> _tryOcr(int generation) async {
    final provider = widget.ocrSourceProvider;

    if (kIsWeb || provider == null) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _runs = const [];
          _skippedRuns = const [];
          _ocrAttempted = true;
          _loading = false;
        });
      }
      return;
    }

    if (mounted && generation == _loadGeneration) {
      setState(() => _ocrLoading = true);
    }

    // Poll for the rendered page. `_renderPage` in `PdfPageWidget` runs
    // async; on entry its pixel buffer is usually still null.
    OcrPageSource? source;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (source == null && DateTime.now().isBefore(deadline)) {
      if (!mounted || generation != _loadGeneration) return;
      source = provider();
      if (source == null) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    if (source == null) {
      // Render never produced pixels within the timeout — likely a render
      // failure or a very slow device. Surface it distinctly so the user
      // knows it's not "this page has no text", it's "we couldn't read
      // the page".
      debugPrint('[PageTextRuns] OCR source never became available '
          '(page=${widget.pageIndex})');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _runs = const [];
        _skippedRuns = const [];
        _ocrAttempted = true;
        _ocrSourceUnavailable = true;
        _ocrLoading = false;
        _loading = false;
      });
      return;
    }

    debugPrint('[PageTextRuns] running OCR on '
        '${source.width}x${source.height} pixels');

    List<OcrTextRun> ocrRuns;
    try {
      ocrRuns = await PdfOcrService.recognizePage(
        source: source,
        pageWidthPt: widget.pageWidthPt,
        pageHeightPt: widget.pageHeightPt,
      );
    } catch (e, st) {
      debugPrint('[PageTextRuns] OCR failed: $e\n$st');
      ocrRuns = const [];
    }

    if (!mounted || generation != _loadGeneration) return;

    debugPrint('[PageTextRuns] OCR found ${ocrRuns.length} line(s)');

    final asRuns = <TextRun>[
      for (final o in ocrRuns)
        TextRun(
          id: -1, // sentinel: OCR run, no content-stream byte range
          byteStart: -1,
          byteEnd: -1,
          text: o.text,
          x: o.x,
          y: o.y,
          width: o.width,
          height: o.height,
          baselineX: o.x,
          baselineY: o.y,
          endX: o.x + o.width,
          fontRef: '',
          fontSize: (o.height * 1.0).clamp(6.0, 72.0), 
          widthEm: 0,
          originalHz: 100,
          charSpacing: 0,
          wordSpacing: 0,
        ),
    ];

    setState(() {
      _runs = asRuns;
      _skippedRuns = const [];
      _ocrAttempted = true;
      _ocrSourceUnavailable = false;
      _ocrLoading = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        if (_loading) {
          return _spinnerCard('Scanning page for text…');
        }
        if (_ocrLoading) {
          return _spinnerCard('Reading text from image…');
        }

        if (_error != null) {
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: _infoCard(
                      icon: Icons.error_outline_rounded,
                      iconColor: DS.red,
                      title: 'Could not read text on this page',
                      body: 'The text layer may be encrypted, malformed, '
                          'or use a font the editor cannot decode.\n\n'
                          'You can still annotate, highlight, and sign '
                          'this page.\n\n'
                          'Details: $_error',
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final runs = _runs ?? const <TextRun>[];
        final skipped = _skippedRuns ?? const <TextRun>[];

        if (runs.isEmpty && skipped.isEmpty) {
          final hasOcr = !kIsWeb && widget.ocrSourceProvider != null;
          final String title;
          final String body;

          if (_ocrSourceUnavailable) {
            title = 'Could not read this page';
            body = 'The page did not finish rendering in time, so text '
                'recognition could not run.\n\n'
                'Try closing and reopening this page, or use the "Text" '
                'tool to place new text on top.';
          } else if (_ocrAttempted && hasOcr) {
            title = 'No text recognized on this page';
            body = 'The page looks like a scan, but OCR could not find '
                'any readable text. Try a clearer scan, or use the '
                '"Text" tool to place new text on top.';
          } else if (kIsWeb) {
            title = 'This page has no editable text';
            body = 'It looks like a scanned or image-only page. Automatic '
                'text recognition is not available in the browser.\n\n'
                'You can still annotate, highlight, and sign.';
          } else {
            title = 'This page has no editable text';
            body = 'It looks like a scanned or image-only page — there is '
                'no text layer to edit here.\n\n'
                'You can still annotate, highlight, sign, or place text '
                'on top using the "Text" tool.';
          }

          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: _infoCard(
                      icon: Icons.image_outlined,
                      title: title,
                      body: body,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        if (runs.isEmpty && skipped.isNotEmpty) {
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: _infoCard(
                      icon: Icons.format_size_rounded,
                      title: 'Only large text blocks on this page',
                      body: '${skipped.length} paragraph'
                          '${skipped.length == 1 ? "" : "s"} on this page '
                          '${skipped.length == 1 ? "is" : "are"} too large '
                          'to edit safely in place.\n\n'
                          'Try another page with smaller text, or use the '
                          '"Text" tool to place new text on top.',
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final sx = size.width / widget.pageWidthPt;
        final sy = size.height / widget.pageHeightPt;

        return Stack(
          children: [
            ...skipped.map((run) => _buildSkippedOutline(run, sx, sy)),
            ...runs.map((run) {
              final isOcr = run.id < 0;
              final accent = isOcr ? DS.orange : DS.indigo;

              final left = run.x * sx;
              final width = run.width * sx;
              final top =
                  (widget.pageHeightPt - (run.y + run.height)) * sy;
              final height = run.height * sy;
              const pad = 2.0;

              return Positioned(
                left: left - pad,
                top: top - pad,
                width: width + pad * 2,
                height: height + pad * 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _openEditor(run, d.globalPosition),
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      border: Border.all(
                        color: accent.withOpacity(0.7),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: isOcr
                        ? Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 3, vertical: 1),
                                decoration: BoxDecoration(
                                  color: DS.orange.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'OCR',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _spinnerCard(String message) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: DS.bgCard.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DS.indigo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      message,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkippedOutline(TextRun run, double sx, double sy) {
    final left = run.x * sx;
    final width = run.width * sx;
    final top = (widget.pageHeightPt - (run.y + run.height)) * sy;
    final height = run.height * sy;
    return Positioned(
      left: left - 2,
      top: top - 2,
      width: width + 4,
      height: height + 4,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
    Color iconColor = Colors.white38,
  }) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: DS.bgCard.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(TextRun run, Offset globalTap) async {
    if (_editInFlight) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Finishing previous edit…'),
            duration: Duration(milliseconds: 900),
          ),
        );
      }
      return;
    }

    final media = MediaQuery.of(context);
    const editorW = 340.0;
    const editorH = 320.0;
    final maxLeft = math.max(8.0, media.size.width - editorW - 8);
    final maxTop = math.max(8.0, media.size.height - editorH - 8);
    final left = globalTap.dx.clamp(8.0, maxLeft);
    final top = (globalTap.dy + 12).clamp(8.0, maxTop);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: TextEditorOverlay(
              initialText: run.text,
              startPlain: true,
              onSave: (text, style, formattingChanged) {
                Navigator.pop(ctx);
                if (text == run.text) return;
                _commitInPlace(run, text, style);
              },
              onCancel: () => Navigator.pop(ctx),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _commitInPlace(
      TextRun run, String newText, TextStyle style) async {
    await _commit(run, newText, style);
  }

  Future<void> _commit(
      TextRun run, String newText, TextStyle style) async {
    if (_editInFlight) return;
    _editInFlight = true;

    try {
      final pageIndex = widget.pageIndex;
      final pageWidthPt = widget.pageWidthPt;
      final pageHeightPt = widget.pageHeightPt;

      final originalNormRect = Rect.fromLTWH(
        run.x / pageWidthPt,
        (pageHeightPt - (run.y + run.height)) / pageHeightPt,
        run.width / pageWidthPt,
        run.height / pageHeightPt,
      );

      int coverColorValue = 0xFFFFFFFF;
      final sampler = widget.sampleBackground;
      if (sampler != null) {
        try {
          coverColorValue = await sampler(originalNormRect);
        } catch (_) {
          coverColorValue = 0xFFFFFFFF;
        }
      }

      if (!mounted) return;

      final edit = TextEditAnnotation(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        pageIndex: pageIndex,
        normPosition: Offset(
          run.x / pageWidthPt,
          (pageHeightPt - (run.y + run.height)) / pageHeightPt,
        ),
        text: newText,
        color: Colors.black,
        fontSize: style.fontSize ?? run.fontSize,
        isBold: style.fontWeight == FontWeight.bold,
        isItalic: style.fontStyle == FontStyle.italic,
        fontFamily: style.fontFamily ?? 'Inter',
        originalText: run.text,
        originalNormRect: originalNormRect,
        preserveWidth: true,
        coverColorValue: coverColorValue,
      );

      try {
        widget.onEditCommitted(edit);
      } catch (e, st) {
        debugPrint('[PageTextRuns] onEditCommitted THREW: $e\n$st');
      }
    } finally {
      _editInFlight = false;
    }
  }
}