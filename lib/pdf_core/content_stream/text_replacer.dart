import 'dart:typed_data';
import 'cs_lexer.dart';
import 'text_state.dart';

class TextReplacementResult {
  final Uint8List bytes;
  final int replacementCount;
  TextReplacementResult(this.bytes, this.replacementCount);
}

class PdfAdvancedTextReplacer {
  TextReplacementResult replaceText({
    required Uint8List contentBytes,
    required String targetText,
    required String replacementText,
    required double maxWidthPoints,
  }) {
    final lexer = ContentStreamLexer(contentBytes);
    final outputBuffer = BytesBuilder();
    final state = PdfTextState();
    int lastReadOffset = 0;
    final operandStack = <dynamic>[];
    final tokenStartOffsets = <int>[];
    int replacementCount = 0;

    while (true) {
      final tokenStart = lexer.offset;
      final token = lexer.nextToken();
      if (token == null) break;

      if (token.type != ContentStreamTokenType.operator) {
        operandStack.add(token.value);
        tokenStartOffsets.add(tokenStart);
      } else {
        final op = token.value as String;
        _updateState(op, operandStack, state);

        if (op == 'Tj' && operandStack.isNotEmpty) {
          final operand = operandStack.last;
          if (operand is List<int>) {
            final currentStr = String.fromCharCodes(operand);
            if (currentStr.contains(targetText)) {
              final opStart = tokenStartOffsets.last;
              _append(outputBuffer, contentBytes, lastReadOffset, opStart);
              final updated = currentStr.replaceAll(targetText, replacementText);
              outputBuffer.add(_escapeAndEncode(updated));
              lastReadOffset = lexer.offset;
              replacementCount++;
            }
          }
        } else if (op == 'TJ' && operandStack.isNotEmpty) {
          final operand = operandStack.last;
          if (operand is List<dynamic>) {
            final flatText = operand
                .whereType<List<int>>()
                .map(String.fromCharCodes)
                .join();
            if (flatText.contains(targetText)) {
              final opStart = tokenStartOffsets.isNotEmpty
                  ? tokenStartOffsets.first : tokenStart;
              _append(outputBuffer, contentBytes, lastReadOffset, opStart);
              final updated = flatText.replaceAll(targetText, replacementText);
              outputBuffer.add(_escapeAndEncode(updated));
              lastReadOffset = lexer.offset;
              replacementCount++;
            }
          }
        }
        operandStack.clear();
        tokenStartOffsets.clear();
      }
    }

    if (lastReadOffset < contentBytes.length) {
      outputBuffer.add(contentBytes.sublist(lastReadOffset));
    }
    return TextReplacementResult(outputBuffer.takeBytes(), replacementCount);
  }

  Uint8List _escapeAndEncode(String text) {
    final buffer = StringBuffer('(');
    for (final code in text.codeUnits) {
      if (code == 0x28 || code == 0x29 || code == 0x5C) {
        buffer.write('\\');
        buffer.writeCharCode(code);
      } else if (code < 32 || code > 126) {
        buffer.write('\\');
        buffer.write(code.toRadixString(8).padLeft(3, '0'));
      } else {
        buffer.writeCharCode(code);
      }
    }
    buffer.write(') Tj');
    return Uint8List.fromList(buffer.toString().codeUnits);
  }

  void _updateState(String op, List<dynamic> stack, PdfTextState state) {
    if (op == 'Tf' && stack.length >= 2) {
      if (stack.last is num) state.fontSize = (stack.last as num).toDouble();
      if (stack[stack.length - 2] is String) {
        state.fontRef = '/${stack[stack.length - 2]}';
      }
    } else if (op == 'Tz' && stack.isNotEmpty && stack.last is num) {
      state.horizontalScaling = (stack.last as num).toDouble();
    } else if (op == 'Tm' && stack.length >= 6) {
      state.setTextMatrix(
        (stack[0] as num).toDouble(), (stack[1] as num).toDouble(),
        (stack[2] as num).toDouble(), (stack[3] as num).toDouble(),
        (stack[4] as num).toDouble(), (stack[5] as num).toDouble(),
      );
    } else if (op == 'Td' && stack.length >= 2) {
      state.moveTextLine(
          (stack[0] as num).toDouble(), (stack[1] as num).toDouble());
    }
  }

  void _append(BytesBuilder builder, Uint8List source, int start, int end) {
    if (end > start && start >= 0 && end <= source.length) {
      builder.add(source.sublist(start, end));
    }
  }
}