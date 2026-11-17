/// Wire contract for Kelivo's capability probe (issue #103, schema v1).
///
/// These types describe *what a capability is*, never how it is detected: no
/// platform probing, no UI, no tool dispatch, no I/O. A future probe layer
/// produces [CapabilityReport] values against this schema; bridge code
/// serializes them with [CapabilityReport.toJson] / [CapabilityReport.fromJson].
///
/// Every invariant below is enforced at construction and again at parse time,
/// and every violation throws rather than being repaired or defaulted
/// (fail-closed):
///
/// - [CapabilityReport.observedAt] is UTC. Non-UTC input is rejected, and a
///   serialized timestamp must declare its zone.
/// - [CapabilityDescriptor.id] is non-empty, lowercase kebab or dotted, and
///   unique inside a report.
/// - Only the four [CapabilityAvailability] values decode. An unknown wire
///   value is a [FormatException], never a fallback to `unsupported`.
/// - Metadata carries non-sensitive string values only. Keys naming a
///   credential (`secret`, `token`, `key`, `password`, …) are rejected, and
///   values are bounded in count, key length, value length and character set.
/// - Instances are immutable: descriptor lists and metadata maps are
///   unmodifiable views taken at construction.
///
/// Serialized shape (`reason` and `metadata` are optional; every other key is
/// required):
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "platform": "ios",
///   "architecture": "arm64",
///   "observedAt": "2026-02-01T09:30:00.000Z",
///   "descriptors": [
///     {
///       "id": "camera.capture",
///       "availability": "permission_required",
///       "reason": "camera permission not granted",
///       "metadata": {"backend": "avfoundation"}
///     }
///   ]
/// }
/// ```
///
/// Unknown extra keys are ignored on decode so a newer writer can add fields
/// without breaking an older reader; a missing or mistyped required key is
/// still fatal.
library;

import 'package:collection/collection.dart';

/// Schema version written by [CapabilityReport.toJson] and the only version
/// accepted by [CapabilityReport.fromJson].
const int capabilitySchemaVersion = 1;

/// Maximum length of a [CapabilityDescriptor.id].
const int capabilityIdMaxLength = 64;

/// Maximum length of a [CapabilityDescriptor.reason].
const int capabilityReasonMaxLength = 280;

/// Maximum number of entries in [CapabilityDescriptor.metadata].
const int capabilityMetadataMaxEntries = 32;

/// Maximum length of a [CapabilityDescriptor.metadata] key.
const int capabilityMetadataKeyMaxLength = 64;

/// Maximum length of a [CapabilityDescriptor.metadata] value.
const int capabilityMetadataValueMaxLength = 256;

/// Maximum length of [CapabilityReport.platform].
const int capabilityPlatformMaxLength = 32;

/// Maximum length of [CapabilityReport.architecture].
const int capabilityArchitectureMaxLength = 64;

final RegExp _idPattern = RegExp(r'^[a-z0-9]+(?:[.-][a-z0-9]+)*$');
final RegExp _metadataKeyPattern = RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$');
final RegExp _platformTokenPattern = RegExp(r'^[a-z0-9][a-z0-9._+-]*$');
final RegExp _keySeparatorPattern = RegExp(r'[._-]');

/// Key segments that name a credential. Matching is per segment, so
/// `keyboard_layout` passes while `api_key` and `public-key` do not.
const Set<String> _sensitiveKeySegments = <String>{
  'auth',
  'authorization',
  'bearer',
  'cookie',
  'cookies',
  'credential',
  'credentials',
  'key',
  'keys',
  'otp',
  'passwd',
  'password',
  'pin',
  'private',
  'pwd',
  'secret',
  'secrets',
  'seed',
  'session',
  'signature',
  'token',
  'tokens',
};

const MapEquality<String, String> _metadataEquality =
    MapEquality<String, String>();

const ListEquality<CapabilityDescriptor> _descriptorsEquality =
    ListEquality<CapabilityDescriptor>();

/// Whether a capability is usable on the current device.
enum CapabilityAvailability {
  /// Present and usable now.
  available('available'),

  /// Present but switched off by user or configuration.
  disabled('disabled'),

  /// Present, but blocked until a permission is granted.
  permissionRequired('permission_required'),

  /// Not present on this platform or build.
  unsupported('unsupported');

  const CapabilityAvailability(this.wireName);

  /// Value used on the wire.
  final String wireName;

  /// Decodes a wire value, rejecting anything outside this enum.
  static CapabilityAvailability fromJson(Object? raw) {
    for (final value in values) {
      if (value.wireName == raw) {
        return value;
      }
    }
    throw FormatException('unknown capability availability: $raw');
  }
}

/// One probed capability: a stable id, its availability, and optional
/// non-sensitive detail.
///
/// The constructor validates its arguments and copies [metadata], so a
/// descriptor never aliases caller-owned collections.
class CapabilityDescriptor {
  CapabilityDescriptor({
    required String id,
    required this.availability,
    String? reason,
    Map<String, String> metadata = const <String, String>{},
  }) : id = _validateId(id),
       reason = _validateReason(reason),
       metadata = _validateMetadata(metadata);

  /// Stable capability identifier: lowercase, `.` or `-` separated segments
  /// (e.g. `camera.capture`, `tts-local`). At most [capabilityIdMaxLength].
  final String id;

  /// Current availability of the capability.
  final CapabilityAvailability availability;

  /// Human-readable explanation, normally set for every availability other
  /// than [CapabilityAvailability.available].
  final String? reason;

  /// Non-sensitive diagnostic fields. Unmodifiable and never credential
  /// bearing; keys are sorted on serialize so output is deterministic.
  final Map<String, String> metadata;

  /// Serializes to the schema v1 wire shape.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'availability': availability.wireName,
      if (reason != null) 'reason': reason,
      if (metadata.isNotEmpty)
        'metadata': <String, String>{
          for (final key in _sortedKeys(metadata)) key: metadata[key] as String,
        },
    };
  }

  /// Parses a wire map, throwing [FormatException] on any malformed field.
  factory CapabilityDescriptor.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('descriptor id must be a string');
    }
    final reason = json['reason'];
    if (reason != null && reason is! String) {
      throw const FormatException('descriptor reason must be a string');
    }
    return CapabilityDescriptor(
      id: id,
      availability: CapabilityAvailability.fromJson(json['availability']),
      reason: reason as String?,
      metadata: _readMetadata(json['metadata']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CapabilityDescriptor &&
        other.id == id &&
        other.availability == availability &&
        other.reason == reason &&
        _metadataEquality.equals(other.metadata, metadata);
  }

  @override
  int get hashCode =>
      Object.hash(id, availability, reason, _metadataEquality.hash(metadata));

  @override
  String toString() => 'CapabilityDescriptor($id, ${availability.wireName})';
}

/// A full capability snapshot for one device at one instant.
///
/// Immutable: [descriptors] is an unmodifiable copy of the list passed in, and
/// ids are unique within the report.
class CapabilityReport {
  CapabilityReport({
    required String platform,
    required String architecture,
    required DateTime observedAt,
    List<CapabilityDescriptor> descriptors = const <CapabilityDescriptor>[],
  }) : platform = _validatePlatformToken(
         'platform',
         platform,
         capabilityPlatformMaxLength,
       ),
       architecture = _validatePlatformToken(
         'architecture',
         architecture,
         capabilityArchitectureMaxLength,
       ),
       observedAt = _validateObservedAt(observedAt),
       descriptors = _validateDescriptors(descriptors);

  /// Host platform as a lowercase token (`ios`, `android`, `macos`,
  /// `windows`, `linux`, `web`).
  final String platform;

  /// Host architecture as a lowercase token (`arm64`, `x64`, `x86_64`).
  final String architecture;

  /// Instant the snapshot was taken, always UTC.
  final DateTime observedAt;

  /// Probed capabilities in probe order; ids are unique.
  final List<CapabilityDescriptor> descriptors;

  /// Descriptor with [id], or `null` when this report does not carry it.
  CapabilityDescriptor? operator [](String id) {
    for (final descriptor in descriptors) {
      if (descriptor.id == id) {
        return descriptor;
      }
    }
    return null;
  }

  /// Serializes to the schema v1 wire shape. Timestamps are always written
  /// with a `Z` designator.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': capabilitySchemaVersion,
      'platform': platform,
      'architecture': architecture,
      'observedAt': observedAt.toUtc().toIso8601String(),
      'descriptors': <Map<String, dynamic>>[
        for (final descriptor in descriptors) descriptor.toJson(),
      ],
    };
  }

  /// Parses a wire map, throwing [FormatException] on any malformed field,
  /// unknown availability value, duplicate id or foreign schema version.
  factory CapabilityReport.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version != capabilitySchemaVersion) {
      throw FormatException('unsupported schemaVersion: $version');
    }
    final platform = json['platform'];
    if (platform is! String) {
      throw const FormatException('platform must be a string');
    }
    final architecture = json['architecture'];
    if (architecture is! String) {
      throw const FormatException('architecture must be a string');
    }
    final observedAt = json['observedAt'];
    if (observedAt is! String) {
      throw const FormatException('observedAt must be an ISO-8601 UTC string');
    }
    final rawDescriptors = json['descriptors'];
    if (rawDescriptors is! List) {
      throw const FormatException('descriptors must be a list');
    }
    final descriptors = <CapabilityDescriptor>[];
    for (final raw in rawDescriptors) {
      if (raw is! Map) {
        throw const FormatException('descriptor entries must be objects');
      }
      descriptors.add(
        CapabilityDescriptor.fromJson(Map<String, dynamic>.from(raw)),
      );
    }
    return CapabilityReport(
      platform: platform,
      architecture: architecture,
      observedAt: _parseObservedAt(observedAt),
      descriptors: descriptors,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CapabilityReport &&
        other.platform == platform &&
        other.architecture == architecture &&
        other.observedAt == observedAt &&
        _descriptorsEquality.equals(other.descriptors, descriptors);
  }

  @override
  int get hashCode => Object.hash(
    platform,
    architecture,
    observedAt,
    _descriptorsEquality.hash(descriptors),
  );

  @override
  String toString() =>
      'CapabilityReport($platform/$architecture, '
      '${descriptors.length} descriptors)';
}

String _validateId(String id) {
  if (id.isEmpty) {
    throw const FormatException('capability id must not be empty');
  }
  if (id.length > capabilityIdMaxLength) {
    throw FormatException(
      'capability id longer than $capabilityIdMaxLength chars: ${id.length}',
    );
  }
  if (!_idPattern.hasMatch(id)) {
    throw FormatException('invalid capability id: $id');
  }
  return id;
}

String? _validateReason(String? reason) {
  if (reason == null) {
    return null;
  }
  if (reason.isEmpty) {
    throw const FormatException('capability reason must not be empty');
  }
  if (reason.length > capabilityReasonMaxLength) {
    throw FormatException(
      'capability reason longer than $capabilityReasonMaxLength chars: '
      '${reason.length}',
    );
  }
  if (_hasControlCharacter(reason)) {
    throw const FormatException(
      'capability reason contains control characters',
    );
  }
  return reason;
}

Map<String, String> _validateMetadata(Map<String, String> metadata) {
  if (metadata.isEmpty) {
    return const <String, String>{};
  }
  if (metadata.length > capabilityMetadataMaxEntries) {
    throw FormatException(
      'metadata has more than $capabilityMetadataMaxEntries entries: '
      '${metadata.length}',
    );
  }
  final copy = <String, String>{};
  for (final entry in metadata.entries) {
    final key = entry.key;
    if (!_metadataKeyPattern.hasMatch(key)) {
      throw FormatException('invalid metadata key: $key');
    }
    if (key.length > capabilityMetadataKeyMaxLength) {
      throw FormatException(
        'metadata key longer than $capabilityMetadataKeyMaxLength chars: $key',
      );
    }
    if (_namesCredential(key)) {
      throw FormatException('sensitive metadata key: $key');
    }
    final value = entry.value;
    if (value.isEmpty) {
      throw FormatException('empty metadata value for: $key');
    }
    if (value.length > capabilityMetadataValueMaxLength) {
      throw FormatException(
        'metadata value longer than $capabilityMetadataValueMaxLength chars '
        'for: $key',
      );
    }
    if (_hasControlCharacter(value)) {
      throw FormatException('metadata value has control characters for: $key');
    }
    copy[key] = value;
  }
  return Map<String, String>.unmodifiable(copy);
}

Map<String, String> _readMetadata(Object? raw) {
  if (raw == null) {
    return const <String, String>{};
  }
  if (raw is! Map) {
    throw const FormatException('descriptor metadata must be an object');
  }
  final result = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) {
      throw const FormatException('metadata keys must be strings');
    }
    final value = entry.value;
    if (value is! String) {
      throw FormatException('metadata value for $key must be a string');
    }
    result[key] = value;
  }
  return result;
}

String _validatePlatformToken(String field, String value, int maxLength) {
  if (value.isEmpty) {
    throw FormatException('$field must not be empty');
  }
  if (value.length > maxLength) {
    throw FormatException(
      '$field longer than $maxLength chars: ${value.length}',
    );
  }
  if (!_platformTokenPattern.hasMatch(value)) {
    throw FormatException('invalid $field token: $value');
  }
  return value;
}

DateTime _validateObservedAt(DateTime observedAt) {
  if (!observedAt.isUtc) {
    throw ArgumentError.value(
      observedAt,
      'observedAt',
      'capability timestamps must be UTC',
    );
  }
  return observedAt;
}

DateTime _parseObservedAt(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('observedAt is not an ISO-8601 timestamp: $raw');
  }
  if (!parsed.isUtc) {
    throw FormatException('observedAt must declare UTC: $raw');
  }
  return parsed;
}

List<CapabilityDescriptor> _validateDescriptors(
  List<CapabilityDescriptor> descriptors,
) {
  final seen = <String>{};
  for (final descriptor in descriptors) {
    if (!seen.add(descriptor.id)) {
      throw FormatException('duplicate capability id: ${descriptor.id}');
    }
  }
  return List<CapabilityDescriptor>.unmodifiable(descriptors);
}

bool _namesCredential(String key) {
  for (final segment in key.split(_keySeparatorPattern)) {
    if (_sensitiveKeySegments.contains(segment)) {
      return true;
    }
  }
  return false;
}

bool _hasControlCharacter(String text) {
  for (final unit in text.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) {
      return true;
    }
  }
  return false;
}

List<String> _sortedKeys(Map<String, String> map) => map.keys.toList()..sort();
