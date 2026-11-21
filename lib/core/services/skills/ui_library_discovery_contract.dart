/// Offline, review-only discovery contract for third-party UI libraries.
///
/// This model never downloads, imports, executes or installs remote code.
enum UiLibrarySource { pubDev, npm, github, extensionRegistry }

enum UiLibraryDelivery { compiledSdk, runtimeExtension }

enum UiLibraryDecision { review, reject }

class UiLibraryCandidate {
  const UiLibraryCandidate({
    required this.id,
    required this.source,
    required this.url,
    required this.license,
    required this.targetPlatforms,
    required this.lastUpdated,
    required this.dependencies,
    required this.delivery,
    this.hasInstallationScript = false,
  });

  final String id;
  final UiLibrarySource source;
  final Uri url;
  final String? license;
  final Set<String> targetPlatforms;
  final DateTime? lastUpdated;
  final List<String> dependencies;
  final UiLibraryDelivery delivery;
  final bool hasInstallationScript;
}

class UiLibraryReview {
  const UiLibraryReview({
    required this.decision,
    required this.reasons,
    required this.adaptationSteps,
    required this.requiresRebuild,
  });

  final UiLibraryDecision decision;
  final List<String> reasons;
  final List<String> adaptationSteps;
  final bool requiresRebuild;

  bool get eligibleForAutomaticExecution => false;
}

class UiLibraryDiscoveryContract {
  const UiLibraryDiscoveryContract();

  UiLibraryReview review(
    UiLibraryCandidate candidate, {
    required String targetPlatform,
    required DateTime now,
    Duration maintenanceWindow = const Duration(days: 730),
  }) {
    final reasons = <String>[];
    if (candidate.id.trim().isEmpty) reasons.add('missing package identity');
    if (candidate.url.scheme != 'https' || candidate.url.host.isEmpty) {
      reasons.add('non-HTTPS source');
    }
    if (candidate.license == null || candidate.license!.trim().isEmpty) {
      reasons.add('unknown license');
    }
    if (!candidate.targetPlatforms.contains(targetPlatform)) {
      reasons.add('unsupported target platform');
    }
    if (candidate.lastUpdated == null ||
        candidate.lastUpdated!.isAfter(now) ||
        now.difference(candidate.lastUpdated!) > maintenanceWindow) {
      reasons.add('unverified maintenance freshness');
    }
    if (candidate.dependencies.any((dependency) => dependency.trim().isEmpty)) {
      reasons.add('invalid dependency metadata');
    }
    if (candidate.hasInstallationScript) {
      reasons.add('remote installation script requires manual security review');
    }

    final requiresRebuild = candidate.delivery == UiLibraryDelivery.compiledSdk;
    return UiLibraryReview(
      decision: reasons.isEmpty
          ? UiLibraryDecision.review
          : UiLibraryDecision.reject,
      reasons: List.unmodifiable(reasons),
      requiresRebuild: requiresRebuild,
      adaptationSteps: List.unmodifiable([
        'Verify canonical publisher, license, lockfile and dependency graph',
        'Review supported platforms and current maintenance status',
        if (requiresRebuild)
          'Add SDK dependency in source control and rebuild the application'
        else
          'Validate the extension manifest and capabilities in a sandbox',
        'Run isolated compatibility and security checks before human approval',
      ]),
    );
  }
}
