import '../pdf_core/content_stream/content_stream_analyzer.dart';

/// A text edit that will be applied by rewriting the original content stream
/// in place, preserving the PDF's own font, size, colour, and encoding.
///
/// Unlike [TextEditAnnotation], this does not produce a white cover box and
/// does not substitute a base-14 font. The trade-off is that it only works
/// when the source font can encode the new characters — the saver checks
/// that and falls back to the overlay path if not.
class CleanTextEdit {
  final String id;
  final int pageIndex;

  /// The run as it was captured when the user tapped it. Carries the byte
  /// range, baseline, and original text used to re-locate the run at save
  /// time.
  final TextRun run;

  final String newText;

  const CleanTextEdit({
    required this.id,
    required this.pageIndex,
    required this.run,
    required this.newText,
  });
}