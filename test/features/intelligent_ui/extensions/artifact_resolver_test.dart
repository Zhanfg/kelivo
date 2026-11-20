import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/artifacts/artifact_manifest.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/artifact_resolver.dart';

void main() {
  final manifest = ArtifactManifest(
    id: 'ui-artifact',
    mimeType: 'image/png',
    byteLength: 20,
    sha256Hex: 'a' * 64,
    createdAt: DateTime.utc(2026, 11, 21),
    sourceId: 'tool:render',
    ownerScope: ArtifactOwnerScope.workspace,
    ownerId: 'workspace:one',
  );
  UiArtifactReference ref({String? hash}) => UiArtifactReference(
    uri: manifest.uri,
    sha256Hex: hash ?? manifest.sha256Hex,
  );
  Future<UiArtifactResolution> resolve({
    ArtifactManifest? match,
    bool present = true,
    String owner = 'workspace:one',
  }) => const UiArtifactResolver().resolve(
    reference: ref(),
    requestingScope: ArtifactOwnerScope.workspace,
    requestingOwnerId: owner,
    lookup: (_) async => match,
    exists: (_) async => present,
  );

  test('pinned manifest and verified presence resolve to ready', () async {
    final result = await resolve(match: manifest);
    expect(result.status, UiArtifactResolutionStatus.ready);
    expect(result.manifest, same(manifest));
    expect(result.canRender, isTrue);
  });

  test('unavailable or deleted artifact yields missing fallback', () async {
    expect((await resolve()).status, UiArtifactResolutionStatus.missing);
    expect((await resolve(match: manifest, present: false)).canRender, isFalse);
  });

  test('cross-owner request denies before existence probe', () async {
    var checked = false;
    final result = await const UiArtifactResolver().resolve(
      reference: ref(),
      requestingScope: ArtifactOwnerScope.workspace,
      requestingOwnerId: 'workspace:other',
      lookup: (_) async => manifest,
      exists: (_) async {
        checked = true;
        return true;
      },
    );
    expect(result.status, UiArtifactResolutionStatus.permissionDenied);
    expect(checked, isFalse);
    expect(result.manifest, isNull);
  });

  test('historical reference digest pin rejects changed artifact', () async {
    final result = await const UiArtifactResolver().resolve(
      reference: ref(hash: 'b' * 64),
      requestingScope: ArtifactOwnerScope.workspace,
      requestingOwnerId: manifest.ownerId,
      lookup: (_) async => manifest,
      exists: (_) async => true,
    );
    expect(result.status, UiArtifactResolutionStatus.versionMismatch);
  });

  test('invalid or path-bearing artifact URI is refused', () {
    expect(
      () =>
          UiArtifactReference(uri: 'artifact://../secret', sha256Hex: 'a' * 64),
      throwsFormatException,
    );
    expect(
      () =>
          UiArtifactReference(uri: 'artifact:ui-artifact', sha256Hex: 'a' * 64),
      throwsFormatException,
    );
  });

  test('lookup returning mismatched manifest cannot change identity', () async {
    final other = ArtifactManifest(
      id: 'another',
      mimeType: 'image/png',
      byteLength: 20,
      sha256Hex: 'a' * 64,
      createdAt: DateTime.utc(2026, 11, 21),
      sourceId: 'tool:render',
      ownerScope: ArtifactOwnerScope.workspace,
      ownerId: 'workspace:one',
    );
    expect(
      (await resolve(match: other)).status,
      UiArtifactResolutionStatus.missing,
    );
  });
}
