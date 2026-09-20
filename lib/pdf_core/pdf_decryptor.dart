import 'dart:typed_data';
import 'lexer.dart';
import 'object_parser.dart';
import 'pdf_crypto.dart';

/// Implements the PDF standard security handler for the common cases:
///   R=2 (RC4-40), R=3 (RC4-40..128), R=4 (AES-128 / RC4).
/// AES-256 (R=5/6) is rejected — see [fromEncryptDict].
class PdfDecryptor {
  final Uint8List _key;
  final int _revision;
  final bool _useAes;

  PdfDecryptor._(this._key, this._revision, this._useAes);

  bool get isAes => _useAes;
  int get revision => _revision;

  static PdfDecryptor? fromEncryptDict(
    Map<String, dynamic> enc,
    Uint8List? fileIdFirst,
    dynamic Function(PdfIndirectReference) resolve,
    String password,
  ) {
    dynamic g(String k) {
      var v = enc[k];
      if (v is PdfIndirectReference) v = resolve(v);
      return v;
    }

    final r = (g('/R') as num?)?.toInt() ?? 0;
    final v = (g('/V') as num?)?.toInt() ?? 0;

    if (r >= 5) {
      throw UnsupportedError(
          'PDF AES-256 encryption (R=$r) is not yet supported.');
    }
    if (r < 2) return null;

    final oBytes = _stringBytes(g('/O'));
    if (oBytes.length < 32) return null;
    final p = (g('/P') as num?)?.toInt() ?? 0;

    int keyLen;
    if (r == 2) {
      keyLen = 5;
    } else {
      keyLen = ((g('/Length') as num?)?.toInt() ?? 40) ~/ 8;
      if (keyLen < 5 || keyLen > 16) keyLen = 16;
    }

    bool useAes = false;
    if (v == 4) {
      final cf = g('/CF');
      final stmf = g('/StmF')?.toString() ?? '';
      if (cf is Map && cf[stmf] is Map) {
        if ((cf[stmf] as Map)['/CFM']?.toString() == '/AESV2') {
          useAes = true;
        }
      }
    }

    // Algorithm 2 — encryption key derivation.
    final buf = BytesBuilder();
    buf.add(_padPassword(password));
    buf.add(oBytes.sublist(0, 32));
    final pBytes = Uint8List(4);
    ByteData.view(pBytes.buffer).setInt32(0, p, Endian.little);
    buf.add(pBytes);
    if (fileIdFirst != null) buf.add(fileIdFirst);

    var key = md5(buf.takeBytes());
    if (r >= 3) {
      for (int i = 0; i < 50; i++) {
        key = md5(key.sublist(0, keyLen));
      }
    }
    key = key.sublist(0, keyLen);

    return PdfDecryptor._(key, r, useAes);
  }

  /// Decrypts the raw bytes of an object (stream or string payload).
  Uint8List decrypt(int objId, int gen, Uint8List data) {
    if (data.isEmpty) return data;
    final objKey = _objectKey(objId, gen);
    if (_useAes) {
      return aesCbcDecryptPrefixedIv(objKey.sublist(0, 16), data);
    }
    return rc4(objKey, data);
  }

  Uint8List _objectKey(int objId, int gen) {
    final buf = BytesBuilder();
    buf.add(_key);
    buf.addByte(objId & 0xFF);
    buf.addByte((objId >> 8) & 0xFF);
    buf.addByte((objId >> 16) & 0xFF);
    buf.addByte(gen & 0xFF);
    buf.addByte((gen >> 8) & 0xFF);
    final h = md5(buf.takeBytes());
    final take = (_key.length + 5).clamp(0, 16);
    return h.sublist(0, take);
  }

  static Uint8List _padPassword(String pw) {
    const fallback = <int>[
      0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
      0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
      0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
      0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
    ];
    final pwBytes = Uint8List.fromList(pw.codeUnits);
    final n = pwBytes.length > 32 ? 32 : pwBytes.length;
    final out = Uint8List(32);
    out.setRange(0, n, pwBytes);
    out.setRange(n, 32, fallback.sublist(0, 32 - n));
    return out;
  }
}

/// Extract raw bytes from a parsed PDF string (PdfRawString or `<hex>`).
Uint8List _stringBytes(dynamic v) {
  if (v is PdfRawString) return Uint8List.fromList(v.bytes);
  if (v is String) {
    if (v.startsWith('<') && v.endsWith('>')) {
      final hex = v.substring(1, v.length - 1);
      final padded = hex.length.isOdd ? '${hex}0' : hex;
      final out = <int>[];
      for (int i = 0; i < padded.length; i += 2) {
        final b = int.tryParse(padded.substring(i, i + 2), radix: 16);
        if (b != null) out.add(b);
      }
      return Uint8List.fromList(out);
    }
    return Uint8List.fromList(v.codeUnits);
  }
  return Uint8List(0);
}

/// Public helper used by the document engine for /ID extraction.
Uint8List? pdfStringToBytes(dynamic v) {
  final b = _stringBytes(v);
  return b.isEmpty ? null : b;
}