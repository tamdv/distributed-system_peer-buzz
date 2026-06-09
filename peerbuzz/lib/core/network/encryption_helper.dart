import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionHelper {
  static Future<String> encrypt(String text) async {
    if (text.isEmpty) return text;
    return await compute(_encryptInIsolate, text);
  }

  static Future<String> decrypt(String base64Text) async {
    if (base64Text.isEmpty) return base64Text;
    return await compute(_decryptInIsolate, base64Text);
  }
}

// Cần định nghĩa các hàm top-level để dùng cho compute
String _encryptInIsolate(String text) {
  final key = encrypt.Key.fromUtf8('my32charultrasecretkeyforpeerbuz');
  final iv = encrypt.IV.fromUtf8('1234567890123456');
  final encrypter = encrypt.Encrypter(encrypt.AES(key));
  final encrypted = encrypter.encrypt(text, iv: iv);
  return encrypted.base64;
}

String _decryptInIsolate(String base64Text) {
  try {
    final key = encrypt.Key.fromUtf8('my32charultrasecretkeyforpeerbuz');
    final iv = encrypt.IV.fromUtf8('1234567890123456');
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final decrypted = encrypter.decrypt64(base64Text, iv: iv);
    return decrypted;
  } catch (e) {
    return "[Lỗi giải mã: $e]";
  }
}
