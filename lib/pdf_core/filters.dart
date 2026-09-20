import 'dart:io';
import 'dart:typed_data';

class PdfFilterDecoder {
  /// Routes stream decompression tasks based on the filter configuration name.
  static Uint8List decodeStream(Uint8List encryptedData, List<String> filters) {
    Uint8List runningBuffer = encryptedData;

    for (String filterName in filters) {
      switch (filterName) {
        case '/FlateDecode':
        case '/Fl':
          runningBuffer = _decodeFlate(runningBuffer);
          break;
        case '/ASCIIHexDecode':
        case '/AHx':
          runningBuffer = _decodeASCIIHex(runningBuffer);
          break;
        default:
          // Gracefully skip unsupported encryption systems (e.g. JBIG2, DCTDecode)
          // to let your parsing layer safely access metadata blocks
          break;
      }
    }
    return runningBuffer;
  }

  static Uint8List _decodeFlate(Uint8List compressedInput) {
    try {
      // PDF FlateDecode natively maps to RFC 1950 ZLib deflate specifications
      List<int> unpacked = zlib.decode(compressedInput);
      return Uint8List.fromList(unpacked);
    } catch (zlibError) {
      // Edge-case recovery: Some bad PDF exporters strip the 2-byte zlib header wrapper.
      // If direct decoding fails, you can fall back to raw inflate here.
      throw FormatException('Failed to inflate Flate compressed block data payload: $zlibError');
    }
  }

  static Uint8List _decodeASCIIHex(Uint8List asciiInput) {
    List<int> binaryOutput = [];
    StringBuffer pairBuffer = StringBuffer();

    for (int i = 0; i < asciiInput.length; i++) {
      int characterCode = asciiInput[i];
      if (characterCode == 62) break; // Exit early if we hit the closing angle bracket '>'

      // Filter out PDF white spaces completely during block translation
      if (characterCode == 32 || characterCode == 9 || characterCode == 13 || characterCode == 10 || characterCode == 0) {
        continue;
      }

      pairBuffer.writeCharCode(characterCode);
      if (pairBuffer.length == 2) {
        int? byteVal = int.tryParse(pairBuffer.toString(), radix: 16);
        if (byteVal != null) binaryOutput.add(byteVal);
        pairBuffer.clear();
      }
    }

    // Handline uneven hanging trail configurations
    if (pairBuffer.length == 1) {
      pairBuffer.write('0');
      int? byteVal = int.tryParse(pairBuffer.toString(), radix: 16);
      if (byteVal != null) binaryOutput.add(byteVal);
    }

    return Uint8List.fromList(binaryOutput);
  }
}

