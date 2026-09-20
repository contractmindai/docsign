import 'dart:convert';
import 'dart:typed_data';

/// Generates PDF appearance stream content for form field widgets.
class PdfAppearanceGenerator {

  // ── Checkbox ────────────────────────────────────────────────────────────────

  /// Returns the raw stream body (without outer obj wrapper) for a checkbox
  /// appearance state. Caller wraps this with /Type /XObject /Subtype /Form /BBox.
  String generateCheckboxAppearance({required bool isChecked, required double size}) {
    final buf = StringBuffer();
    buf.write('q\r\n');
    buf.write('0.5 w 0.8 0.8 0.8 RG 1 g\r\n');
    buf.write('0 0 $size $size re b\r\n'); // filled + stroked box

    if (isChecked) {
      // Draw a bold check-mark (✓) path
      buf.write('0 g 0 G 1.5 w\r\n');
      final double m = size * 0.15;
      final double mx = size * 0.38;
      final double my = size * 0.22;
      final double tx = size * 0.62;
      final double ty = size * 0.78;
      buf.write('${_f(m)} ${_f(my)} m ${_f(mx)} ${_f(m)} l ${_f(size - m)} ${_f(ty)} l S\r\n');
    }

    buf.write('Q\r\n');
    return _wrapStream(buf.toString());
  }

  // ── Radio button ─────────────────────────────────────────────────────────────

  String generateRadioButtonAppearance({required bool isSelected, required double size}) {
    final double cx = size / 2;
    final double cy = size / 2;
    const double k = 0.5523;
    final double r = size / 2 - 0.5;

    final buf = StringBuffer();
    buf.write('q\r\n');
    buf.write('0.5 w 0.8 0.8 0.8 RG 1 g\r\n');
    buf.write(_circle(cx, cy, r, k));
    buf.write('b\r\n');

    if (isSelected) {
      final double ir = r * 0.45;
      buf.write('0 g 0 G\r\n');
      buf.write(_circle(cx, cy, ir, k));
      buf.write('f\r\n');
    }

    buf.write('Q\r\n');
    return _wrapStream(buf.toString());
  }

  // ── Signature ────────────────────────────────────────────────────────────────

  /// Generates an appearance stream for a signature field.
  ///
  /// [mode] controls what is drawn:
  ///   - 'text'  — renders [label] as italic text (e.g. a typed name)
  ///   - 'initials' — large bold initials centred in the box
  ///   - 'blank' — clears the field (empty signed state)
  ///
  /// [width] / [height] come from the field's /Rect.
  String generateSignatureAppearance({
    required double width,
    required double height,
    String mode = 'text',
    String label = '',
    double fontSize = 0, // 0 = auto-fit
  }) {
    final buf = StringBuffer();
    buf.write('q\r\n');

    // Light blue tint background
    buf.write('0.94 0.97 1 rg\r\n');
    buf.write('0 0 ${_f(width)} ${_f(height)} re f\r\n');

    // Border
    buf.write('0.2 0.4 0.8 RG 0.5 w\r\n');
    buf.write('0 0 ${_f(width)} ${_f(height)} re S\r\n');

    if (mode == 'text' && label.isNotEmpty) {
      final double fs = fontSize > 0 ? fontSize : _fitFontSize(label, width, height);
      final double y = (height - fs) / 2 + fs * 0.25;
      final escaped = _escape(label);
      buf.write('BT\r\n');
      buf.write('/Helv ${ _f(fs)} Tf\r\n');
      buf.write('0.1 0.1 0.5 rg\r\n'); // dark-blue ink colour
      buf.write('${_f(4)} ${_f(y)} Td\r\n');
      buf.write('($escaped) Tj\r\n');
      buf.write('ET\r\n');

      // Signature underline
      buf.write('0.2 0.4 0.8 RG 0.3 w\r\n');
      buf.write('4 ${_f(y - 2)} m ${_f(width - 4)} ${_f(y - 2)} l S\r\n');
    } else if (mode == 'initials' && label.isNotEmpty) {
      final double fs = _fitFontSize(label, width * 0.85, height * 0.75, minSize: 10);
      final double x = width / 2 - (label.length * fs * 0.35);
      final double y = (height - fs) / 2 + fs * 0.2;
      final escaped = _escape(label);
      buf.write('BT\r\n');
      buf.write('/Helv ${_f(fs)} Tf\r\n');
      buf.write('0.1 0.1 0.5 rg\r\n');
      buf.write('${_f(x)} ${_f(y)} Td\r\n');
      buf.write('($escaped) Tj\r\n');
      buf.write('ET\r\n');
    }

    buf.write('Q\r\n');
    return _wrapStream(buf.toString());
  }

  // ── Text field (used by field_filler when building inline AP) ───────────────

  String generateTextAppearance({
    required String text,
    required double width,
    required double height,
    String fontName = '/Helv',
    double fontSize = 0,
    String alignment = 'left', // 'left' | 'center' | 'right'
  }) {
    final double fs = fontSize > 0 ? fontSize : _fitFontSize(text, width - 4, height);
    final double y = (height - fs) / 2 + fs * 0.2;
    final escaped = _escape(text);

    double x;
    if (alignment == 'center') {
      x = width / 2 - (text.length * fs * 0.3);
    } else if (alignment == 'right') {
      x = width - 4 - text.length * fs * 0.6;
      if (x < 2) x = 2;
    } else {
      x = 2.0;
    }

    final buf = StringBuffer();
    buf.write('q\r\n');
    buf.write('BT\r\n');
    buf.write('$fontName ${_f(fs)} Tf\r\n');
    buf.write('0 g\r\n');
    buf.write('${_f(x)} ${_f(y)} Td\r\n');
    buf.write('($escaped) Tj\r\n');
    buf.write('ET\r\n');
    buf.write('Q\r\n');
    return _wrapStream(buf.toString());
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _circle(double cx, double cy, double r, double k) {
    return '${_f(cx + r)} ${_f(cy)} m\r\n'
        '${_f(cx + r)} ${_f(cy + r * k)} ${_f(cx + r * k)} ${_f(cy + r)} ${_f(cx)} ${_f(cy + r)} c\r\n'
        '${_f(cx - r * k)} ${_f(cy + r)} ${_f(cx - r)} ${_f(cy + r * k)} ${_f(cx - r)} ${_f(cy)} c\r\n'
        '${_f(cx - r)} ${_f(cy - r * k)} ${_f(cx - r * k)} ${_f(cy - r)} ${_f(cx)} ${_f(cy - r)} c\r\n'
        '${_f(cx + r * k)} ${_f(cy - r)} ${_f(cx + r)} ${_f(cy - r * k)} ${_f(cx + r)} ${_f(cy)} c\r\n';
  }

  double _fitFontSize(String text, double width, double height,
      {double minSize = 6.0}) {
    if (text.isEmpty) return 12.0;
    // Approximate: each char ~0.55 em wide
    double byWidth = width / (text.length * 0.55);
    double byHeight = height * 0.72;
    double size = byWidth < byHeight ? byWidth : byHeight;
    return size < minSize ? minSize : (size > 72 ? 72 : size);
  }

  String _wrapStream(String content) {
    final bytes = utf8.encode(content);
    return '<< /Length ${bytes.length} >>\r\nstream\r\n$content\r\nendstream';
  }

  String _f(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(3);

  String _escape(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)');
}
