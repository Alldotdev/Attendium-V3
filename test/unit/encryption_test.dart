import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendium/infrastructure/backup/encryption_service.dart';

void main() {
  group('EncryptionService Tests (Section 35 & 48)', () {
    const testPassphrase = 'CorrectHorseBatteryStaple#2026!';
    final originalText = 'Attendium Authoritative Database Backup Payload - Class CS-101';
    final originalBytes = Uint8List.fromList(utf8.encode(originalText));

    test('Encrypt and decrypt roundtrip matches original data', () {
      final encryptResult = EncryptionService.encrypt(
        plaintext: originalBytes,
        passphrase: testPassphrase,
      );

      expect(encryptResult.isSuccess, true);
      final encryptedBlob = encryptResult.successOrNull!;
      expect(encryptedBlob.length, greaterThan(originalBytes.length));

      // Decrypt with correct passphrase
      final decryptResult = EncryptionService.decrypt(
        encryptedBlob: encryptedBlob,
        passphrase: testPassphrase,
      );

      expect(decryptResult.isSuccess, true);
      final decryptedBytes = decryptResult.successOrNull!;
      expect(utf8.decode(decryptedBytes), originalText);
    });

    test('Decryption with wrong passphrase fails authentication', () {
      final encryptResult = EncryptionService.encrypt(
        plaintext: originalBytes,
        passphrase: testPassphrase,
      );
      final encryptedBlob = encryptResult.successOrNull!;

      final decryptResult = EncryptionService.decrypt(
        encryptedBlob: encryptedBlob,
        passphrase: 'WrongPassword123!',
      );

      expect(decryptResult.isFailure, true);
      expect(decryptResult.errorOrNull?.message.contains('Authentication failed'), true);
    });

    test('Decryption of tampered ciphertext is rejected by HMAC', () {
      final encryptResult = EncryptionService.encrypt(
        plaintext: originalBytes,
        passphrase: testPassphrase,
      );
      final encryptedBlob = encryptResult.successOrNull!;

      // Tamper a byte at the end of the ciphertext
      final tampered = Uint8List.fromList(encryptedBlob);
      tampered[tampered.length - 1] ^= 0xFF;

      final decryptResult = EncryptionService.decrypt(
        encryptedBlob: tampered,
        passphrase: testPassphrase,
      );

      expect(decryptResult.isFailure, true);
      expect(decryptResult.errorOrNull?.message.contains('Authentication failed'), true);
    });

    test('Decryption of non-Attendium file fails header check', () {
      final randomBytes = Uint8List.fromList(List.filled(100, 42));

      final decryptResult = EncryptionService.decrypt(
        encryptedBlob: randomBytes,
        passphrase: testPassphrase,
      );

      expect(decryptResult.isFailure, true);
      expect(decryptResult.errorOrNull?.message.contains('Invalid file signature'), true);
    });
  });
}
