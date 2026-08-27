import 'dart:io';

import 'package:Kelivo/core/services/backup/encrypted_full_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypted complete backup round-trips and authenticates', () async {
    final temp = await Directory.systemTemp.createTemp('kelivo_enc_test_');
    try {
      final source = File('${temp.path}/source.zip');
      final bytes = List<int>.generate(5 * 1024 * 1024 + 137, (index) => (index * 31 + 7) & 0xff);
      await source.writeAsBytes(bytes, flush: true);
      final encrypted = await EncryptedFullBackupCodec.encryptFile(
        source: source,
        password: 'correct horse battery staple',
        temporaryDirectory: temp,
      );
      expect(encrypted.path.endsWith('.kelivo'), isTrue);
      final restored = await EncryptedFullBackupCodec.decryptToTemporaryFile(
        source: encrypted,
        password: 'correct horse battery staple',
        temporaryDirectory: temp,
      );
      expect(await restored.readAsBytes(), bytes);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });

  test('encrypted complete backup rejects wrong password', () async {
    final temp = await Directory.systemTemp.createTemp('kelivo_enc_bad_');
    try {
      final source = File('${temp.path}/source.zip')
        ..writeAsBytesSync(List<int>.generate(4096, (i) => i & 0xff));
      final encrypted = await EncryptedFullBackupCodec.encryptFile(
        source: source,
        password: 'correct password',
        temporaryDirectory: temp,
      );
      await expectLater(
        EncryptedFullBackupCodec.decryptToTemporaryFile(
          source: encrypted,
          password: 'wrong password',
          temporaryDirectory: temp,
        ),
        throwsA(isA<FormatException>()),
      );
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}
