import '../../../core/services/artifacts/artifact_manifest.dart';
import 'artifact_resolver.dart';

/// #67 validates a pinned historical UI binding; never materializes bytes.
enum ArtifactHistoryDecision { allow, deny, fallback }

final class ArtifactHistoryBinding {
  ArtifactHistoryBinding({
    required this.reference,
    required this.originSourceId,
    required this.ownerScope,
    required this.ownerId,
    required this.extensionPackage,
    required this.extensionVersion,
  }) {
    final safe = RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$');
    final version = RegExp(
      r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
    );
    if (!safe.hasMatch(originSourceId) ||
        !safe.hasMatch(ownerId) ||
        !safe.hasMatch(extensionPackage) ||
        !version.hasMatch(extensionVersion)) {
      throw ArgumentError('Invalid historical source or extension pin');
    }
  }
  final UiArtifactReference reference;
  final String originSourceId;
  final ArtifactOwnerScope ownerScope;
  final String ownerId;
  final String extensionPackage;
  final String extensionVersion;
}

final class ArtifactHistoryProvenancePolicy {
  const ArtifactHistoryProvenancePolicy();

  ArtifactHistoryDecision check({
    required ArtifactHistoryBinding binding,
    required UiArtifactResolution resolution,
    required ArtifactOwnerScope requestingScope,
    required String requestingOwnerId,
    required String installedExtensionPackage,
    required String installedExtensionVersion,
  }) {
    if (requestingScope != binding.ownerScope ||
        requestingOwnerId != binding.ownerId ||
        binding.extensionPackage != installedExtensionPackage) {
      return ArtifactHistoryDecision.deny;
    }
    if (binding.extensionVersion != installedExtensionVersion) {
      return ArtifactHistoryDecision.fallback;
    }
    if (!resolution.canRender || resolution.manifest == null) {
      return ArtifactHistoryDecision.fallback;
    }
    final artifact = resolution.manifest!;
    if (artifact.ownerScope != binding.ownerScope ||
        artifact.ownerId != binding.ownerId ||
        artifact.sourceId != binding.originSourceId ||
        artifact.uri != binding.reference.uri ||
        artifact.sha256Hex != binding.reference.sha256Hex) {
      return ArtifactHistoryDecision.deny;
    }
    return ArtifactHistoryDecision.allow;
  }
}
