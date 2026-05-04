// Mobile/desktop — dart:io available
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> ioReadBytes(String path) async {
  try { return await File(path).readAsBytes(); } catch (_) { return null; }
}

Future<void> ioWriteBytes(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes);
}

bool ioExists(String path) {
  try { return File(path).existsSync(); } catch (_) { return false; }
}

Future<void> ioDelete(String path) async {
  try { await File(path).delete(); } catch (_) {}
}
