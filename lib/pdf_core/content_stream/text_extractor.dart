import 'dart:math';
import 'dart:typed_data';
import 'cs_lexer.dart';
import 'text_state.dart';
import 'cmap_parser.dart';

class ExtractedTextChunk {
  final String text;
  final Rectangle<double> bounds;
  final String fontReference;
  final double fontSize;
  ExtractedTextChunk({
    required this.text,
    required this.bounds,
    required this.fontReference,
    required this.fontSize,
  });
}

class PdfTextExtractor {
  final PdfTextState _state = PdfTextState();
  final List<dynamic> _operandStack = [];

  List<ExtractedTextChunk> extractChunks(
      Uint8List uncompressedContentBytes,
      {Map<String, ToUnicodeCMap>? cmaps}) {
    final results = <ExtractedTextChunk>[];
    final lexer = ContentStreamLexer(uncompressedContentBytes);

    while (true) {
      final token = lexer.nextToken();
      if (token == null) break;
      if (token.type != ContentStreamTokenType.operator) {
        _operandStack.add(token.value);
      } else {
        _executeOperator(token.value as String, results, cmaps);
        _operandStack.clear();
      }
    }
    return results;
  }

  void _executeOperator(String op, List<ExtractedTextChunk> results,
      Map<String, ToUnicodeCMap>? cmaps) {
    switch (op) {
      case 'q': _state.saveGraphicsState(); break;
      case 'Q': _state.restoreGraphicsState(); break;
      case 'cm':
        if (_operandStack.length >= 6) {
          _state.concatCtm(_d(0), _d(1), _d(2), _d(3), _d(4), _d(5));
        }
        break;
      case 'BT': _state.beginTextBlock(); break;
      case 'ET': break;
      case 'Tc': if (_operandStack.isNotEmpty) _state.charSpacing = _d(last); break;
      case 'Tw': if (_operandStack.isNotEmpty) _state.wordSpacing = _d(last); break;
      case 'Tz': if (_operandStack.isNotEmpty) _state.horizontalScaling = _d(last); break;
      case 'TL': if (_operandStack.isNotEmpty) _state.leading = _d(last); break;
      case 'Ts': if (_operandStack.isNotEmpty) _state.textRise = _d(last); break;
      case 'Tf':
        if (_operandStack.length >= 2) {
          _state.fontRef = '/' + _operandStack[_operandStack.length - 2].toString();
          _state.fontSize = _d(last);
        }
        break;
      case 'Tm':
        if (_operandStack.length >= 6) {
          _state.setTextMatrix(_d(0), _d(1), _d(2), _d(3), _d(4), _d(5));
        }
        break;
      case 'Td':
        if (_operandStack.length >= 2) _state.moveTextLine(_d(0), _d(1));
        break;
      case 'T*': _state.nextLine(); break;
      case 'Tj':
        if (_operandStack.isNotEmpty && _operandStack.last is List<int>) {
          _processStringRender(_operandStack.last as List<int>, results, cmaps);
        }
        break;
      case 'TJ':
        if (_operandStack.isNotEmpty && _operandStack.last is List<dynamic>) {
          final arr = _operandStack.last as List<dynamic>;
          for (final element in arr) {
            if (element is List<int>) {
              _processStringRender(element, results, cmaps);
            } else if (element is num) {
              _state.advanceTJ(element.toDouble());
            }
          }
        }
        break;
    }
  }

  void _processStringRender(List<int> stringBytes,
      List<ExtractedTextChunk> results, Map<String, ToUnicodeCMap>? cmaps) {
    final cmap = cmaps?[_state.fontRef];
    String plainText;
    if (cmap != null) {
      final buffer = StringBuffer();
      for (final b in stringBytes) {
        buffer.write(cmap.lookup(b) ?? String.fromCharCode(b));
      }
      plainText = buffer.toString();
    } else {
      plainText = String.fromCharCodes(stringBytes);
    }

    final widthEm = plainText.length * 0.6;
    final trm = _state.textRenderingMatrix;
    final origin = trm.transformPoint(0, 0);
    final end = trm.transformPoint(widthEm, 0);
    final asc = trm.transformPoint(0, 0.75);
    final desc = trm.transformPoint(0, -0.2);

    final left = min(min(origin.x, end.x), min(asc.x, desc.x));
    final right = max(max(origin.x, end.x), max(asc.x, desc.x));
    final bottom = min(min(origin.y, end.y), min(asc.y, desc.y));
    final top = max(max(origin.y, end.y), max(asc.y, desc.y));

    results.add(ExtractedTextChunk(
      text: plainText,
      bounds: Rectangle(left, bottom, right - left, top - bottom),
      fontReference: _state.fontRef,
      fontSize: _state.fontSize,
    ));
    _state.advanceBy(widthEm);
  }

  dynamic get last => _operandStack.last;
  double _d(int i) => i < _operandStack.length && _operandStack[i] is num
      ? (_operandStack[i] as num).toDouble() : 0.0;
}