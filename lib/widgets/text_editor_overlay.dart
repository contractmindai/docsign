import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../widgets/ds.dart';

class TextEditorOverlay extends StatefulWidget {
  final String? initialText;

  /// When true, the overlay opens with the formatting toolbar collapsed
  /// behind a "Change formatting" link instead of shown up front. Used when
  /// editing an existing run, where the default expectation is a plain text
  /// fix that preserves the document's original appearance rather than a
  /// deliberate restyle. Free-standing text stamps (no "original" appearance
  /// to preserve) should leave this false.
  final bool startPlain;

  /// Font size the editor opens with. Defaults to 14 when the caller
  /// doesn't supply the run's real size. This is a starting value only —
  /// whatever the user leaves in the toolbar is what gets saved.
  final double initialFontSize;

  /// Called with (text, style, formattingChanged). `formattingChanged` is
  /// true only if the user opened/touched the formatting controls — callers
  /// use this to decide between an in-place edit that preserves the
  /// original font exactly, versus a restyled overlay replacement.
  final void Function(String text, TextStyle style, bool formattingChanged)
      onSave;
  final VoidCallback onCancel;

  const TextEditorOverlay({
    super.key,
    this.initialText,
    this.startPlain = false,
    this.initialFontSize = 14,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<TextEditorOverlay> createState() => _TextEditorOverlayState();
}

class _TextEditorOverlayState extends State<TextEditorOverlay> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  /// Initialised from [TextEditorOverlay.initialFontSize]. Not a const so
  /// a caller can seed it with the size of the run being edited.
  late double _fontSize = widget.initialFontSize;

  Color _textColor = Colors.black;
  bool _isBold = false;
  bool _isItalic = false;
  String _fontFamily = 'Inter';

  late bool _formattingExpanded = !widget.startPlain;
  bool _formattingTouched = false;

  static const _fonts = ['Inter', 'Times New Roman', 'Courier', 'Georgia'];
  static const _fontSizes = [
    8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 56, 64
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  TextStyle get _currentStyle => TextStyle(
        fontSize: _fontSize,
        color: _textColor,
        fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
        fontFamily: _fontFamily,
      );

  @override
  Widget build(BuildContext context) {
    // Responsive width: never wider than the viewport minus a margin.
    // Without this, the 340dp container overflows on 320dp-wide phones
    // and the math.max() clamp guard in PageTextRunsOverlay can't help —
    // the dialog still can't fit.
    final double editorWidth =
        math.min(340.0, MediaQuery.of(context).size.width - 16);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: editorWidth,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Toolbar ──────────────────────────────────────────────
            if (_formattingExpanded)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2E),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    _buildToolButton(
                      icon: Icons.format_bold,
                      isActive: _isBold,
                      onTap: () => setState(() {
                        _isBold = !_isBold;
                        _formattingTouched = true;
                      }),
                      tooltip: 'Bold',
                      color: DS.indigo,
                    ),
                    _buildToolButton(
                      icon: Icons.format_italic,
                      isActive: _isItalic,
                      onTap: () => setState(() {
                        _isItalic = !_isItalic;
                        _formattingTouched = true;
                      }),
                      tooltip: 'Italic',
                      color: DS.indigo,
                    ),
                    const Spacer(),
                    _buildFontFamilySelector(),
                    const SizedBox(width: 6),
                    _buildFontSizeSelector(),
                    const SizedBox(width: 6),
                    _buildColorPicker(),
                  ],
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2E),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_fix_high_rounded,
                        size: 14, color: Colors.white38),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Keeps the original look · ${_fontSize.toInt()}pt',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _formattingExpanded = true;
                        _formattingTouched = true;
                      }),
                      child: const Text(
                        'Change formatting',
                        style: TextStyle(
                          color: DS.indigo,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Text input ────────────────────────────────────────────
            Container(
              constraints:
                  const BoxConstraints(minHeight: 60, maxHeight: 200),
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                style: _currentStyle.copyWith(color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Type your text here...',
                  hintStyle: TextStyle(color: Colors.white38),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (text) {
                  if (text.trim().isNotEmpty) {
                    widget.onSave(
                        text.trim(), _currentStyle, _formattingTouched);
                  }
                },
              ),
            ),

            // ── Presets ───────────────────────────────────────────────
            if (_formattingExpanded)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(children: [
                  _buildPreset(
                    'Title',
                    () => setState(() {
                      _fontSize = 24;
                      _isBold = true;
                      _isItalic = false;
                      _textColor = DS.indigo;
                      _formattingTouched = true;
                    }),
                  ),
                  const SizedBox(width: 6),
                  _buildPreset(
                    'Subtitle',
                    () => setState(() {
                      _fontSize = 16;
                      _isBold = false;
                      _isItalic = true;
                      _textColor = Colors.grey;
                      _formattingTouched = true;
                    }),
                  ),
                  const SizedBox(width: 6),
                  _buildPreset(
                    'Body',
                    () => setState(() {
                      _fontSize = 12;
                      _isBold = false;
                      _isItalic = false;
                      _textColor = Colors.white;
                      _formattingTouched = true;
                    }),
                  ),
                ]),
              ),

            // ── Cancel / Apply ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_controller.text.trim().isNotEmpty) {
                        widget.onSave(
                          _controller.text.trim(),
                          _currentStyle,
                          _formattingTouched,
                        );
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: DS.indigo,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontSizeSelector() {
    // If the run's real size isn't one of the presets, insert it in sorted
    // order so the dropdown reflects the current value.
    final sizes = [..._fontSizes];
    final current = _fontSize.round();
    if (!sizes.contains(current)) {
      sizes.add(current);
      sizes.sort();
    }

    return PopupMenuButton<double>(
      tooltip: 'Font size',
      offset: const Offset(0, 40),
      color: const Color(0xFF2C2C2E),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${_fontSize.toInt()}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
        ]),
      ),
      onSelected: (size) => setState(() {
        _fontSize = size;
        _formattingTouched = true;
      }),
      itemBuilder: (_) => sizes
          .map((s) => PopupMenuItem(
                value: s.toDouble(),
                child: Text('$s pt',
                    style: TextStyle(
                        fontSize: s.toDouble().clamp(10, 20).toDouble())),
              ))
          .toList(),
    );
  }

  Widget _buildFontFamilySelector() {
    return PopupMenuButton<String>(
      tooltip: 'Font',
      offset: const Offset(0, 40),
      color: const Color(0xFF2C2C2E),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            _fontFamily,
            style: TextStyle(
              fontSize: 12,
              fontFamily: _fontFamily,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
        ]),
      ),
      onSelected: (font) => setState(() {
        _fontFamily = font;
        _formattingTouched = true;
      }),
      itemBuilder: (_) => _fonts
          .map((f) => PopupMenuItem(
                value: f,
                child: Text(f, style: TextStyle(fontFamily: f, fontSize: 14)),
              ))
          .toList(),
    );
  }

  Widget _buildColorPicker() {
    return PopupMenuButton<Color>(
      tooltip: 'Text color',
      offset: const Offset(0, 40),
      color: const Color(0xFF2C2C2E),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _textColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 2),
        ),
      ),
      onSelected: (color) => setState(() {
        _textColor = color;
        _formattingTouched = true;
      }),
      itemBuilder: (_) => [
        Colors.white,
        Colors.black,
        Colors.red.shade700,
        Colors.blue.shade700,
        Colors.green.shade700,
        Colors.orange.shade700,
        Colors.purple.shade700,
        DS.indigo,
        Colors.grey.shade700,
      ]
          .map((c) => PopupMenuItem(
                value: c,
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Text(_colorName(c), style: const TextStyle(fontSize: 13)),
                ]),
              ))
          .toList(),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required String tooltip,
    Color? color,
  }) {
    final tint = color ?? DS.indigo;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? tint.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? tint : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _buildPreset(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: DS.indigo.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: DS.indigo.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: DS.indigo,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _colorName(Color c) {
    if (c == Colors.black) return 'Black';
    if (c == Colors.white) return 'White';
    if (c == Colors.red.shade700) return 'Red';
    if (c == Colors.blue.shade700) return 'Blue';
    if (c == Colors.green.shade700) return 'Green';
    if (c == Colors.orange.shade700) return 'Orange';
    if (c == Colors.purple.shade700) return 'Purple';
    if (c == DS.indigo) return 'Indigo';
    return 'Grey';
  }
}