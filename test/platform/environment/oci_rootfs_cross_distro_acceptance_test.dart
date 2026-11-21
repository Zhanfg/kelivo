import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/sandbox/oci_rootfs_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// #47: OCI metadata regressions and a gated multi-distribution device matrix.
/// Local metadata checks DO NOT prove Android PRoot execution compatibility.
final _deviceEnabled =
    Platform.environment['KELIVO_OCI_PROOT_DEVICE_TEST'] == '1';

String manifest(String mediaType) => jsonEncode({
  'schemaVersion': 2,
  'mediaType': 'application/vnd.oci.image.manifest.v1+json',
  'config': {
    'mediaType': 'application/vnd.oci.image.config.v1+json',
    'digest': 'sha256:${'a' * 64}',
    'size': 128,
  },
  'layers': [
    {'mediaType': mediaType, 'digest': 'sha256:${'b' * 64}', 'size': 4096},
  ],
});

void main() {
  test('OCI gzip and zstd layer metadata are accepted without extraction', () {
    for (final type in [
      'application/vnd.oci.image.layer.v1.tar+gzip',
      'application/vnd.oci.image.layer.v1.tar+zstd',
    ]) {
      final parsed = OciRootfsManifest.parse(manifest(type));
      expect(parsed.layers.single.mediaType, type);
      expect(parsed.layers.single.size, 4096);
    }
  });

  test('unsafe TAR references cannot be accepted as PRoot rootfs entries', () {
    for (final entry in ['../../host', '/system/bin/sh', 'a/../b']) {
      expect(
        () => OciTarEntryPolicy.check(name: entry, type: 'file', size: 1),
        throwsFormatException,
      );
    }
    expect(
      () => OciTarEntryPolicy.check(name: 'dev/null', type: 'device', size: 0),
      throwsFormatException,
    );
  });

  test(
    'Android PRoot boot, package-manager and architecture evidence for two distros',
    () async {
      final evidenceFile =
          Platform.environment['KELIVO_OCI_PROOT_EVIDENCE_JSON'];
      if (evidenceFile == null || evidenceFile.isEmpty) {
        throw StateError('Explicit sanitized device evidence file required');
      }
      final file = File(evidenceFile);
      if (!await file.exists() || await file.length() > 65536) {
        throw StateError('Missing or oversized PRoot device evidence');
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic> ||
          data['androidDevice'] != true ||
          data['prootUsed'] != true ||
          data['architecturesVerified'] != true) {
        throw const FormatException('Incomplete Android PRoot evidence');
      }
      final distros = data['distributions'];
      if (distros is! List || distros.length < 2) {
        throw const FormatException('Two actual distributions required');
      }
      final names = <String>{};
      for (final item in distros) {
        if (item is! Map<String, dynamic> ||
            item['bootVerified'] != true ||
            item['packageManagerVerified'] != true ||
            item['architectureVerified'] != true ||
            item['distribution'] is! String) {
          throw const FormatException('Incomplete distribution device result');
        }
        names.add(item['distribution'] as String);
      }
      expect(names.length, greaterThanOrEqualTo(2));
      // Supplied evidence still requires independent device/log review.
    },
    skip: !_deviceEnabled
        ? 'NOT TESTED: two physical PRoot distributions absent'
        : false,
  );
}
