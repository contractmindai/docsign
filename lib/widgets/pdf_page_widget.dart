import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/annotation.dart';
import 'annotation_painter.dart';
import 'ds.dart';
import 'text_editor_overlay.dart';

final _renderSem = _Semaphore(2);

class PdfPageWidget extends StatefulWidget {
  final PdfDocument document;
  final int pageIndex;
  final double displayWidth;
  final bool darkMode;
  final List<RectAnnotation>   rects;
  final InkAnnotation?          ink;
  final List<StickyNote>        notes;
  final List<SignatureOverlay>  signatures;
  final List<TextStamp>         textStamps;
  final List<RedactionRect>     redactions;
  final List<ClauseBookmark>    clauseBookmarks;
  final List<TextEditAnnotation> textEdits; // ✅ ADD THIS
  final AnnotationTool  tool;
  final Color           annotationColor;
  final double          inkStrokeWidth;
  final Uint8List?      pendingSignature;
  final bool            isInitialMode;
  final void Function(RectAnnotation)    onRectAdded;
  final void Function(InkStroke)         onInkStrokeAdded;
  final void Function(StickyNote)        onNoteAdded;
  final void Function(String, bool)      onNoteToggled;
  final void Function(SignatureOverlay)  onSignaturePlaced;
  final void Function(String, Offset)    onSignatureMoved;
  final void Function(String, Size)      onSignatureResized;
  final void Function(String)            onSignatureDeleted;
  final void Function(TextStamp)         onTextStampAdded;
  final void Function(RedactionRect)     onRedactionAdded;
  final void Function(ClauseBookmark)    onBookmarkAdded;
  final void Function(TextEditAnnotation) onTextEditAdded; // ✅ ADD THIS

  const PdfPageWidget({
    super.key,
    required this.document, required this.pageIndex, required this.displayWidth,
    required this.darkMode, required this.rects, required this.ink,
    required this.notes, required this.signatures, required this.textStamps,
    required this.redactions, required this.clauseBookmarks, 
    required this.textEdits, // ✅ ADD THIS
    required this.tool,
    required this.annotationColor, required this.inkStrokeWidth,
    required this.pendingSignature, required this.isInitialMode,
    required this.onRectAdded, required this.onInkStrokeAdded,
    required this.onNoteAdded, required this.onNoteToggled,
    required this.onSignaturePlaced, required this.onSignatureMoved,
    required this.onSignatureResized, required this.onSignatureDeleted,
    required this.onTextStampAdded, required this.onRedactionAdded,
    required this.onBookmarkAdded, required this.onTextEditAdded, // ✅ ADD THIS
  });

  @override
  State<PdfPageWidget> createState() => _PdfPageWidgetState();
}

class _PdfPageWidgetState extends State<PdfPageWidget> {
  Uint8List? _pageBytes;
  double     _aspect = 1.414;
  bool       _loading = true;
  bool       _failed  = false;
  int        _retries = 0;
  static const _maxRetries = 3;
  static const _maxRenderWidth = 1200.0;

  Offset? _dragStart, _dragCurrent;
  final List<Offset> _strokePoints = [];
  String? _selectedSigId;

  @override
  void initState() { super.initState(); _renderPage(); }

  @override
  void didUpdateWidget(PdfPageWidget old) {
    super.didUpdateWidget(old);
    if (old.displayWidth != widget.displayWidth) { _retries = 0; _renderPage(); }
  }

  Future<void> _renderPage() async {
    if (!mounted) return;
    setState(() { _loading = true; _failed = false; });
    await _renderSem.acquire();
    try {
      final page = widget.document.pages[widget.pageIndex];
      _aspect = page.width / page.height;

      final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      final physW = (widget.displayWidth * dpr.clamp(0.5, 2.0)).clamp(300.0, _maxRenderWidth);
      final physH = (physW / _aspect).clamp(200.0, _maxRenderWidth * 2);

      final pdfImage = await page.render(
          fullWidth: physW, fullHeight: physH, backgroundColor: Colors.white);

      if (pdfImage == null || !mounted) {
        setState(() { _loading = false; _failed = true; }); return;
      }

      final pixels = pdfImage.pixels;
      final convertedPixels = Uint8List(pixels.length);
      for (int i = 0; i < pixels.length; i += 4) {
        convertedPixels[i] = pixels[i + 2];
        convertedPixels[i + 1] = pixels[i + 1];
        convertedPixels[i + 2] = pixels[i];
        convertedPixels[i + 3] = pixels[i + 3];
      }

      final comp = Completer<ui.Image>();
      ui.decodeImageFromPixels(convertedPixels, pdfImage.width, pdfImage.height,
          ui.PixelFormat.rgba8888, (img) => comp.complete(img));
      final uiImage = await comp.future;
      try {
        final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        if (mounted && byteData != null) {
          setState(() {
            _pageBytes = byteData.buffer.asUint8List();
            _loading = false; _failed = false; _retries = 0;
          });
        }
      } finally {
        uiImage.dispose();
      }
    } catch (e) {
      if (mounted) {
        if (_retries < _maxRetries) {
          _retries++;
          await Future.delayed(Duration(milliseconds: 500 * _retries));
          _renderSem.release();
          return _renderPage();
        }
        setState(() { _loading = false; _failed = true; });
      }
    } finally {
      _renderSem.release();
    }
  }

  Offset _norm(Offset local, Size size) =>
      Offset(local.dx / size.width, local.dy / size.height);

  bool get _isRectTool =>
      widget.tool == AnnotationTool.highlight ||
      widget.tool == AnnotationTool.underline ||
      widget.tool == AnnotationTool.strikethrough ||
      widget.tool == AnnotationTool.redaction ||
      widget.tool == AnnotationTool.clauseBookmark;

  AnnotationType? get _rectType => switch (widget.tool) {
    AnnotationTool.highlight     => AnnotationType.highlight,
    AnnotationTool.underline     => AnnotationType.underline,
    AnnotationTool.strikethrough => AnnotationType.strikethrough,
    _                            => null,
  };

  Color get _toolColor => switch (widget.tool) {
    AnnotationTool.highlight     => const Color(0xFFFFD600),
    AnnotationTool.underline     => const Color(0xFF38BDF8),
    AnnotationTool.strikethrough => const Color(0xFFF87171),
    AnnotationTool.redaction     => Colors.black,
    _                            => widget.annotationColor,
  };

  bool get _annotating =>
      widget.tool != AnnotationTool.view || widget.pendingSignature != null;

  void _onTap(TapDownDetails d, Size size) {
    final norm = _norm(d.localPosition, size);
    
    if (widget.tool == AnnotationTool.textStamp) {
      _showTextEditor(context, norm);
      return;
    }
    
    if (widget.pendingSignature != null) {
      widget.onSignaturePlaced(SignatureOverlay(
        id: UniqueKey().toString(), imageBytes: widget.pendingSignature!,
        pageIndex: widget.pageIndex,
        normPosition: Offset((norm.dx - 0.175).clamp(0.0, 0.65), (norm.dy - 0.035).clamp(0.0, 0.93)),
        normSize: widget.isInitialMode ? const Size(0.18, 0.05) : const Size(0.38, 0.08),
        isInitials: widget.isInitialMode));
      return;
    }
    
    for (final note in widget.notes) {
      final nx = note.normPosition.dx * size.width;
      final ny = note.normPosition.dy * size.height;
      if ((d.localPosition - Offset(nx, ny)).distance < size.width * 0.07) {
        widget.onNoteToggled(note.id, !note.isExpanded); return;
      }
    }
    if (widget.tool == AnnotationTool.stickyNote) _showNoteDialog(context, norm);
    setState(() => _selectedSigId = null);
  }

  void _showTextEditor(BuildContext ctx, Offset normPos) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: TextEditorOverlay(
          onSave: (text, style) {
            widget.onTextEditAdded(TextEditAnnotation(
              id: UniqueKey().toString(),
              pageIndex: widget.pageIndex,
              normPosition: normPos,
              text: text,
              color: style.color ?? widget.annotationColor,
              fontSize: style.fontSize ?? 14,
              isBold: style.fontWeight == FontWeight.bold,
              isItalic: style.fontStyle == FontStyle.italic,
            ));
            Navigator.pop(dialogCtx);
          },
          onCancel: () => Navigator.pop(dialogCtx),
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails d, Size size) {
    if (widget.tool == AnnotationTool.ink) {
      setState(() { _strokePoints..clear()..add(_norm(d.localPosition, size)); });
    } else if (_isRectTool) {
      setState(() { _dragStart = d.localPosition; _dragCurrent = d.localPosition; });
    }
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    if (widget.tool == AnnotationTool.ink) {
      setState(() => _strokePoints.add(_norm(d.localPosition, size)));
    } else if (_isRectTool) {
      setState(() => _dragCurrent = d.localPosition);
    }
  }

  void _onPanEnd(DragEndDetails _, Size size) {
    if (widget.tool == AnnotationTool.ink && _strokePoints.length >= 2) {
      widget.onInkStrokeAdded(InkStroke(points: List.from(_strokePoints),
          color: widget.annotationColor, normWidth: widget.inkStrokeWidth));
      setState(() => _strokePoints.clear()); return;
    }
    if (_isRectTool && _dragStart != null && _dragCurrent != null) {
      final r = Rect.fromPoints(_norm(_dragStart!, size), _norm(_dragCurrent!, size));
      if (r.width > 0.01 && r.height > 0.005) {
        switch (widget.tool) {
          case AnnotationTool.redaction:
            widget.onRedactionAdded(RedactionRect(id: UniqueKey().toString(), pageIndex: widget.pageIndex, normRect: r));
          case AnnotationTool.clauseBookmark:
            _showBookmarkDialog(context, r);
          default:
            if (_rectType != null) widget.onRectAdded(RectAnnotation(
                id: UniqueKey().toString(), pageIndex: widget.pageIndex, normRect: r, color: _toolColor, type: _rectType!));
        }
      }
      setState(() { _dragStart = null; _dragCurrent = null; });
    }
  }

  Future<void> _showNoteDialog(BuildContext ctx, Offset normPos) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: DS.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Note', style: TextStyle(color: Colors.white)),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(hintText: 'Type your note…',
            hintStyle: const TextStyle(color: Colors.white38), filled: true,
            fillColor: Colors.white.withOpacity(0.07),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), style: FilledButton.styleFrom(backgroundColor: DS.indigo), child: const Text('Add')),
        ]));
    if (text != null && text.trim().isNotEmpty) {
      widget.onNoteAdded(StickyNote(id: UniqueKey().toString(), pageIndex: widget.pageIndex, normPosition: normPos,
          text: text.trim(), color: const Color(0xFFFB923C)));
    }
  }

  Future<void> _showBookmarkDialog(BuildContext ctx, Rect normRect) async {
    const labels = ['Payment Terms','Liability','Termination','Confidentiality','Indemnification','Governing Law'];
    const colors = [DS.indigo, DS.green, DS.orange, DS.red, Color(0xFF3B82F6), DS.purple];
    String sel = labels.first;
    await showDialog<void>(context: ctx,
      builder: (_) => StatefulBuilder(builder: (c2, ss) => AlertDialog(
        backgroundColor: DS.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clause Label', style: TextStyle(color: Colors.white)),
        content: Wrap(spacing: 8, runSpacing: 8,
          children: labels.map((lbl) => GestureDetector(onTap: () => ss(() => sel = lbl),
            child: AnimatedContainer(duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: sel == lbl ? DS.indigo : Colors.white10,
                  borderRadius: BorderRadius.circular(8), border: Border.all(color: sel == lbl ? DS.indigo : Colors.white24)),
              child: Text(lbl, style: const TextStyle(color: Colors.white, fontSize: 12))))).toList()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c2), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          FilledButton(onPressed: () {
            final idx = labels.indexOf(sel);
            widget.onBookmarkAdded(ClauseBookmark(id: UniqueKey().toString(),
                pageIndex: widget.pageIndex, normRect: normRect, label: sel,
                color: colors[idx.clamp(0, colors.length - 1)]));
            Navigator.pop(c2);
          }, style: FilledButton.styleFrom(backgroundColor: DS.indigo), child: const Text('Add')),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    final page     = widget.document.pages[widget.pageIndex];
    final displayH = widget.displayWidth / (page.width / page.height);
    return SizedBox(
      width: widget.displayWidth,
      height: displayH,
      child: LayoutBuilder(builder: (_, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(children: [
          SizedBox.expand(child: _buildImage()),
          SizedBox.expand(child: _buildAnnotationLayer(size)),
          ...widget.signatures.map((s) => _buildSigOverlay(s, size)),
          ...widget.textEdits.map((t) => _buildTextEdit(t, size)),
        ]);
      }),
    );
  }

  Widget _buildTextEdit(TextEditAnnotation textEdit, Size pageSize) {
    return Positioned(
      left: textEdit.normPosition.dx * pageSize.width,
      top: textEdit.normPosition.dy * pageSize.height,
      child: Text(textEdit.text, style: TextStyle(
        fontSize: textEdit.fontSize, color: textEdit.color,
        fontWeight: textEdit.isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: textEdit.isItalic ? FontStyle.italic : FontStyle.normal,
        fontFamily: textEdit.fontFamily)),
    );
  }

  Widget _buildImage() {
    if (_loading) return Container(color: Colors.white,
        child: const Center(child: SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(color: DS.indigo, strokeWidth: 2))));
    if (_failed) return Container(color: const Color(0xFF1A1A2E),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.broken_image_outlined, size: 32, color: Colors.white.withOpacity(0.2)), const SizedBox(height: 8),
          FilledButton.icon(onPressed: () { _retries = 0; _renderPage(); },
              icon: const Icon(Icons.refresh_rounded, size: 14), label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: DS.indigo.withOpacity(0.7), visualDensity: VisualDensity.compact))])));
    if (_pageBytes == null) return Container(color: Colors.white);
    
    // ✅ Use InteractiveViewer here for natural zoom feel
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 5.0,
      child: Image.memory(_pageBytes!, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }

  Widget _buildAnnotationLayer(Size size) {
    Rect? draftNorm;
    if (_dragStart != null && _dragCurrent != null && _isRectTool) {
      draftNorm = Rect.fromPoints(_norm(_dragStart!, size), _norm(_dragCurrent!, size));
    }
    InkStroke? active;
    if (widget.tool == AnnotationTool.ink && _strokePoints.length >= 2) {
      active = InkStroke(points: List.from(_strokePoints), color: widget.annotationColor, normWidth: widget.inkStrokeWidth);
    }
    return GestureDetector(
      behavior: _annotating ? HitTestBehavior.opaque : HitTestBehavior.translucent,
      onTapDown:   _annotating ? (d) => _onTap(d, size) : null,
      onPanStart:  _annotating ? (d) => _onPanStart(d, size) : null,
      onPanUpdate: _annotating ? (d) => _onPanUpdate(d, size) : null,
      onPanEnd:    _annotating ? (d) => _onPanEnd(d, size) : null,
      child: RepaintBoundary(child: CustomPaint(size: size,
        painter: AnnotationPainter(rects: widget.rects, ink: widget.ink,
          activeStroke: active, notes: widget.notes, textStamps: widget.textStamps,
          redactions: widget.redactions, clauseBookmarks: widget.clauseBookmarks,
          draftRect: draftNorm, draftType: widget.tool == AnnotationTool.redaction ? null : _rectType, draftColor: _toolColor))),
    );
  }

  Widget _buildSigOverlay(SignatureOverlay sig, Size pageSize) {
    final isSel = sig.id == _selectedSigId;
    const hs = 24.0;
    return Positioned(
      left: sig.normPosition.dx * pageSize.width, top: sig.normPosition.dy * pageSize.height,
      child: GestureDetector(
        onTap: () => setState(() => _selectedSigId = sig.id),
        onPanUpdate: (d) => widget.onSignatureMoved(sig.id, Offset(
          (sig.normPosition.dx + d.delta.dx / pageSize.width).clamp(0.0, 1.0 - sig.normSize.width),
          (sig.normPosition.dy + d.delta.dy / pageSize.height).clamp(0.0, 1.0 - sig.normSize.height))),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: sig.normSize.width * pageSize.width, height: sig.normSize.height * pageSize.height,
            decoration: BoxDecoration(border: Border.all(color: isSel ? DS.indigo : Colors.transparent, width: 2.0), borderRadius: BorderRadius.circular(3)),
            child: Image.memory(sig.imageBytes, fit: BoxFit.contain)),
          if (isSel) ...[
            Positioned(top: -hs/2, right: -hs/2,
              child: _Handle(icon: Icons.close_rounded, color: DS.red, size: hs, onTap: () => widget.onSignatureDeleted(sig.id))),
            Positioned(bottom: -hs/2, right: -hs/2,
              child: _Handle(icon: Icons.open_in_full_rounded, color: DS.indigo, size: hs,
                onPan: (d) => widget.onSignatureResized(sig.id, Size(
                  (sig.normSize.width + d.delta.dx / pageSize.width).clamp(0.04, 0.9),
                  (sig.normSize.height + d.delta.dy / pageSize.height).clamp(0.02, 0.5))))),
          ],
        ]),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  final IconData icon; final Color color; final double size;
  final VoidCallback? onTap; final void Function(DragUpdateDetails)? onPan;
  const _Handle({required this.icon, required this.color, required this.size, this.onTap, this.onPan});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, onPanUpdate: onPan,
    child: Container(width: size, height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)]),
      child: Icon(icon, size: size * 0.55, color: Colors.white)));
}

class _Semaphore {
  final int _max; int _count = 0;
  final _q = <Completer<void>>[];
  _Semaphore(this._max);
  Future<void> acquire() async {
    if (_count < _max) { _count++; return; }
    final c = Completer<void>(); _q.add(c); await c.future; _count++;
  }
  void release() { _count--; if (_q.isNotEmpty) _q.removeAt(0).complete(); }
}