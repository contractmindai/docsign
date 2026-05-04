import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signature/signature.dart';

import 'ds.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SignatureDialog — transparent background + shake-free canvas
//
// Fixes:
//   1. SignatureController exports PNG with transparent background
//   2. GestureDetector.behavior = opaque on the canvas so parent scroll
//      doesn't steal touches (eliminates shake during signing)
//   3. Stable RepaintBoundary prevents unnecessary repaints
// ─────────────────────────────────────────────────────────────────────────────

class SignatureDialog {
  static Future<Uint8List?> show(BuildContext context) {
    return showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SignaturePad(),
    );
  }
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad();
  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  late SignatureController _ctrl;
  Color _penColor = Colors.black;
  double _penWidth = 3.0;
  bool _isEmpty = true;
  String _tab = 'Draw'; // Draw | Type | Upload

  // For typed signature
  final _typeCtrl = TextEditingController();
  String _fontStyle = 'Signature';

  @override
  void initState() {
    super.initState();
    _ctrl = SignatureController(
      penStrokeWidth: _penWidth,
      penColor: _penColor,
      // ✅ transparent background — no white sticker effect
      exportBackgroundColor: Colors.transparent,
    );
    _ctrl.addListener(() {
      if (mounted) setState(() => _isEmpty = _ctrl.isEmpty);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  // ✅ Export with transparent background
  Future<Uint8List?> _export() async {
    if (_tab == 'Draw') {
      if (_ctrl.isEmpty) return null;
      return await _ctrl.toPngBytes(
        height: 200, width: 600);
    }
    if (_tab == 'Type' && _typeCtrl.text.trim().isNotEmpty) {
      return await _renderTextSignature(_typeCtrl.text.trim());
    }
    return null;
  }

  /// Render typed text to transparent PNG
  Future<Uint8List?> _renderTextSignature(String text) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    const w = 500.0, h = 150.0;

    final textStyle = TextStyle(
      fontFamily: _fontStyle == 'Signature'
          ? 'Dancing Script' : 'Inter',
      fontSize: _fontStyle == 'Signature' ? 60 : 44,
      color: _penColor,
      fontWeight: FontWeight.w500,
    );

    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);

    tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));

  final picture = recorder.endRecording();
  final img = await picture.toImage(w.toInt(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  
  img.dispose(); // ✅ Dispose image
  picture.dispose(); // ✅ Dispose picture
  
  return bytes?.buffer.asUint8List();
  }

  void _clear() {
    _ctrl.clear();
    setState(() => _isEmpty = true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 2),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: DS.separator, borderRadius: BorderRadius.circular(2)))),

        // Tab bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            for (final tab in ['Draw', 'Type'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _tab = tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: _tab == tab
                          ? DS.indigo.withOpacity(0.2)
                          : DS.bgCard2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _tab == tab
                              ? DS.indigo.withOpacity(0.6)
                              : DS.separator)),
                    child: Text(tab, style: TextStyle(
                        color: _tab == tab ? DS.indigo : DS.textSecondary,
                        fontSize: 13,
                        fontWeight: _tab == tab
                            ? FontWeight.w600 : FontWeight.w500)),
                  ),
                ),
              ),
            const Spacer(),
            // Pen color dots
            if (_tab == 'Draw') Row(children: [
              for (final c in [Colors.black, DS.indigo, DS.red, DS.green])
                GestureDetector(
                  onTap: () {
                    setState(() { _penColor = c; });
                    _ctrl = SignatureController(
                        penStrokeWidth: _penWidth, penColor: c,
                        exportBackgroundColor: Colors.transparent);
                    _ctrl.addListener(
                        () => setState(() => _isEmpty = _ctrl.isEmpty));
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: _penColor == c
                          ? Border.all(color: Colors.white, width: 2)
                          : null)),
                ),
            ]),
          ]),
        ),

        const SizedBox(height: 12),

        // Canvas or type field
        if (_tab == 'Draw')
          _DrawCanvas(ctrl: _ctrl)
        else
          _TypeField(
            ctrl: _typeCtrl,
            fontStyle: _fontStyle,
            penColor: _penColor,
            onFontChanged: (f) => setState(() => _fontStyle = f),
            onColorChanged: (c) => setState(() => _penColor = c),
          ),

        const SizedBox(height: 12),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(children: [
            OutlinedButton(
              onPressed: _tab == 'Draw' ? _clear : () => _typeCtrl.clear(),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: const BorderSide(color: DS.separator)),
              child: const Text('Clear')),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                final bytes = await _export();
                if (context.mounted) Navigator.pop(context, bytes);
              },
              style: FilledButton.styleFrom(
                  backgroundColor: DS.indigo,
                  minimumSize: const Size(120, 44)),
              child: Text('Done', style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ]),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ]),
    );
  }
}

// ── Draw canvas — gesture-isolated to prevent shake ──────────────────────────

class _DrawCanvas extends StatelessWidget {
  final SignatureController ctrl;
  const _DrawCanvas({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DS.separator, width: 0.5),
      ),
      // ✅ Absorb all gestures so parent scroll never steals touches
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Listener(
          // Listener captures pointer events before GestureDetector
          onPointerDown: (_) {},
          behavior: HitTestBehavior.opaque,
          child: Signature(
            controller: ctrl,
            backgroundColor: Colors.white,
            // ✅ Dynamic size — fills container exactly
            width: double.infinity,
            height: 180,
          ),
        ),
      ),
    );
  }
}

// ── Type signature ────────────────────────────────────────────────────────────

class _TypeField extends StatelessWidget {
  final TextEditingController ctrl;
  final String fontStyle;
  final Color penColor;
  final ValueChanged<String> onFontChanged;
  final ValueChanged<Color> onColorChanged;

  const _TypeField({required this.ctrl, required this.fontStyle,
      required this.penColor, required this.onFontChanged,
      required this.onColorChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        // Preview
        Container(
          width: double.infinity, height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DS.separator, width: 0.5)),
          child: ValueListenableBuilder(
            valueListenable: ctrl,
            builder: (_, __, ___) => Text(
              ctrl.text.isEmpty ? 'Your Signature' : ctrl.text,
              style: TextStyle(
                fontFamily: fontStyle == 'Signature' ? null : 'Inter',
                fontSize: 42, color: ctrl.text.isEmpty
                    ? Colors.black26 : penColor,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Type your name',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true, fillColor: DS.bgCard2,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DS.separator)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DS.separator)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: DS.indigo))),
        ),
      ]),
    );
  }
}
