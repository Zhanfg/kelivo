/// Protocol for a declarative IntelligentUI extension package.
///
/// This file only describes packages and components. It does not load code,
/// install libraries, grant permissions, or change kelivo.native/1 parsing.
enum UiExtensionRuntime {
  sandboxedWeb('sandboxed_web'),
  compiledFlutter('compiled_flutter');

  const UiExtensionRuntime(this.wireName);
  final String wireName;

  static UiExtensionRuntime parse(String value) {
    for (final runtime in values) {
      if (runtime.wireName == value) return runtime;
    }
    throw FormatException('Unknown extension runtime');
  }
}

enum UiExtensionValueType {
  string('string'),
  number('number'),
  boolean('boolean'),
  record('record'),
  array('array');

  const UiExtensionValueType(this.wireName);
  final String wireName;

  static UiExtensionValueType parse(String value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    throw FormatException('Unsupported UI value type');
  }
}

/// Namespaced, declarative component specification.
final class UiExtensionComponent {
  UiExtensionComponent({
    required this.name,
    required Map<String, UiExtensionValueType> properties,
    Set<String> requiredProperties = const {},
  }) : properties = Map.unmodifiable(properties),
       requiredProperties = Set.unmodifiable(requiredProperties) {
    if (!_identifier.hasMatch(name) ||
        name.length > 64 ||
        properties.isEmpty ||
        properties.length > 48 ||
        properties.keys.any((key) => !_identifier.hasMatch(key)) ||
        !this.requiredProperties.every(properties.containsKey)) {
      throw ArgumentError('Invalid extension component declaration');
    }
  }

  static final _identifier = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
  final String name;
  final Map<String, UiExtensionValueType> properties;
  final Set<String> requiredProperties;

  Map<String, Object?> toJson() => {
    'name': name,
    'properties': {
      for (final key in properties.keys.toList()..sort())
        key: properties[key]!.wireName,
    },
    'required': requiredProperties.toList()..sort(),
  };

  factory UiExtensionComponent.fromJson(Map<String, Object?> json) {
    _validateKeys(json, {'name', 'properties', 'required'});
    final raw = json['properties'];
    final required = json['required'];
    if (raw is! Map ||
        required is! List ||
        required.any((item) => item is! String)) {
      throw const FormatException('Invalid component properties or required');
    }
    final parsed = <String, UiExtensionValueType>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Invalid component property type');
      }
      parsed[entry.key as String] = UiExtensionValueType.parse(
        entry.value as String,
      );
    }
    try {
      return UiExtensionComponent(
        name: _string(json, 'name'),
        properties: parsed,
        requiredProperties: required.cast<String>().toSet(),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid UI component: ' + error.toString());
    }
  }
}

/// Installable package metadata. Requested capabilities are NOT grants.
///
/// Web extensions must run in a sandbox and ask the host for every action.
/// Compiled Flutter extensions require a new application build, not AOT import.
final class UiExtensionManifest {
  UiExtensionManifest({
    required this.packageId,
    required this.version,
    required this.runtime,
    required List<UiExtensionComponent> components,
    Set<String> requestedCapabilities = const {},
  }) : components = List.unmodifiable(components),
       requestedCapabilities = Set.unmodifiable(requestedCapabilities) {
    if (!_packageId.hasMatch(packageId) ||
        !_version.hasMatch(version) ||
        components.isEmpty ||
        components.length > 64 ||
        components.map((e) => e.name).toSet().length != components.length ||
        !this.requestedCapabilities.every(_allowedCapability.contains)) {
      throw ArgumentError('Invalid extension manifest');
    }
  }

  static const int schemaVersion = 1;
  static final _packageId = RegExp(
    r'^[a-z][a-z0-9-]{1,39}\.[a-z][a-z0-9-]{1,39}$',
  );
  static final _version = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
  );

  /// Explicit capability requests are reviewed during installation.
  /// Shell, Root, LSP, ambient file access and unrestricted MCP are forbidden.
  static const Set<String> _allowedCapability = {
    'artifact.read',
    'network.fetch',
    'clipboard.write',
  };

  final String packageId;
  final String version;
  final UiExtensionRuntime runtime;
  final List<UiExtensionComponent> components;
  final Set<String> requestedCapabilities;

  String get packageVersion => packageId + '@' + version;

  String componentReference(String component) {
    if (!components.any((item) => item.name == component)) {
      throw ArgumentError('Component not declared by package');
    }
    return packageVersion + '/' + component;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'packageId': packageId,
    'version': version,
    'runtime': runtime.wireName,
    'components': components.map((c) => c.toJson()).toList(),
    'requestedCapabilities': requestedCapabilities.toList()..sort(),
  };

  factory UiExtensionManifest.fromJson(Map<String, Object?> json) {
    _validateKeys(json, {
      'schemaVersion',
      'packageId',
      'version',
      'runtime',
      'components',
      'requestedCapabilities',
    });
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported UI extension manifest version');
    }
    final entries = json['components'];
    final permissions = json['requestedCapabilities'];
    if (entries is! List ||
        permissions is! List ||
        permissions.any((item) => item is! String)) {
      throw const FormatException('Invalid extension components/capabilities');
    }
    if (permissions.cast<String>().toSet().length != permissions.length) {
      throw const FormatException('Duplicate capability requests');
    }
    try {
      return UiExtensionManifest(
        packageId: _string(json, 'packageId'),
        version: _string(json, 'version'),
        runtime: UiExtensionRuntime.parse(_string(json, 'runtime')),
        components: entries.map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid component object');
          }
          return UiExtensionComponent.fromJson(Map<String, Object?>.from(item));
        }).toList(),
        requestedCapabilities: permissions.cast<String>().toSet(),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid extension manifest: ' + error.toString());
    }
  }
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException(key + ' must be a string');
  return value;
}

void _validateKeys(Map<String, Object?> json, Set<String> expected) {
  if (json.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(json.keys.toSet()).isNotEmpty) {
    throw const FormatException('Unknown or missing extension fields');
  }
}
