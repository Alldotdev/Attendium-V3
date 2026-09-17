import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Computes SHA-256 hashes for documents to protect against duplicate imports (Section 46).
class DocumentHasher {
  const DocumentHasher._();

  static String hashBytes(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static String hashString(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
