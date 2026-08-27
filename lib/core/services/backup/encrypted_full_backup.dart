import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_cancel_token.dart';
import 'backup_task_progress.dart';

/// Streaming, password-encrypted envelope used for complete local backups.
///
/// Format v1:
///   magic(8) | version(1) | saltLen(1) | noncePrefixLen(1) |
///   chunkSize(4, BE) | salt | noncePrefix |
///   repeated { plainLen(4, BE) | ciphertext(plainLen) | mac(16) } |
///   terminator plainLen=0
///
/// Each chunk is independently authenticated with AES-256-GCM and a unique
/// 96-bit nonce: 64-bit random prefix + 32-bit chunk index. The encryption key
/// is derived once from the user password with Argon2id.
final class EncryptedFullBackupCodec {
  EncryptedFullBackupCodec._();

  static final Uint8List _magic = Uint8List.fromList(ascii.encode('KELIVOEB'));
  static const int formatVersion = 1;
  static const int _saltLength = 16;
  static const int _noncePrefixLength = 8;
  static const int _macLength = 16;
  static const int _chunkSize = 4 * 1024 * 1024;
  static const int _argonMemoryKiB = 19 * 1024;
  static const int _argonParallelism = 1;
  static const int _argonIterations = 2;

  static Future<File> encryptFile({
    required File source,
    required String password,
    BackupProgressSink? onProgress,
    BackupCancelToken? cancelToken,
    Directory? temporaryDirectory,
  }) async {
    _validatePassword(password);
    if (!await source.exists()) {
      throw FileSystemException('Backup source does not exist', source.path);
    }

    final temp = temporaryDirectory ?? await getTemporaryDirectory();
    final work = Directory(
      p.join(
        temp.path,
        'kelivo_encrypted_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await work.create(recursive: true);
    final output = File(
      p.join(
        work.path,
        'kelivo_full_${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.kelivo',
      ),
    );

    final salt = _randomBytes(_saltLength);
    final noncePrefix = _randomBytes(_noncePrefixLength);
    final secretKey = await _deriveKey(password, salt);
    final cipher = AesGcm.with256bits();
    final input = await source.open(mode: FileMode.read);
    final sink = await output.open(mode: FileMode.write);
    final sourceBytes = await source.length();
    var processed = 0;
    var chunkIndex = 0;

    try {
      await sink.writeFrom(_header(salt: salt, noncePrefix: noncePrefix));
      while (true) {
        _throwIfCancelled(cancelToken);
        final clear = await input.read(_chunkSize);
        if (clear.isEmpty) break;
        if (chunkIndex > 0xffffffff) {
          throw const FormatException('encrypted_backup_too_many_chunks');
        }
        final nonce = _nonce(noncePrefix, chunkIndex);
        final box = await cipher.encrypt(
          clear,
          secretKey: secretKey,
          nonce: nonce,
        );
        if (box.cipherText.length != clear.length ||
            box.mac.bytes.length != _macLength) {
          throw const FormatException('encrypted_backup_cipher_shape');
        }
        await sink.writeFrom(_u32(clear.length));
        await sink.writeFrom(box.cipherText);
        await sink.writeFrom(box.mac.bytes);
        processed += clear.length;
        chunkIndex++;
        onProgress?.call(
          BackupProgress(
            phase: BackupPhase.packing,
            processed: processed,
            total: sourceBytes,
            unit: BackupProgressUnit.bytes,
            cancellable: true,
            detail: 'Encrypting complete backup',
          ),
        );
      }
      await sink.writeFrom(_u32(0));
      await sink.flush();
      return output;
    } catch (_) {
      try {
        if (await output.exists()) await output.delete();
        if (await work.exists()) await work.delete(recursive: true);
      } catch (_) {}
      rethrow;
    } finally {
      await input.close();
      await sink.close();
    }
  }

  static Future<File> decryptToTemporaryFile({
    required File source,
    required String password,
    BackupProgressSink? onProgress,
    BackupCancelToken? cancelToken,
    Directory? temporaryDirectory,
  }) async {
    _validatePassword(password);
    if (!await source.exists()) {
      throw FileSystemException('Encrypted backup does not exist', source.path);
    }

    final input = await source.open(mode: FileMode.read);
    final total = await source.length();
    final fixed = await _readExact(input, 15);
    if (!_sameBytes(fixed.sublist(0, 8), _magic)) {
      await input.close();
      throw const FormatException('encrypted_backup_magic');
    }
    if (fixed[8] != formatVersion) {
      await input.close();
      throw const FormatException('encrypted_backup_version');
    }
    final saltLength = fixed[9];
    final noncePrefixLength = fixed[10];
    final chunkSize = _readU32(fixed, 11);
    if (saltLength != _saltLength ||
        noncePrefixLength != _noncePrefixLength ||
        chunkSize <= 0 ||
        chunkSize > 64 * 1024 * 1024) {
      await input.close();
      throw const FormatException('encrypted_backup_header');
    }
    final salt = await _readExact(input, saltLength);
    final noncePrefix = await _readExact(input, noncePrefixLength);
    final secretKey = await _deriveKey(password, salt);
    final cipher = AesGcm.with256bits();

    final temp = temporaryDirectory ?? await getTemporaryDirectory();
    final work = Directory(
      p.join(
        temp.path,
        'kelivo_decrypted_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await work.create(recursive: true);
    final output = File(p.join(work.path, 'kelivo_complete_backup.zip'));
    final sink = await output.open(mode: FileMode.write);
    var chunkIndex = 0;
    var processedCipherBytes = 15 + saltLength + noncePrefixLength;

    try {
      while (true) {
        _throwIfCancelled(cancelToken);
        final lengthBytes = await _readExact(input, 4);
        processedCipherBytes += 4;
        final clearLength = _readU32(lengthBytes, 0);
        if (clearLength == 0) {
          if (processedCipherBytes != total) {
            throw const FormatException('encrypted_backup_trailing_data');
          }
          break;
        }
        if (clearLength > chunkSize || chunkIndex > 0xffffffff) {
          throw const FormatException('encrypted_backup_chunk_length');
        }
        final cipherText = await _readExact(input, clearLength);
        final macBytes = await _readExact(input, _macLength);
        processedCipherBytes += clearLength + _macLength;
        final nonce = _nonce(noncePrefix, chunkIndex);
        late final List<int> clear;
        try {
          clear = await cipher.decrypt(
            SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
            secretKey: secretKey,
          );
        } catch (_) {
          throw const FormatException(
            'encrypted_backup_authentication_or_password',
          );
        }
        if (clear.length != clearLength) {
          throw const FormatException('encrypted_backup_plain_length');
        }
        await sink.writeFrom(clear);
        chunkIndex++;
        onProgress?.call(
          BackupProgress(
            phase: BackupPhase.verifying,
            processed: processedCipherBytes,
            total: total,
            unit: BackupProgressUnit.bytes,
            cancellable: true,
            detail: 'Decrypting and authenticating complete backup',
          ),
        );
      }
      await sink.flush();
      return output;
    } catch (_) {
      try {
        if (await output.exists()) await output.delete();
        if (await work.exists()) await work.delete(recursive: true);
      } catch (_) {}
      rethrow;
    } finally {
      await input.close();
      await sink.close();
    }
  }

  static Future<void> cleanupTemporaryFile(File? file) async {
    if (file == null) return;
    final parent = file.parent;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    try {
      if (await parent.exists() &&
          (p.basename(parent.path).startsWith('kelivo_encrypted_') ||
              p.basename(parent.path).startsWith('kelivo_decrypted_'))) {
        await parent.delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt) {
    final kdf = Argon2id(
      memory: _argonMemoryKiB,
      parallelism: _argonParallelism,
      iterations: _argonIterations,
      hashLength: 32,
    );
    return kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static Uint8List _header({
    required List<int> salt,
    required List<int> noncePrefix,
  }) {
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(formatVersion)
      ..addByte(salt.length)
      ..addByte(noncePrefix.length)
      ..add(_u32(_chunkSize))
      ..add(salt)
      ..add(noncePrefix);
    return out.takeBytes();
  }

  static Uint8List _nonce(List<int> prefix, int index) {
    final out = Uint8List(12)..setRange(0, 8, prefix);
    ByteData.sublistView(out).setUint32(8, index, Endian.big);
    return out;
  }

  static Uint8List _u32(int value) {
    final out = Uint8List(4);
    ByteData.sublistView(out).setUint32(0, value, Endian.big);
    return out;
  }

  static int _readU32(List<int> source, int offset) {
    final bytes = source is Uint8List ? source : Uint8List.fromList(source);
    return ByteData.sublistView(bytes).getUint32(offset, Endian.big);
  }

  static Future<Uint8List> _readExact(RandomAccessFile file, int length) async {
    final out = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final part = await file.read(length - offset);
      if (part.isEmpty) {
        throw const FormatException('encrypted_backup_truncated');
      }
      out.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return out;
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static void _validatePassword(String password) {
    if (password.length < 8) {
      throw const FormatException('encrypted_backup_password_too_short');
    }
  }

  static void _throwIfCancelled(BackupCancelToken? token) {
    if (token?.isCancelled == true) {
      throw const BackupCancelledException();
    }
  }
}
