// Web stub — no dart:io on web
import 'dart:typed_data';

Future<Uint8List?> ioReadBytes(String path) async => null;
Future<void> ioWriteBytes(String path, Uint8List bytes) async {}
bool ioExists(String path) => false;
Future<void> ioDelete(String path) async {}
