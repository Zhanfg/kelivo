import '../extensions/extension_manifest.dart';
import '../extensions/extension_registry.dart';

/// Side-effect-free parser for version-pinned extension declarations.
/// Native v1 records remain owned by UiRecordParser and are never rewritten.
final class UiExtensionImportParser {
  UiExtensionImportParser(this.registry);

  final UiExtensionRegistry registry;
  final Map<String, UiExtensionManifest> _namespaces = {};
  final Map<String, String> _components = {};

  static final _use = RegExp(
    r'^use ([a-z][a-z0-9-]{1,39}\.[a-z][a-z0-9-]{1,39})@([0-9]+\.[0-9]+\.[0-9]+) as ([a-zA-Z][a-zA-Z0-9_]*)$',
  );
  static final _import = RegExp(
    r'^import ([a-zA-Z][a-zA-Z0-9_]*)\.([a-zA-Z][a-zA-Z0-9_]*) as ([a-zA-Z][a-zA-Z0-9_]*)$',
  );
  static const _reserved = {'use', 'import', 'state', 'let', 'node'};

  /// Grammar: 'use example.package@1.2.3 as example'
  /// and 'import example.Widget as Alias' (single declarations, no semicolons).
  void parse(String source) {
    if (source.length > 320 || source.contains('\n') || source.contains('\r')) {
      throw const FormatException('Invalid extension declaration length');
    }
    final use = _use.firstMatch(source);
    if (use != null) {
      final package = use.group(1)!;
      final version = use.group(2)!;
      final alias = use.group(3)!;
      _checkAlias(alias);
      if (_namespaces.containsKey(alias) || _components.containsKey(alias)) {
        throw const FormatException('Duplicate alias');
      }
      final manifest = registry.resolve(package, version: version);
      if (manifest == null ||
          manifest.runtime != UiExtensionRuntime.sandboxedWeb) {
        throw const FormatException('Unregistered or unsafe extension');
      }
      _namespaces[alias] = manifest;
      return;
    }
    final import = _import.firstMatch(source);
    if (import != null) {
      final namespace = import.group(1)!;
      final component = import.group(2)!;
      final alias = import.group(3)!;
      _checkAlias(alias);
      if (_namespaces.containsKey(alias) || _components.containsKey(alias)) {
        throw const FormatException('Duplicate alias');
      }
      final manifest = _namespaces[namespace];
      if (manifest == null) throw const FormatException('Unknown namespace');
      if (!manifest.components.any((item) => item.name == component)) {
        throw const FormatException('Unknown extension component');
      }
      _components[alias] = manifest.componentReference(component);
      return;
    }
    throw const FormatException('Unsupported extension declaration');
  }

  /// Returns a namespaced component identity, not executable code or grants.
  String? resolveComponent(String alias) => _components[alias];

  Map<String, String> get importedComponents => Map.unmodifiable(_components);

  void _checkAlias(String alias) {
    if (alias.length > 64 || _reserved.contains(alias)) {
      throw const FormatException('Invalid or reserved alias');
    }
  }
}
