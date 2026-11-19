import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/sandbox/rootfs_integrity.dart';
import 'package:Kelivo/core/services/sandbox/rootfs_registry_source.dart';

void main() {
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('rootfs-test-'),
  );
  tearDown(() async => dir.delete(recursive: true));

  RootfsArchiveDescriptor descriptor(String digest) => RootfsArchiveDescriptor(
    arch: 'arm64',
    url: 'https://example.org/rootfs.tar.gz',
    sha256: digest,
    format: RootfsArchiveFormat.tarGz,
  );

  test('only independently pinned matching content verifies', () async {
    final file = File('${dir.path}/archive')..writeAsBytesSync([1, 2, 3]);
    final digest = sha256.convert([1, 2, 3]).toString();
    expect(
      await RootfsIntegrity(
        trustedSha256: {digest},
      ).verify(file, descriptor(digest)),
      isTrue,
    );
    expect(
      await RootfsIntegrity(trustedSha256: {}).verify(file, descriptor(digest)),
      isFalse,
    );
    await file.writeAsBytes([4]);
    expect(
      await RootfsIntegrity(
        trustedSha256: {digest},
      ).verify(file, descriptor(digest)),
      isFalse,
    );
  });

  test('publish refuses existing target without corrupting original', () async {
    final source = File('${dir.path}/source')..writeAsBytesSync([1, 2, 3]);
    final target = File('${dir.path}/target')..writeAsBytesSync([8]);
    final digest = sha256.convert([1, 2, 3]).toString();
    final integrity = RootfsIntegrity(trustedSha256: {digest});
    await expectLater(
      integrity.publish(
        candidate: source,
        descriptor: descriptor(digest),
        target: target,
      ),
      throwsStateError,
    );
    expect(await target.readAsBytes(), [8]);
  });

  test('verified new target published, tamper rejected', () async {
    final source = File('${dir.path}/source')..writeAsBytesSync([1, 2, 3]);
    final target = File('${dir.path}/target');
    final digest = sha256.convert([1, 2, 3]).toString();
    final integrity = RootfsIntegrity(trustedSha256: {digest});
    await integrity.publish(
      candidate: source,
      descriptor: descriptor(digest),
      target: target,
    );
    expect(await target.readAsBytes(), [1, 2, 3]);
    await source.writeAsBytes([0]);
    await expectLater(
      integrity.publish(
        candidate: source,
        descriptor: descriptor(digest),
        target: File('${dir.path}/other'),
      ),
      throwsFormatException,
    );
  });
}
