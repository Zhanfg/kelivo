// Version-pinned, in-memory extension registry. No dynamic code loading.
import 'extension_manifest.dart';

final class UiExtensionRegistry {
  final Map<String, UiExtensionManifest> _packages = {};
  final Map<String, String> _pins = {};

  /// Reject conflicting records rather than replacing code invisibly.
  void register(Map<String, Object?> encoded) {
    final parsed = UiExtensionManifest.fromJson(encoded);
    if (parsed.runtime == UiExtensionRuntime.compiledFlutter) {
      throw StateError('Compiled Flutter extensions need a new app build');
    }
    final key = parsed.packageVersion;
    if (_packages.containsKey(key)) throw StateError('Already registered');
    _packages[key] = parsed;
  }

  List<UiExtensionManifest> list({String? packageId}) => List.unmodifiable(
    _packages.values.where(
      (entry) => packageId == null || entry.packageId == packageId,
    ),
  );

  /// Pin must refer to an already registered package version.
  void pin(String packageId, String version) {
    if (!_packages.containsKey('$packageId@$version')) {
      throw StateError('Missing version');
    }
    _pins[packageId] = version;
  }

  UiExtensionManifest? resolve(String packageId, {String? version}) {
    final requestedVersion = version ?? _pins[packageId];
    if (requestedVersion == null) return null;
    return _packages['$packageId@$requestedVersion'];
  }

  /// A pinned version cannot disappear silently.
  void uninstall(String packageId, String version) {
    if (_pins[packageId] == version) {
      throw StateError('Unpin before uninstalling active version');
    }
    if (_packages.remove('$packageId@$version') == null) {
      throw StateError('Version not installed');
    }
  }

  void unpin(String packageId) => _pins.remove(packageId);
}
