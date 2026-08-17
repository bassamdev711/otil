import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class BackupCodec {
  BackupCodec._();

  static const _magic = 'MIFT1';
  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2.hmacSha256(iterations: 100000, bits: 256);

  static Future<Uint8List> encrypt(Map<String, dynamic> payload, String password) async {
    _validatePassword(password);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    final secretBox = await _cipher.encrypt(utf8.encode(jsonEncode(payload)), secretKey: key);
    return Uint8List.fromList([...utf8.encode(_magic), ...salt, ...secretBox.concatenation()]);
  }

  static Future<Map<String, dynamic>> decrypt(Uint8List bytes, String password) async {
    _validatePassword(password);
    final headerLength = _magic.length;
    if (bytes.length <= headerLength + 16 || utf8.decode(bytes.sublist(0, headerLength), allowMalformed: true) != _magic) {
      throw const FormatException('ملف النسخة غير مشفر أو غير مدعوم');
    }
    final salt = bytes.sublist(headerLength, headerLength + 16);
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    final secretBox = SecretBox.fromConcatenation(bytes.sublist(headerLength + 16), nonceLength: _cipher.nonceLength, macLength: _cipher.macAlgorithm.macLength);
    final clearText = await _cipher.decrypt(secretBox, secretKey: key);
    final decoded = jsonDecode(utf8.decode(clearText));
    if (decoded is! Map) throw const FormatException('محتوى النسخة غير صالح');
    return Map<String, dynamic>.from(decoded);
  }

  static void _validatePassword(String password) {
    if (password.length < 8) throw const FormatException('كلمة مرور النسخة يجب أن تحتوي على 8 أحرف على الأقل');
  }
}
