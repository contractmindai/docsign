// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser file download using a Blob URL.
/// This file is only compiled on web (via conditional import).
void triggerWebDownload(String filename, Uint8List bytes) {
  try {
    final blob   = html.Blob([bytes], 'application/pdf');
    final url    = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  } catch (e) {
    // Fallback: open in new tab
    html.window.open('data:application/pdf;base64,', '_blank');
  }
}
