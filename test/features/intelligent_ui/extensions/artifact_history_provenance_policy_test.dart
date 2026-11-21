import 'package:Kelivo/core/services/artifacts/artifact_manifest.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/artifact_history_provenance_policy.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/artifact_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final artifact = ArtifactManifest(
    id: 'history-safe',
    mimeType: 'image/png',
    byteLength: 32,
    sha256Hex: 'a' * 64,
    createdAt: DateTime.utc(2026, 11, 21),
    sourceId: 'tool:render',
    ownerScope: ArtifactOwnerScope.workspace,
    ownerId: 'workspace:one',
  );
  final ref = UiArtifactReference(
    uri: artifact.uri,
    sha256Hex: artifact.sha256Hex,
  );
  ArtifactHistoryBinding binding({
    String source = 'tool:render',
    String version = '1.2.3',
  }) => ArtifactHistoryBinding(
    reference: ref,
    originSourceId: source,
    ownerScope: ArtifactOwnerScope.workspace,
    ownerId: 'workspace:one',
    extensionPackage: 'example.widgets',
    extensionVersion: version,
  );
  ArtifactHistoryDecision check(
    ArtifactHistoryBinding item,
    UiArtifactResolution result, {
    String owner = 'workspace:one',
    String version = '1.2.3',
  }) => const ArtifactHistoryProvenancePolicy().check(
    binding: item,
    resolution: result,
    requestingScope: ArtifactOwnerScope.workspace,
    requestingOwnerId: owner,
    installedExtensionPackage: 'example.widgets',
    installedExtensionVersion: version,
  );
  final ready = UiArtifactResolution(
    UiArtifactResolutionStatus.ready,
    manifest: artifact,
  );

  test(
    'verified provenance, owner and extension pin permit history recovery',
    () {
      expect(check(binding(), ready), ArtifactHistoryDecision.allow);
    },
  );
  test('cross-owner and spoofed source cannot render an artifact', () {
    expect(
      check(binding(), ready, owner: 'workspace:other'),
      ArtifactHistoryDecision.deny,
    );
    expect(
      check(binding(source: 'model:generated'), ready),
      ArtifactHistoryDecision.deny,
    );
  });
  test(
    'missing, denied or changed content falls back instead of hallucinating',
    () {
      for (final status in [
        UiArtifactResolutionStatus.missing,
        UiArtifactResolutionStatus.permissionDenied,
        UiArtifactResolutionStatus.versionMismatch,
      ]) {
        expect(
          check(binding(), UiArtifactResolution(status)),
          ArtifactHistoryDecision.fallback,
        );
      }
    },
  );
  test('extension version changes require safe fallback', () {
    expect(
      check(binding(), ready, version: '1.2.4'),
      ArtifactHistoryDecision.fallback,
    );
    expect(() => binding(version: 'latest'), throwsArgumentError);
  });
}
