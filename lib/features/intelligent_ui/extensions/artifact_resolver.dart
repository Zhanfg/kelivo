import '../../../core/services/artifacts/artifact_manifest.dart';

/// A UI binding carries an opaque URI and a pinned digest; never a file path.
final class UiArtifactReference {
  UiArtifactReference({required this.uri, required this.sha256Hex}) {
    ArtifactManifest.idFromUri(uri);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hex)) {
      throw ArgumentError('Invalid pinned artifact checksum');
    }
  }

  final String uri;
  final String sha256Hex;
}

enum UiArtifactResolutionStatus {
  ready,
  missing,
  permissionDenied,
  versionMismatch,
}

final class UiArtifactResolution {
  const UiArtifactResolution(this.status, {this.manifest});
  final UiArtifactResolutionStatus status;
  final ArtifactManifest? manifest;
  bool get canRender => status == UiArtifactResolutionStatus.ready;
}

/// Fail-closed resolver for historical IntelligentUI source references.
///
/// The host supplies an authorized manifest lookup and availability probe.
/// No bytes are opened and no ambient filesystem permission is granted.
final class UiArtifactResolver {
  const UiArtifactResolver();

  Future<UiArtifactResolution> resolve({
    required UiArtifactReference reference,
    required ArtifactOwnerScope requestingScope,
    required String requestingOwnerId,
    required Future<ArtifactManifest?> Function(String id) lookup,
    required Future<bool> Function(ArtifactManifest manifest) exists,
  }) async {
    if (requestingOwnerId.isEmpty) {
      return const UiArtifactResolution(
        UiArtifactResolutionStatus.permissionDenied,
      );
    }
    final id = ArtifactManifest.idFromUri(reference.uri);
    final manifest = await lookup(id);
    if (manifest == null || manifest.id != id) {
      return const UiArtifactResolution(UiArtifactResolutionStatus.missing);
    }
    if (manifest.ownerScope != requestingScope ||
        manifest.ownerId != requestingOwnerId) {
      // Do not probe existence of an artifact belonging to another owner.
      return const UiArtifactResolution(
        UiArtifactResolutionStatus.permissionDenied,
      );
    }
    if (manifest.sha256Hex != reference.sha256Hex) {
      return const UiArtifactResolution(
        UiArtifactResolutionStatus.versionMismatch,
      );
    }
    if (!await exists(manifest)) {
      return const UiArtifactResolution(UiArtifactResolutionStatus.missing);
    }
    return UiArtifactResolution(
      UiArtifactResolutionStatus.ready,
      manifest: manifest,
    );
  }
}
