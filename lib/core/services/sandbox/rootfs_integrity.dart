// Fail-closed rootfs archive verification and guarded publication.
// A digest authenticates bytes only if its expected value was independently pinned.
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'rootfs_registry_source.dart';

final class RootfsIntegrity {
  RootfsIntegrity({required Set<String> trustedSha256})
    : trustedSha256 = Set.unmodifiable(trustedSha256) {
    if (trustedSha256.any((x) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(x))) {
      throw ArgumentError('Invalid trusted digest');
    }
  }

  final Set<String> trustedSha256;

  /// Check pinned digest AND descriptor digest; never trust a registry alone.
  Future<bool> verify(File archive, RootfsArchiveDescriptor descriptor) async {
    if (!trustedSha256.contains(descriptor.sha256)) return false;
    if (await FileSystemEntity.type(archive.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final actual = (await sha256.bind(archive.openRead()).first).toString();
    return actual == descriptor.sha256;
  }

  /// Replace a rootfs archive only after digest verification. A failed copy,
  /// hash, or rename leaves [target] unchanged and cleans only owned staging.
  /// Directory must reside on the same filesystem for atomic rename.
  Future<void> publish({
    required File candidate,
    required RootfsArchiveDescriptor descriptor,
    required File target,
  }) async {
    if (!await verify(candidate, descriptor)) {
      throw const FormatException('Rootfs archive is not pinned or is corrupt');
    }
    final parent = target.parent;
    if (!await parent.exists()) throw StateError('Missing target directory');
    final staging = await parent.createTemp('.rootfs-stage-');
    final staged = File('${staging.path}/archive');
    try {
      await candidate.openRead().pipe(staged.openWrite());
      if (!await verify(staged, descriptor)) {
        throw const FormatException('Rootfs staging verification failed');
      }
      // Fail closed instead of overwriting a previously installed archive.
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Target already exists; explicit rollback required');
      }
      await staged.rename(target.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
