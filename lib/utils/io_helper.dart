import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'io_helper_stub.dart'
    if (dart.library.io) 'io_helper_mobile.dart';

class IoHelper {
  static Future<void> write(String path, Uint8List bytes) async {
    if (kIsWeb) return;
    await ioWrite(path, bytes);
  }
}
