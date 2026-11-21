/// #30 immutable provenance tag for a tool/agent result.
/// This is not cryptographic attestation. Only a trusted host may set verified.
enum TrustedResultOrigin { executedTool, storedCache, modelGenerated }

enum TrustedResultDecision { trustedEvidence, unverified }

final class TrustedResultProvenance {
  TrustedResultProvenance({
    required this.origin,
    required this.sourceId,
    required this.environmentId,
    required this.authorizationScope,
    required DateTime observedAt,
    required this.hostVerified,
    Map<String, String> metadata = const {},
  }) : observedAt = observedAt.toUtc(),
       metadata = Map.unmodifiable(metadata) {
    final safe = RegExp(r'^[a-zA-Z0-9_.:-]{1,128}$');
    if (!safe.hasMatch(sourceId) ||
        !safe.hasMatch(environmentId) ||
        !safe.hasMatch(authorizationScope) ||
        this.metadata.length > 16 ||
        this.metadata.entries.any(
          (entry) =>
              !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,47}$').hasMatch(entry.key) ||
              entry.value.length > 128 ||
              RegExp(
                r'(secret|token|password|credential|cookie|private|key)',
                caseSensitive: false,
              ).hasMatch(entry.key),
        )) {
      throw ArgumentError('Invalid or sensitive provenance metadata');
    }
  }

  final TrustedResultOrigin origin;
  final String sourceId;
  final String environmentId;
  final String authorizationScope;
  final DateTime observedAt;
  final bool hostVerified;
  final Map<String, String> metadata;

  TrustedResultDecision get decision =>
      origin == TrustedResultOrigin.executedTool && hostVerified
      ? TrustedResultDecision.trustedEvidence
      : TrustedResultDecision.unverified;

  Map<String, Object> toRedactedJson() => Map.unmodifiable({
    'origin': origin.name,
    'sourceId': sourceId,
    'environmentId': environmentId,
    'authorizationScope': authorizationScope,
    'observedAt': observedAt.toIso8601String(),
    'hostVerified': hostVerified,
    'metadata': metadata,
  });
}
