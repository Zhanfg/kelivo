import 'extension_manifest.dart';

/// Platform-neutral policy/lifecycle contract for a sandboxed WebView host.
///
/// No WebView is instantiated here. The host must separately enforce OS-level
/// isolation, navigation interception, CSP, and permission mediation.
enum WebExtensionSurfaceState { prepared, active, suspended, disposed }

final class WebExtensionSurface {
  WebExtensionSurface({
    required this.manifest,
    required Iterable<Uri> allowedOrigins,
  }) : allowedOrigins = Set.unmodifiable(allowedOrigins) {
    if (manifest.runtime != UiExtensionRuntime.sandboxedWeb) {
      throw ArgumentError('Only sandboxed Web extension runtime accepted');
    }
    for (final origin in this.allowedOrigins) {
      if (origin.scheme != 'https' ||
          origin.host.isEmpty ||
          origin.userInfo.isNotEmpty ||
          origin.hasQuery ||
          origin.hasFragment ||
          origin.path.isNotEmpty ||
          origin.hasPort) {
        throw ArgumentError('Unsafe WebView origin');
      }
    }
  }

  final UiExtensionManifest manifest;
  final Set<Uri> allowedOrigins;
  WebExtensionSurfaceState _state = WebExtensionSurfaceState.prepared;

  WebExtensionSurfaceState get state => _state;

  /// No ambient tool bridge is ever offered by this contract.
  bool get permitsArbitraryHostTools => false;
  bool get isRendered => _state == WebExtensionSurfaceState.active;

  void activate() {
    if (_state != WebExtensionSurfaceState.prepared &&
        _state != WebExtensionSurfaceState.suspended) {
      throw StateError('Cannot activate surface in $_state');
    }
    _state = WebExtensionSurfaceState.active;
  }

  void suspend() {
    if (_state != WebExtensionSurfaceState.active) {
      throw StateError('Can only suspend an active surface');
    }
    _state = WebExtensionSurfaceState.suspended;
  }

  void dispose() {
    if (_state == WebExtensionSurfaceState.disposed) return;
    _state = WebExtensionSurfaceState.disposed;
  }

  /// Host navigation must be denied unless both the package requested the
  /// capability and the exact HTTPS origin is included in the host allowlist.
  bool permitsNavigation(Uri destination) {
    if (_state != WebExtensionSurfaceState.active ||
        !manifest.requestedCapabilities.contains('network.fetch') ||
        destination.scheme != 'https' ||
        destination.userInfo.isNotEmpty ||
        destination.hasFragment ||
        destination.hasPort ||
        destination.host.isEmpty) {
      return false;
    }
    final origin = Uri(scheme: destination.scheme, host: destination.host);
    return allowedOrigins.contains(origin);
  }
}
