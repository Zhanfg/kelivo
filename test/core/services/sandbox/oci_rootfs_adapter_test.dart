import 'dart:convert';

import 'package:Kelivo/core/services/sandbox/oci_rootfs_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

final _digest = 'sha256:${'a' * 64}';

Map<String, Object?> _descriptor(String mediaType, {int size = 25}) => {
  'mediaType': mediaType,
  'digest': _digest,
  'size': size,
};

Map<String, Object?> _manifest() => {
  'schemaVersion': 2,
  'mediaType': 'application/vnd.oci.image.manifest.v1+json',
  'config': _descriptor('application/vnd.oci.image.config.v1+json'),
  'layers': [
    _descriptor('application/vnd.oci.image.layer.v1.tar+gzip'),
    _descriptor('application/vnd.oci.image.layer.v1.tar'),
  ],
};

void main() {
  test('accepts bounded OCI v1 manifest without extraction', () {
    final manifest = OciRootfsManifest.parse(jsonEncode(_manifest()));
    expect(manifest.layers, hasLength(2));
    expect(manifest.config.digest, _digest);
    expect(manifest.layers.first.size, 25);
    expect(() => manifest.layers.clear(), throwsUnsupportedError);
  });

  test('rejects unsupported schema and media type', () {
    expect(
      () => OciRootfsManifest.parse(
        jsonEncode({..._manifest(), 'schemaVersion': 1}),
      ),
      throwsFormatException,
    );
    expect(
      () => OciRootfsManifest.parse(
        jsonEncode({..._manifest(), 'mediaType': 'application/unsafe'}),
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed and unbounded metadata', () {
    expect(() => OciRootfsManifest.parse('{'), throwsFormatException);
    expect(
      () => OciRootfsManifest.parse(
        jsonEncode({
          ..._manifest(),
          'layers': List.filled(
            129,
            _descriptor('application/vnd.oci.image.layer.v1.tar'),
          ),
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => OciRootfsManifest.parse(' ' * (512 * 1024 + 1)),
      throwsFormatException,
    );
  });

  test('rejects missing digest, invalid digest and extra keys', () {
    final invalid = _descriptor('application/vnd.oci.image.layer.v1.tar')
      ..['digest'] = 'sha256:bad';
    expect(
      () => OciRootfsManifest.parse(
        jsonEncode({
          ..._manifest(),
          'layers': [invalid],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => OciRootfsManifest.parse(
        jsonEncode({..._manifest(), 'shellCommand': 'ignored'}),
      ),
      throwsFormatException,
    );
  });

  test('rejects unknown layer formats and excessive sizes', () {
    expect(
      () => OciRootfsManifest.parse(
        jsonEncode({
          ..._manifest(),
          'layers': [_descriptor('application/vnd.oci.image.layer.v1.tar+xz')],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => OciRootfsManifest.parse(
        jsonEncode({
          ..._manifest(),
          'layers': [
            _descriptor('application/vnd.oci.image.layer.v1.tar', size: -1),
          ],
        }),
      ),
      throwsFormatException,
    );
  });

  test('rejects TAR path traversal, absolute paths and Windows drives', () {
    for (final name in [
      '../etc/passwd',
      '/etc/passwd',
      r'C:\Windows\system.ini',
      'a/../b',
      'a/./b',
      r'a\b',
    ]) {
      expect(
        () => OciTarEntryPolicy.check(name: name, type: 'file', size: 1),
        throwsFormatException,
      );
    }
  });

  test('rejects symlinks, hardlinks and device entries', () {
    for (final type in ['symlink', 'hardlink', 'device', 'fifo']) {
      expect(
        () => OciTarEntryPolicy.check(name: 'safe', type: type, size: 0),
        throwsFormatException,
      );
    }
  });

  test('accepts safe entry metadata, but performs no extraction', () {
    OciTarEntryPolicy.check(name: 'usr/bin/tool', type: 'file', size: 2048);
    OciTarEntryPolicy.check(name: 'usr/bin/', type: 'directory', size: 0);
    expect(
      () => OciTarEntryPolicy.check(
        name: 'large.bin',
        type: 'file',
        size: 1024 * 1024 * 1024 + 1,
      ),
      throwsFormatException,
    );
  });
}
