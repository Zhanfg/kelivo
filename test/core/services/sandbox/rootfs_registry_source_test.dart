import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/sandbox/rootfs_registry_source.dart';

void main() {
  final time = DateTime.utc(2026, 11, 17, 14);
  const checksum =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  RootfsArchiveDescriptor archive({
    String arch = 'arm64',
    String url = 'https://example.org/images/ubuntu.tar.gz',
    String sha256 = checksum,
    RootfsArchiveFormat format = RootfsArchiveFormat.tarGz,
  }) => RootfsArchiveDescriptor(
    arch: arch,
    url: url,
    sha256: sha256,
    format: format,
  );

  RootfsRegistryRelease release({List<RootfsArchiveDescriptor>? files}) =>
      RootfsRegistryRelease(
        id: 'ubuntu-24.04.4',
        distro: 'ubuntu',
        version: '24.04.4',
        codename: 'noble',
        archives: files ?? [archive()],
      );

  RootfsRegistryManifest manifest({List<RootfsRegistryRelease>? releases}) =>
      RootfsRegistryManifest(
        sourceId: 'official-candidates',
        publishedAt: time,
        releases: releases ?? [release()],
      );

  test('versioned registry JSON roundtrip', () {
    final model = manifest();
    final json = model.toJson();
    expect(json['schemaVersion'], 1);
    expect(RootfsRegistryManifest.fromJson(json).toJson(), json);
    expect(model.byId('ubuntu-24.04.4')?.archiveFor('arm64')?.sha256, checksum);
    expect(model.byId('missing'), isNull);
    expect(release().archiveFor('amd64'), isNull);
  });

  test('new candidate cannot silently change current pinned default', () {
    final json = manifest().toJson();
    expect(json.containsKey('defaultImage'), false);
    expect(json.containsKey('autoInstall'), false);
    expect(json.containsKey('trusted'), false);
  });

  test('rejects HTTPS credential, query, wrong format and digest', () {
    expect(
      () => archive(url: 'http://example.org/ubuntu.tar.gz'),
      throwsArgumentError,
    );
    expect(
      () => archive(url: 'https://user:pass@example.org/ubuntu.tar.gz'),
      throwsArgumentError,
    );
    expect(
      () => archive(url: 'https://example.org/ubuntu.tar.gz?token=1'),
      throwsArgumentError,
    );
    expect(
      () => archive(url: 'https://example.org/ubuntu.tar.xz'),
      throwsArgumentError,
    );
    expect(() => archive(sha256: 'bad'), throwsArgumentError);
    expect(() => archive(arch: 'mips'), throwsArgumentError);
  });

  test('rejects duplicate architectures and release identities', () {
    expect(() => release(files: [archive(), archive()]), throwsArgumentError);
    final first = release();
    expect(() => manifest(releases: [first, first]), throwsArgumentError);
  });

  test('enforces exact versioned schema and types', () {
    final json = manifest().toJson();
    expect(
      () => RootfsRegistryManifest.fromJson({...json, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => RootfsRegistryManifest.fromJson({...json, 'extra': 1}),
      throwsFormatException,
    );
    expect(
      () => RootfsRegistryManifest.fromJson({
        ...json,
        'publishedAt': '2026-11-17T14:00:00',
      }),
      throwsFormatException,
    );
    expect(
      () => RootfsRegistryManifest.fromJson({...json, 'releases': 'invalid'}),
      throwsFormatException,
    );
    final item = Map<String, Object?>.from(
      (json['releases'] as List).first as Map,
    );
    item['archives'] = [
      {'arch': 'arm64', 'url': 'https://example.org/evil'},
    ];
    expect(
      () => RootfsRegistryManifest.fromJson({
        ...json,
        'releases': [item],
      }),
      throwsFormatException,
    );
  });

  test('input collections are not retained or modifiable', () {
    final files = [archive()];
    final candidate = release(files: files);
    files.clear();
    expect(candidate.archives, hasLength(1));
    expect(() => candidate.archives.clear(), throwsUnsupportedError);
    final releases = [candidate];
    final registry = manifest(releases: releases);
    releases.clear();
    expect(registry.releases, hasLength(1));
    expect(() => registry.releases.clear(), throwsUnsupportedError);
  });

  test('invalid source identity and local timestamp fail', () {
    expect(
      () => RootfsRegistryManifest(
        sourceId: '../secret',
        publishedAt: time,
        releases: [],
      ),
      throwsArgumentError,
    );
    expect(
      () => RootfsRegistryManifest(
        sourceId: 'source',
        publishedAt: DateTime(2026, 11, 17),
        releases: [],
      ),
      throwsArgumentError,
    );
  });
  test('integer distro versions remain valid for Fedora releases', () {
    final fedora = RootfsRegistryRelease(
      id: 'fedora-43',
      distro: 'fedora',
      version: '43',
      codename: 'fedora',
      archives: [archive(url: 'https://example.org/images/fedora.tar.gz')],
    );
    expect(RootfsRegistryRelease.fromJson(fedora.toJson()).version, '43');
  });
}
