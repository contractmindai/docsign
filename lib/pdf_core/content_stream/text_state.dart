import 'dart:math';

class PdfMatrix {
  final double a, b, c, d, e, f;
  const PdfMatrix(this.a, this.b, this.c, this.d, this.e, this.f);
  factory PdfMatrix.identity() => const PdfMatrix(1, 0, 0, 1, 0, 0);

  PdfMatrix multiply(PdfMatrix o) => PdfMatrix(
        a * o.a + b * o.c,
        a * o.b + b * o.d,
        c * o.a + d * o.c,
        c * o.b + d * o.d,
        e * o.a + f * o.c + o.e,
        e * o.b + f * o.d + o.f,
      );

  Point<double> transformPoint(double x, double y) =>
      Point(x * a + y * c + e, x * b + y * d + f);
}

class PdfTextState {
  PdfMatrix ctm = PdfMatrix.identity();
  PdfMatrix tm = PdfMatrix.identity();
  PdfMatrix tlm = PdfMatrix.identity();
  double charSpacing = 0.0;
  double wordSpacing = 0.0;
  double horizontalScaling = 100.0;
  double leading = 0.0;
  String fontRef = '';
  double fontSize = 0.0;
  double textRise = 0.0;

  final List<_GState> _stack = [];

  void saveGraphicsState() {
    _stack.add(_GState(ctm, charSpacing, wordSpacing, horizontalScaling,
        leading, fontRef, fontSize, textRise));
  }

  void restoreGraphicsState() {
    if (_stack.isEmpty) return;
    final s = _stack.removeLast();
    ctm = s.ctm;
    charSpacing = s.charSpacing;
    wordSpacing = s.wordSpacing;
    horizontalScaling = s.horizontalScaling;
    leading = s.leading;
    fontRef = s.fontRef;
    fontSize = s.fontSize;
    textRise = s.textRise;
  }

  void concatCtm(double a, double b, double c, double d, double e, double f) {
    ctm = PdfMatrix(a, b, c, d, e, f).multiply(ctm);
  }

  void beginTextBlock() {
    tm = PdfMatrix.identity();
    tlm = PdfMatrix.identity();
  }

  void moveTextLine(double tx, double ty) {
    tlm = PdfMatrix(1, 0, 0, 1, tx, ty).multiply(tlm);
    tm = tlm;
  }

  void setTextMatrix(double a, double b, double c, double d, double e, double f) {
    tm = PdfMatrix(a, b, c, d, e, f);
    tlm = tm;
  }

  void nextLine() => moveTextLine(0, -leading);

  PdfMatrix get textRenderingMatrix {
    final th = horizontalScaling / 100.0;
    return PdfMatrix(fontSize * th, 0, 0, fontSize, 0, textRise)
        .multiply(tm)
        .multiply(ctm);
  }

  void advanceBy(double widthEm) {
    final th = horizontalScaling / 100.0;
    final tx = (widthEm * fontSize + charSpacing) * th;
    tm = PdfMatrix(1, 0, 0, 1, tx, 0).multiply(tm);
  }

  void advanceTJ(double adj) {
    final th = horizontalScaling / 100.0;
    final tx = (-adj / 1000.0) * fontSize * th;
    tm = PdfMatrix(1, 0, 0, 1, tx, 0).multiply(tm);
  }
}

class _GState {
  final PdfMatrix ctm;
  final double charSpacing, wordSpacing, horizontalScaling, leading, fontSize, textRise;
  final String fontRef;
  const _GState(this.ctm, this.charSpacing, this.wordSpacing,
      this.horizontalScaling, this.leading, this.fontRef, this.fontSize, this.textRise);
}