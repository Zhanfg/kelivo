import 'extension_manifest.dart';

/// #66 install-time metadata audit. Does not create OS sandbox boundaries.
enum ExtensionInstallDecision { allowForReview, deny }

final class ExtensionInstallAuditPolicy {
  const ExtensionInstallAuditPolicy();

  static const allowedCapabilities = {
    'artifact.read',
    'network.fetch',
    'clipboard.write',
  };

  ExtensionInstallDecision check(
    UiExtensionManifest manifest, {
    required bool ownerConsent,
    required bool signatureVerified,
    required bool dependenciesPinned,
    required bool sandboxAvailable,
  }) {
    if (!ownerConsent ||
        !signatureVerified ||
        !dependenciesPinned ||
        !sandboxAvailable ||
        manifest.runtime != UiExtensionRuntime.sandboxedWeb ||
        manifest.requestedCapabilities.any(
          (c) => !allowedCapabilities.contains(c),
        )) {
      return ExtensionInstallDecision.deny;
    }
    return ExtensionInstallDecision.allowForReview;
  }

  /// Separate untrusted raw payload check: invalid/unknown capability names
  /// must fail before manifest parsing and never become implicit grants.
  ExtensionInstallDecision checkRawCapabilities(Iterable<String> capabilities) {
    if (capabilities.any((c) => !allowedCapabilities.contains(c))) {
      return ExtensionInstallDecision.deny;
    }
    return ExtensionInstallDecision.allowForReview;
  }
}
