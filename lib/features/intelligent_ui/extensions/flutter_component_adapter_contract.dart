import 'extension_manifest.dart';

/// #63 Flutter adapter registry is a compile-time declaration only.
/// Flutter AOT does not import third-party Dart dynamically at runtime.
enum FlutterAdapterDecision { supported, rebuildRequired, denied }

final class CompiledFlutterAdapter {
  CompiledFlutterAdapter({
    required this.packageId,
    required this.version,
    required Iterable<String> componentNames,
  }) : componentNames = Set.unmodifiable(componentNames) {
    if (packageId.trim().isEmpty ||
        version.trim().isEmpty ||
        this.componentNames.isEmpty ||
        this.componentNames.any(
          (name) => !RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(name),
        )) {
      throw ArgumentError('Invalid compiled Flutter adapter');
    }
  }

  final String packageId;
  final String version;
  final Set<String> componentNames;
}

final class FlutterComponentAdapterContract {
  FlutterComponentAdapterContract(Iterable<CompiledFlutterAdapter> compiled)
    : _compiled = Map.unmodifiable({
        for (final item in compiled) item.packageId: item,
      }) {
    final all = compiled.toList();
    if (all.length != _compiled.length) {
      throw ArgumentError('Duplicate compiled adapter package');
    }
  }

  final Map<String, CompiledFlutterAdapter> _compiled;

  FlutterAdapterDecision resolve(
    UiExtensionManifest manifest,
    String component,
  ) {
    if (manifest.runtime != UiExtensionRuntime.compiledFlutter ||
        !manifest.components.any((c) => c.name == component)) {
      return FlutterAdapterDecision.denied;
    }
    final built = _compiled[manifest.packageId];
    if (built == null ||
        built.version != manifest.version ||
        !built.componentNames.contains(component)) {
      return FlutterAdapterDecision.rebuildRequired;
    }
    return FlutterAdapterDecision.supported;
  }
}
