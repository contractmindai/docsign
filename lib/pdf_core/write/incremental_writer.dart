import 'dart:convert';
import 'dart:typed_data';

import 'object_parser.dart';

class IncrementalUpdatePayload {
  final int objectId;
  final int generation;
  final Uint8List bytes;

  /// Accepts [Uint8List], [List<int>], or [String] as the body.
  ///
  /// - Binary stream payloads (image XObjects, form XObjects, content
  ///   streams) are passed as Uint8List or List<int>.
  /// - Dictionary bodies (field dicts, page dicts, AcroForm dicts) come
  ///   from the forms layer as Strings produced by serializing helpers.
  ///
  /// Strings are latin1-encoded (1 byte per code unit, 0..255) so binary
  /// payloads that were previously stringified with
  /// `String.fromCharCodes(bytes)` round-trip losslessly.
  IncrementalUpdatePayload(this.objectId, this.generation, dynamic body)
      : bytes = _coerce(body);

  factory IncrementalUpdatePayload.fromString(
      int objectId, int generation, String body) {
    return IncrementalUpdatePayload(objectId, generation, body);
  }

  static Uint8List _coerce(dynamic body) {
    if (body is Uint8List) return body;
    if (body is List<int>) return Uint8List.fromList(body);
    if (body is String) return Uint8List.fromList(latin1.encode(body));
    throw ArgumentError(
        'IncrementalUpdatePayload body must be Uint8List, List<int>, or String; '
        'got ${body.runtimeType}');
  }
}

class PdfIncrementalWriter {
  static Uint8List appendUpdates(
    Uint8List originalBytes,
    List<IncrementalUpdatePayload> updates,
    int originalXrefOffset,
    int highestObjectIdUsed, {
    required PdfIndirectReference rootRef,
  }) {
    if (updates.isEmpty) return originalBytes;

    final output = BytesBuilder(copy: false);
    output.add(originalBytes);
    if (originalBytes.isNotEmpty &&
        originalBytes.last != 10 &&
        originalBytes.last != 13) {
      output.add(utf8.encode('\r\n'));
    }

    int filePointer = output.length;
    final newOffsets = <int, int>{};

    for (final update in updates) {
      newOffsets[update.objectId] = filePointer;
      final header =
          utf8.encode('${update.objectId} ${update.generation} obj\r\n');
      output.add(header);
      filePointer += header.length;
      output.add(update.bytes);
      filePointer += update.bytes.length;
      final footerBytes = utf8.encode('\r\nendobj\r\n');
      output.add(footerBytes);
      filePointer += footerBytes.length;
    }

    final newXrefStartOffset = filePointer;
    final sortedIds = newOffsets.keys.toList()..sort();
    final runs = _groupIntoRuns(sortedIds);

    final xrefBuf = StringBuffer('xref\r\n');
    for (final run in runs) {
      xrefBuf.write('${run.first} ${run.length}\r\n');
      for (final id in run) {
        final offset = newOffsets[id]!.toString().padLeft(10, '0');
        xrefBuf.write('$offset 00000 n \r\n');
      }
    }
    final xrefBytes = utf8.encode(xrefBuf.toString());
    output.add(xrefBytes);
    filePointer += xrefBytes.length;

    final trailerSize = highestObjectIdUsed + 1;
    output.add(utf8.encode(
        'trailer\r\n<<\r\n/Size $trailerSize\r\n/Root ${rootRef.objectId} '
        '${rootRef.generation} R\r\n/Prev $originalXrefOffset\r\n>>\r\n'));
    output.add(utf8.encode('startxref\r\n$newXrefStartOffset\r\n%%EOF\r\n'));
    return output.takeBytes();
  }

  static List<List<int>> _groupIntoRuns(List<int> sortedIds) {
    if (sortedIds.isEmpty) return [];
    final runs = <List<int>>[];
    var current = [sortedIds[0]];
    for (int i = 1; i < sortedIds.length; i++) {
      if (sortedIds[i] == sortedIds[i - 1] + 1) {
        current.add(sortedIds[i]);
      } else {
        runs.add(current);
        current = [sortedIds[i]];
      }
    }
    runs.add(current);
    return runs;
  }
}