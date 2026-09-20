import 'dart:typed_data';
import 'package:pointycastle/export.dart';

Uint8List md5(Uint8List data) => MD5Digest().process(data);
Uint8List sha256(Uint8List data) => SHA256Digest().process(data);

/// RC4 — symmetric, so encrypt and decrypt are the same call.
Uint8List rc4(Uint8List key, Uint8List data) {
  final s = List<int>.generate(256, (i) => i);
  int j = 0;
  for (int i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xFF;
    final t = s[i]; s[i] = s[j]; s[j] = t;
  }
  final out = Uint8List(data.length);
  int a = 0, b = 0;
  for (int k = 0; k < data.length; k++) {
    a = (a + 1) & 0xFF;
    b = (b + s[a]) & 0xFF;
    final t = s[a]; s[a] = s[b]; s[b] = t;
    out[k] = data[k] ^ s[(s[a] + s[b]) & 0xFF];
  }
  return out;
}

/// AES-CBC with the 16-byte IV prepended (PDF /AESV2 format) + PKCS#7 unpad.
Uint8List aesCbcDecryptPrefixedIv(Uint8List key, Uint8List data) {
  if (data.length < 32) throw FormatException('AES ciphertext too short');
  final iv = data.sublist(0, 16);
  final ct = data.sublist(16);
  if (ct.length % 16 != 0) {
    throw FormatException('AES ciphertext not block-aligned');
  }
  // ✅ FIXED: was `_aesCbcNoPad`, should be `aesCbcNoPad`
  return _pkcs7Unpad(aesCbcNoPad(key, iv, ct, encrypt: false));
}

Uint8List aesCbcNoPad(Uint8List key, Uint8List iv, Uint8List input,
    {required bool encrypt}) {
  final cipher = CBCBlockCipher(AESEngine())
    ..init(encrypt, ParametersWithIV(KeyParameter(key), iv));
  final out = Uint8List(input.length);
  for (int i = 0; i < input.length; i += 16) {
    cipher.processBlock(input, i, out, i);
  }
  return out;
}

Uint8List aesEcbNoPad(Uint8List key, Uint8List input, {required bool encrypt}) {
  final cipher = AESEngine()..init(encrypt, KeyParameter(key));
  final out = Uint8List(input.length);
  for (int i = 0; i < input.length; i += 16) {
    cipher.processBlock(input, i, out, i);
  }
  return out;
}

Uint8List _pkcs7Unpad(Uint8List data) {
  if (data.isEmpty) return data;
  final pad = data.last;
  if (pad < 1 || pad > 16 || pad > data.length) return data;
  return data.sublist(0, data.length - pad);
}