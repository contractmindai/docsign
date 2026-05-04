import 'dart:io';
import 'dart:typed_data';
Future<void> ioWrite(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes);
}
