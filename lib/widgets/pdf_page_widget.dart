import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/annotation.dart';
import '../services/pdf_ocr_service.dart';
import 'annotation_painter.dart';
import 'ds.dart';
import 'page_text_runs_overlay.dart';
import 'text_editor_overlay.dart';
import '../utils/app_localizations.dart';

final _renderSem = _Semaphore(1);

class PdfPageWidget extends StatefulWidget {
  final PdfDocument document;
  final int pageIndex;
  final int pageCount;
  final int revision;
  final double displayWidth;
  final bool darkMode;
  final List<RectAnnotation> rects;
  final InkAnnotation? ink;
  final List<StickyNote> notes;
  final List<SignatureOverlay> signatures;
  final List<TextStamp> textStamps;
  final List<RedactionRect> redactions;
  final List<ClauseBookmark> clauseBookmarks;
  final List<TextEditAnnotation> textEdits;
  final AnnotationTool tool;
  final Color annotationColor;
  final double inkStrokeWidth;
  final Uint8List? pendingSignature;
  final bool isInitialMode;
  final Uint8List? currentSourceBytes;

  final void Function(RectAnnotation) onRectAdded;
  final void Function(InkStroke) onInkStrokeAdded;
  final void Function(StickyNote) onNoteAdded;
  final void Function(String, bool) onNoteToggled;
  final void Function(SignatureOverlay) onSignaturePlaced;
  final void Function(String, Offset) onSignatureMoved;
  final void Function(String, Size) onSignatureResized;
  final void Function(String) onSignatureDeleted;
  final void Function(TextStamp) onTextStampAdded;
  final void Function(RedactionRect) onRedactionAdded;
  final void Function(ClauseBookmark) onBookmarkAdded;
  final void Function(TextEditAnnotation) onTextEditAdded;
  final void Function(Rect) onHighlightTapped;
  final void Function(Uint8List newSourceBytes)? onSourceBytesUpdated;

  const PdfPageWidget({
    super.key,
    required this.document,
    required this.pageIndex,
    required this.pageCount,
    required this.revision,
    required this.displayWidth,
    required this.darkMode,
    required this.rects,
    required this.ink,
    required this.notes,
    required this.signatures,
    required this.textStamps,
    required this.redactions,
    required this.clauseBookmarks,
    required this.textEdits,
    required this.tool,
    required this.annotationColor,
    required this.inkStrokeWidth,
    required this.pendingSignature,
    required this.isInitialMode,
    required this.onRectAdded,
    required this.onInkStrokeAdded,
    required this.onNoteAdded,
    required this.onNoteToggled,
    required this.onSignaturePlaced,
    required this.onSignatureMoved,
    required this.onSignatureResized,
    required this.onSignatureDeleted,
    required this.onTextStampAdded,
    required this.onRedactionAdded,
    required this.onBookmarkAdded,
    required this.onTextEditAdded,
    required this.onHighlightTapped,
    this.currentSourceBytes,
    this.onSourceBytesUpdated,
  });

  @override
  State<PdfPageWidget> createState() => _PdfPageWidgetState();
}

class _PdfPageWidgetState extends State<PdfPageWidget> {
  ui.Image? _pageImage;
  bool _loading = true;
  bool _failed = false;
  int _retries = 0;

  // Raw RGBA pixel data from the last render. Used to feed OCR when the
  // page has no extractable text layer (scanned / rasterized PDFs).
  Uint8List? _rawPagePixels;
  int _rawPixelWidth = 0;
  int _rawPixelHeight = 0;

  static const _maxRetries = 3;
  static const _maxRenderSize = 2000.0;

  Offset? _dragStart, _dragCurrent;
  final List<Offset> _strokePoints = [];
  String? _selectedSigId;

  late final TransformationController _transformationController;

  double get _pageAspect {
    try {
      final page = widget.document.pages[widget.pageIndex];
      return page.width / page.height;
    } catch (_) {
      return 1.414;
    }
  }

  double get _pageWidthPt {
    try {
      return widget.document.pages[widget.pageIndex].width;
    } catch (_) {
      return 595.28;
    }
  }

  double get _pageHeightPt {
    try {
      return widget.document.pages[widget.pageIndex].height;
    } catch (_) {
      return 841.89;
    }
  }

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _renderPage();
  }

  @override
  void didUpdateWidget(PdfPageWidget old) {
    super.didUpdateWidget(old);
    final documentChanged = !identical(old.document, widget.document);
    if (documentChanged ||
        (old.displayWidth - widget.displayWidth).abs() > 40.0) {
      _retries = 0;
      _renderPage();
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _pageImage?.dispose();
    super.dispose();
  }

  Future<void> _renderPage() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _failed = false;
    });

    await _renderSem.acquire();
    bool released = false;

    try {
      final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      final safeDpr = dpr < 1.0 ? 1.0 : dpr;
      const renderScale = 1.5;

      final page = widget.document.pages[widget.pageIndex];
      final targetW = widget.displayWidth * safeDpr * renderScale;
      final targetH = targetW / _pageAspect;
      final physW = math.min(targetW, _maxRenderSize);
      final physH = math.min(targetH, _maxRenderSize);

      final bgColor = widget.darkMode ? const Color(0xFF111111) : Colors.white;

      final pdfImage = await page.render(
        fullWidth: physW,
        fullHeight: physH,
        backgroundColor: bgColor,
      );

      if (pdfImage == null || !mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }

      final pixels = pdfImage.pixels;
      final convertedPixels = Uint8List(pixels.length);
      for (int i = 0; i < pixels.length; i += 4) {
        convertedPixels[i] = pixels[i + 2];
        convertedPixels[i + 1] = pixels[i + 1];
        convertedPixels[i + 2] = pixels[i];
        convertedPixels[i + 3] = pixels[i + 3];
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        convertedPixels,
        pdfImage.width,
        pdfImage.height,
        ui.PixelFormat.rgba8888,
        (img) => completer.complete(img),
      );
      final uiImage = await completer.future;

      if (mounted) {
        _pageImage?.dispose();
        setState(() {
          _pageImage = uiImage;
          _rawPagePixels = convertedPixels;
          _rawPixelWidth = pdfImage.width;
          _rawPixelHeight = pdfImage.height;
          _loading = false;
          _failed = false;
          _retries = 0;
        });
      } else {
        uiImage.dispose();
      }

      released = true;
      _renderSem.release();
    } catch (e) {
      if (mounted) {
        if (_retries < _maxRetries) {
          _retries++;
          _renderSem.release();
          released = true;
          await Future.delayed(Duration(milliseconds: 500 * _retries));
          return _renderPage();
        }
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    } finally {
      if (!released) _renderSem.release();
    }
  }

  /// Returns the last rendered page's raw pixels + dimensions, or null if
  /// the page hasn't finished rendering yet. Consumed by the text-runs
  /// overlay as an OCR source when the page has no text layer.
  OcrPageSource? _ocrSource() {
    final px = _rawPagePixels;
    if (px == null || _rawPixelWidth <= 0 || _rawPixelHeight <= 0) return null;
    return OcrPageSource(
      pixels: px,
      width: _rawPixelWidth,
      height: _rawPixelHeight,
    );
  }

  Future<int> _sampleBackground(Rect normRect) async {
    final img = _pageImage;
    if (img == null) return 0xFFFFFFFF;

    try {
      final sampleX =
          (normRect.left * img.width).round().clamp(0, img.width - 1);
      final sampleY =
          ((normRect.top * img.height).round() - 2).clamp(0, img.height - 1);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(sampleX.toDouble(), sampleY.toDouble(), 1.0, 1.0),
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint(),
      );
      final picture = recorder.endRecording();
      final tiny = await picture.toImage(1, 1);
      final data = await tiny.toByteData(format: ui.ImageByteFormat.rawRgba);
      tiny.dispose();
      picture.dispose();

      if (data == null || data.lengthInBytes < 4) return 0xFFFFFFFF;
      final r = data.getUint8(0);
      final g = data.getUint8(1);
      final b = data.getUint8(2);
      return 0xFF000000 | (r << 16) | (g << 8) | b;
    } catch (_) {
      return 0xFFFFFFFF;
    }
  }

  Offset _norm(Offset local, Size size) =>
      Offset(local.dx / size.width, local.dy / size.height);
  Rect _dn(Rect n, double w, double h) =>
      Rect.fromLTWH(n.left * w, n.top * h, n.width * w, n.height * h);

  bool get _isRectTool =>
      widget.tool == AnnotationTool.highlight ||
      widget.tool == AnnotationTool.underline ||
      widget.tool == AnnotationTool.strikethrough ||
      widget.tool == AnnotationTool.redaction ||
      widget.tool == AnnotationTool.clauseBookmark;

  AnnotationType? get _rectType => switch (widget.tool) {
        AnnotationTool.highlight => AnnotationType.highlight,
        AnnotationTool.underline => AnnotationType.underline,
        AnnotationTool.strikethrough => AnnotationType.strikethrough,
        _ => null,
      };

  Color get _toolColor => switch (widget.tool) {
        AnnotationTool.highlight => const Color(0xFFFFD600),
        AnnotationTool.underline => const Color(0xFF38BDF8),
        AnnotationTool.strikethrough => const Color(0xFFF87171),
        AnnotationTool.redaction => Colors.black,
        _ => widget.annotationColor,
      };

  bool get _annotating =>
      widget.tool != AnnotationTool.view || widget.pendingSignature != null;

  bool get _isTextEditMode => widget.tool == AnnotationTool.textEdit;

  void _onTap(TapDownDetails d, Size size) {
    final l10n = AppLocalizations.of(context)!;
    final norm = _norm(d.localPosition, size);

    if (_isTextEditMode) return;

    for (final note in widget.notes) {
      final nx = note.normPosition.dx * size.width;
      final ny = note.normPosition.dy * size.height;
      if ((d.localPosition - Offset(nx, ny)).distance < size.width * 0.07) {
        widget.onNoteToggled(note.id, !note.isExpanded);
        return;
      }
    }

    for (final r in widget.rects) {
      if (r.type != AnnotationType.highlight) continue;
      final rect = _dn(r.normRect, size.width, size.height);
      if (rect.contains(d.localPosition)) {
        widget.onHighlightTapped(r.normRect);
        return;
      }
    }

    if (_annotating) {
      if (widget.tool == AnnotationTool.textStamp) {
        _showTextEditor(context, norm);
        return;
      }
      if (widget.pendingSignature != null) {
        widget.onSignaturePlaced(
          SignatureOverlay(
            id: UniqueKey().toString(),
            imageBytes: widget.pendingSignature!,
            pageIndex: widget.pageIndex,
            normPosition: Offset(
              (norm.dx - 0.175).clamp(0.0, 0.65),
              (norm.dy - 0.035).clamp(0.0, 0.93),
            ),
            normSize: widget.isInitialMode
                ? const Size(0.18, 0.05)
                : const Size(0.38, 0.08),
            isInitials: widget.isInitialMode,
          ),
        );
        return;
      }
      if (widget.tool == AnnotationTool.stickyNote) {
        _showNoteDialog(context, norm);
      }
    }

    setState(() => _selectedSigId = null);
  }

  void _showTextEditor(BuildContext ctx, Offset normPos) {
    final l10n = AppLocalizations.of(ctx)!;
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: TextEditorOverlay(
          onSave: (text, style, formattingChanged) {
            widget.onTextEditAdded(
              TextEditAnnotation(
                id: UniqueKey().toString(),
                pageIndex: widget.pageIndex,
                normPosition: normPos,
                text: text,
                color: style.color ?? widget.annotationColor,
                fontSize: style.fontSize ?? 14,
                isBold: style.fontWeight == FontWeight.bold,
                isItalic: style.fontStyle == FontStyle.italic,
              ),
            );
            Navigator.pop(dialogCtx);
          },
          onCancel: () => Navigator.pop(dialogCtx),
        ),
      ),
    );
  }

  Future<void> _showNoteDialog(BuildContext ctx, Offset normPos) async {
    final l10n = AppLocalizations.of(ctx)!;
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: DS.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.addNoteTitle,
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.addNoteHint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.07),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel,
                style: const TextStyle(color: Colors.white38)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: DS.indigo),
            child: Text(l10n.add),
          ),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) {
      widget.onNoteAdded(
        StickyNote(
          id: UniqueKey().toString(),
          pageIndex: widget.pageIndex,
          normPosition: normPos,
          text: text.trim(),
          color: const Color(0xFFFB923C),
        ),
      );
    }
  }

  void _onPanStart(DragStartDetails d, Size size) {
    if (_isTextEditMode) return;
    if (widget.tool == AnnotationTool.ink) {
      setState(() {
        _strokePoints
          ..clear()
          ..add(_norm(d.localPosition, size));
      });
    } else if (_isRectTool) {
      setState(() {
        _dragStart = d.localPosition;
        _dragCurrent = d.localPosition;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    if (_isTextEditMode) return;
    if (widget.tool == AnnotationTool.ink) {
      setState(() => _strokePoints.add(_norm(d.localPosition, size)));
    } else if (_isRectTool) {
      setState(() => _dragCurrent = d.localPosition);
    }
  }

  void _onPanEnd(DragEndDetails _, Size size) {
    if (_isTextEditMode) return;
    if (widget.tool == AnnotationTool.ink && _strokePoints.length >= 2) {
      widget.onInkStrokeAdded(
        InkStroke(
          points: List.from(_strokePoints),
          color: widget.annotationColor,
          normWidth: widget.inkStrokeWidth,
        ),
      );
      setState(() => _strokePoints.clear());
      return;
    }

    if (_isRectTool && _dragStart != null && _dragCurrent != null) {
      final r = Rect.fromPoints(
        _norm(_dragStart!, size),
        _norm(_dragCurrent!, size),
      );
      if (r.width > 0.01 && r.height > 0.005) {
        switch (widget.tool) {
          case AnnotationTool.redaction:
            widget.onRedactionAdded(
              RedactionRect(
                id: UniqueKey().toString(),
                pageIndex: widget.pageIndex,
                normRect: r,
              ),
            );
          case AnnotationTool.clauseBookmark:
            _showBookmarkDialog(context, r);
          default:
            if (_rectType != null) {
              widget.onRectAdded(
                RectAnnotation(
                  id: UniqueKey().toString(),
                  pageIndex: widget.pageIndex,
                  normRect: r,
                  color: _toolColor,
                  type: _rectType!,
                ),
              );
            }
        }
      }
      setState(() {
        _dragStart = null;
        _dragCurrent = null;
      });
    }
  }

  Future<void> _showBookmarkDialog(BuildContext ctx, Rect normRect) async {
    final l10n = AppLocalizations.of(ctx)!;
    const labels = [
      'Payment Terms',
      'Liability',
      'Termination',
      'Confidentiality',
      'Indemnification',
      'Governing Law',
    ];
    const colors = [
      DS.indigo,
      DS.green,
      DS.orange,
      DS.red,
      Color(0xFF3B82F6),
      DS.purple
    ];
    String sel = labels.first;
    await showDialog<void>(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (c2, ss) => AlertDialog(
          backgroundColor: DS.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l10n.clauseLabelTitle,
              style: const TextStyle(color: Colors.white)),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: labels
                .map((lbl) => GestureDetector(
                      onTap: () => ss(() => sel = lbl),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel == lbl ? DS.indigo : Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel == lbl
                                  ? DS.indigo
                                  : Colors.white24),
                        ),
                        child: Text(lbl,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                      ),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c2),
              child: Text(l10n.cancel,
                  style: const TextStyle(color: Colors.white38)),
            ),
            FilledButton(
              onPressed: () {
                final idx = labels.indexOf(sel);
                widget.onBookmarkAdded(
                  ClauseBookmark(
                    id: UniqueKey().toString(),
                    pageIndex: widget.pageIndex,
                    normRect: normRect,
                    label: sel,
                    color: colors[idx.clamp(0, colors.length - 1)],
                  ),
                );
                Navigator.pop(c2);
              },
              style: FilledButton.styleFrom(backgroundColor: DS.indigo),
              child: Text(l10n.add),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayH = widget.displayWidth / _pageAspect;
    return SizedBox(
      width: widget.displayWidth,
      height: displayH,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              Positioned.fill(child: _buildImage(context)),
              Positioned.fill(child: _buildAnnotationLayer(context, size)),
              ...widget.signatures.map((s) => _buildSigOverlay(s, size)),
              ...widget.textEdits.map((t) => _buildTextEdit(t, size)),
              if (_isTextEditMode && widget.currentSourceBytes != null)
                Positioned.fill(
                  child: PageTextRunsOverlay(
                    sourceBytes: widget.currentSourceBytes!,
                    pageIndex: widget.pageIndex,
                    pageCount: widget.pageCount,
                    revision: widget.revision,
                    displayWidth: size.width,
                    displayHeight: size.height,
                    pageWidthPt: _pageWidthPt,
                    pageHeightPt: _pageHeightPt,
                    onEditCommitted: widget.onTextEditAdded,
                    onSourceBytesUpdated: widget.onSourceBytesUpdated,
                    sampleBackground: _sampleBackground,
                    ocrSourceProvider: _ocrSource,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextEdit(TextEditAnnotation textEdit, Size pageSize) {
    final style = TextStyle(
      fontSize: textEdit.fontSize,
      color: textEdit.color,
      fontWeight: textEdit.isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: textEdit.isItalic ? FontStyle.italic : FontStyle.normal,
      fontFamily: textEdit.fontFamily,
    );

    if (textEdit.isReplacement) {
      final r = textEdit.originalNormRect!;
      final coverColor = Color(textEdit.coverColorValue);
      return Positioned(
        left: r.left * pageSize.width,
        top: r.top * pageSize.height,
        width: r.width * pageSize.width,
        height: r.height * pageSize.height,
        child: Stack(
          children: [
            Container(color: coverColor),
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(textEdit.text, style: style, maxLines: 1),
              ),
            ),
          ],
        ),
      );
    }

    return Positioned(
      left: textEdit.normPosition.dx * pageSize.width,
      top: textEdit.normPosition.dy * pageSize.height,
      child: Text(textEdit.text, style: style),
    );
  }

  Widget _buildImage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(color: DS.indigo, strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed) {
      return Container(
        color: const Color(0xFF1A1A2E),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  size: 32, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  _retries = 0;
                  _renderPage();
                },
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: Text(l10n.retry),
                style: FilledButton.styleFrom(
                  backgroundColor: DS.indigo.withOpacity(0.7),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_pageImage == null) return Container(color: Colors.white);

    final displayH = widget.displayWidth / _pageAspect;

    return GestureDetector(
      onDoubleTap: () {
        if (_transformationController.value.getMaxScaleOnAxis() > 1.0) {
          _transformationController.value = Matrix4.identity();
        } else {
          final center = Offset(widget.displayWidth / 2, displayH / 2);
          final newMatrix = Matrix4.identity()
            ..translate(center.dx, center.dy)
            ..scale(2.0)
            ..translate(-center.dx, -center.dy);
          _transformationController.value = newMatrix;
        }
      },
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1.0,
        maxScale: 5.0,
        boundaryMargin: EdgeInsets.zero,
        child: SizedBox(
          width: widget.displayWidth,
          height: displayH,
          child: RawImage(
            image: _pageImage,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  Widget _buildAnnotationLayer(BuildContext context, Size size) {
    final l10n = AppLocalizations.of(context)!;
    Rect? draftNorm;
    if (_dragStart != null && _dragCurrent != null && _isRectTool) {
      draftNorm =
          Rect.fromPoints(_norm(_dragStart!, size), _norm(_dragCurrent!, size));
    }
    InkStroke? active;
    if (widget.tool == AnnotationTool.ink && _strokePoints.length >= 2) {
      active = InkStroke(
        points: List.from(_strokePoints),
        color: widget.annotationColor,
        normWidth: widget.inkStrokeWidth,
      );
    }
    final gesturesEnabled = _annotating && !_isTextEditMode;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (d) => _onTap(d, size),
      onPanStart: gesturesEnabled ? (d) => _onPanStart(d, size) : null,
      onPanUpdate: gesturesEnabled ? (d) => _onPanUpdate(d, size) : null,
      onPanEnd: gesturesEnabled ? (d) => _onPanEnd(d, size) : null,
      child: RepaintBoundary(
        child: CustomPaint(
          size: size,
          painter: AnnotationPainter(
            rects: widget.rects,
            ink: widget.ink,
            activeStroke: active,
            notes: widget.notes,
            textStamps: widget.textStamps,
            redactions: widget.redactions,
            clauseBookmarks: widget.clauseBookmarks,
            draftRect: draftNorm,
            draftType:
                widget.tool == AnnotationTool.redaction ? null : _rectType,
            draftColor: _toolColor,
            redactedLabel: l10n.redacted,
          ),
        ),
      ),
    );
  }

  Widget _buildSigOverlay(SignatureOverlay sig, Size pageSize) {
    final isSel = sig.id == _selectedSigId;
    const handleSize = 32.0;
    return Positioned(
      left: sig.normPosition.dx * pageSize.width,
      top: sig.normPosition.dy * pageSize.height,
      child: GestureDetector(
        onTap: () => setState(() => _selectedSigId = sig.id),
        onPanUpdate: (d) => widget.onSignatureMoved(
          sig.id,
          Offset(
            (sig.normPosition.dx + d.delta.dx / pageSize.width)
                .clamp(0.0, 1.0 - sig.normSize.width),
            (sig.normPosition.dy + d.delta.dy / pageSize.height)
                .clamp(0.0, 1.0 - sig.normSize.height),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: sig.normSize.width * pageSize.width,
              height: sig.normSize.height * pageSize.height,
              decoration: BoxDecoration(
                border: Border.all(
                    color: isSel ? DS.indigo : Colors.transparent, width: 2.0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Image.memory(sig.imageBytes, fit: BoxFit.contain),
            ),
            if (isSel) ...[
              Positioned(
                top: -handleSize / 2,
                left: -handleSize / 2,
                child: _Handle(
                  icon: Icons.close_rounded,
                  color: DS.red,
                  size: handleSize,
                  onTap: () => widget.onSignatureDeleted(sig.id),
                ),
              ),
              Positioned(
                bottom: -handleSize / 2,
                right: -handleSize / 2,
                child: _Handle(
                  icon: Icons.open_in_full_rounded,
                  color: DS.indigo,
                  size: handleSize,
                  onPan: (d) => widget.onSignatureResized(
                    sig.id,
                    Size(
                      (sig.normSize.width + d.delta.dx / pageSize.width)
                          .clamp(0.04, 0.9),
                      (sig.normSize.height + d.delta.dy / pageSize.height)
                          .clamp(0.02, 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final void Function(DragUpdateDetails)? onPan;

  const _Handle({
    required this.icon,
    required this.color,
    required this.size,
    this.onTap,
    this.onPan,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: onPan,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)
          ],
        ),
        child: Icon(icon, size: size * 0.55, color: Colors.white),
      ),
    );
  }
}

class _Semaphore {
  final int _max;
  int _count = 0;
  final _q = <Completer<void>>[];

  _Semaphore(this._max);

  Future<void> acquire() async {
    if (_count < _max) {
      _count++;
      return;
    }
    final c = Completer<void>();
    _q.add(c);
    await c.future;
    _count++;
  }

  void release() {
    _count--;
    if (_q.isNotEmpty) _q.removeAt(0).complete();
  }
}