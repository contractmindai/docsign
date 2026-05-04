import 'package:flutter/material.dart';
import '../widgets/ds.dart';

class TextEditorOverlay extends StatefulWidget {
  final String? initialText;
  final Function(String text, TextStyle style) onSave;
  final VoidCallback onCancel;

  const TextEditorOverlay({
    super.key,
    this.initialText,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<TextEditorOverlay> createState() => _TextEditorOverlayState();
}

class _TextEditorOverlayState extends State<TextEditorOverlay> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  
  double _fontSize = 14;
  Color _textColor = Colors.black;
  bool _isBold = false;
  bool _isItalic = false;
  String _fontFamily = 'Inter';
  
  static const _fonts = ['Inter', 'Times New Roman', 'Courier', 'Georgia'];
  static const _fontSizes = [10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 48];

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
  return Container(
    width: 320,
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),  // ✅ Dark background like the app
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),  // ✅ Slightly lighter toolbar
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          // ... rest of toolbar
        ),
        // Text input
        Container(
          constraints: const BoxConstraints(minHeight: 60, maxHeight: 200),
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            style: _currentStyle.copyWith(color: Colors.white),  // ✅ White text on dark
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Type your text here...',
              hintStyle: TextStyle(color: Colors.white38),  // ✅ Visible hint
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (text) {
              if (text.trim().isNotEmpty) widget.onSave(text.trim(), _currentStyle);
            },
          ),
        ),
        // Presets
        Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(children: [
            _buildPreset('Title', () => setState(() { _fontSize = 24; _isBold = true; _isItalic = false; _textColor = DS.indigo; })),
            const SizedBox(width: 6),
            _buildPreset('Subtitle', () => setState(() { _fontSize = 16; _isBold = false; _isItalic = true; _textColor = Colors.grey[400]!; })),
            const SizedBox(width: 6),
            _buildPreset('Body', () => setState(() { _fontSize = 12; _isBold = false; _isItalic = false; _textColor = Colors.white; })),
          ]),
        ),
        // ✅ NEW: Cancel + Apply buttons
    Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              if (_controller.text.trim().isNotEmpty) {
                widget.onSave(_controller.text.trim(), _currentStyle);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
      ],
    ),
  );
}


  Widget _buildFontSizeSelector() {
    return PopupMenuButton<double>(
      tooltip: 'Font size',
      offset: const Offset(0, 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${_fontSize.toInt()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[600]),
        ]),
      ),
      onSelected: (size) => setState(() => _fontSize = size),
      itemBuilder: (_) => _fontSizes.map((s) => PopupMenuItem(value: s.toDouble(), child: Text('$s pt', style: TextStyle(fontSize: s.toDouble())))).toList(),
    );
  }

  Widget _buildFontFamilySelector() {
    return PopupMenuButton<String>(
      tooltip: 'Font',
      offset: const Offset(0, 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_fontFamily, style: TextStyle(fontSize: 12, fontFamily: _fontFamily, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[600]),
        ]),
      ),
      onSelected: (font) => setState(() => _fontFamily = font),
      itemBuilder: (_) => _fonts.map((f) => PopupMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f, fontSize: 14)))).toList(),
    );
  }

  Widget _buildColorPicker() {
    return PopupMenuButton<Color>(
      tooltip: 'Text color',
      offset: const Offset(0, 40),
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: _textColor, shape: BoxShape.circle, border: Border.all(color: Colors.grey[300]!, width: 2)),
      ),
      onSelected: (color) => setState(() => _textColor = color),
      itemBuilder: (_) => [
        Colors.black, Colors.red.shade700, Colors.blue.shade700, Colors.green.shade700,
        Colors.orange.shade700, Colors.purple.shade700, DS.indigo, Colors.grey.shade700,
      ].map((c) => PopupMenuItem(value: c, child: Row(children: [
        Container(width: 24, height: 24, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Text(_colorName(c), style: const TextStyle(fontSize: 13)),
      ]))).toList(),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required String tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? (color ?? Colors.black).withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 18, color: isActive ? (color ?? Colors.black) : (color ?? Colors.grey[600])),
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
          color: DS.indigo.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: DS.indigo.withOpacity(0.2)),
        ),
        child: Text(label, style: TextStyle(color: DS.indigo, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }

  String _colorName(Color c) {
    if (c == Colors.black) return 'Black';
    if (c == Colors.red.shade700) return 'Red';
    if (c == Colors.blue.shade700) return 'Blue';
    if (c == Colors.green.shade700) return 'Green';
    if (c == Colors.orange.shade700) return 'Orange';
    if (c == Colors.purple.shade700) return 'Purple';
    if (c == DS.indigo) return 'Indigo';
    return 'Grey';
  }
}