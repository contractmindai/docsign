import 'dart:typed_data';

// ✅ Conditional import — dart:html only compiled on web
import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_impl.dart';

/// Download a file in the browser (web) or no-op on mobile.
/// On web: creates a Blob URL, clicks a hidden anchor → browser saves the file.
void downloadFile(String filename, Uint8List bytes) {
  triggerWebDownload(filename, bytes);
}
