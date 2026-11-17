/// Protocol data model for an artifact's identity and integrity.
///
/// An artifact is addressed by an opaque identifier and described by what a
/// consumer needs in order to prove it holds the right bytes: MIME type, byte
/// length, SHA-256, creation instant, producing source, and owning scope. The
/// manifest carries no local path, no reference to a local file, and no
/// credential material, so it is safe to serialize into a conversation record,
/// a workspace index, or a task row.
///
/// ## Identifier and URI form
///
/// The identifier is rendered as `artifact://<id>`, an **authority-form** URI:
/// `<id>` occupies the authority (host) component, and the URI carries no
/// user-info, no port, no path, no query, and no fragment.
///
/// The competing rendering, `artifact:<id>`, is an opaque
/// (non-hierarchical) URI. It is not used, and
/// [ArtifactManifest.idFromUri] rejects it. Keeping exactly one form means a
/// consumer that splits a URI at the first `/` never has to guess whether the
/// tail is a path or part of the identifier.
///
/// Authority form constrains the identifier. RFC 3986 host components are
/// case-insensitive, and Dart's [Uri] folds the host to lowercase, so an id
/// containing uppercase letters would not survive `Uri.parse(uri).host`.
/// Identifiers are therefore restricted to `[a-z0-9][a-z0-9._~-]*`: lowercase
/// alphanumeric first character, then lowercase alphanumerics and the
/// unreserved symbols `.`, `_`, `~`, `-`. Nothing in that set needs
/// percent-encoding, so the rendered URI and its parsed form are identical and
/// identity is stable across every hop. As a consequence, `/`, `\`, `?`, `#`,
/// `%`, `..`, whitespace, and control characters are all rejected —
/// path traversal cannot even be expressed.
///
/// ## JSON shape
///
/// | key             | field                          |
/// | --------------- | ------------------------------ |
/// | `schemaVersion` | always `1`                     |
/// | `id`            | [id]                           |
/// | `uri`           | [uri] (`artifact://<id>`)      |
/// | `mimeType`      | [mimeType]                     |
/// | `byteLength`    | [byteLength]                   |
/// | `sha256Hex`     | [sha256Hex]                    |
/// | `createdAt`     | [createdAt] (ISO-8601 UTC)     |
/// | `sourceId`      | [sourceId]                     |
/// | `ownerScope`    | [ownerScope] (wire token)      |
/// | `ownerId`       | [ownerId]                      |
/// | `displayName`   | [displayName] (omitted if null)|
///
/// Instant serializes as `createdAt.toUtc().toIso8601String()` and therefore
/// always ends in `Z`; parsing requires an explicit UTC instant, offsetless
/// strings are rejected rather than guessed against the local zone. [uri] is
/// stored alongside [id] and must agree with it, so a payload whose identity
/// fields disagree is refused instead of silently preferring one of them.
///
/// Parsing is strict. Unknown schema versions, unknown enum tokens, unknown
/// keys, missing keys, and wrongly typed values are all rejected: a payload
/// that would lose information on re-serialization is a payload this model
/// does not accept. [fromJson] reports every rejection as a [FormatException];
/// the constructor reports invalid arguments as [ArgumentError].
library;

/// Scope that owns an artifact.
///
/// Serializes as its [wireName], never as the enum index, so reordering or
/// inserting a value cannot silently remap existing records.
enum ArtifactOwnerScope {
  conversation('conversation'),
  workspace('workspace'),
  task('task');

  const ArtifactOwnerScope(this.wireName);

  /// Stable wire token for this scope.
  final String wireName;

  /// Parses a wire token, rejecting anything not in [values].
  static ArtifactOwnerScope fromWireName(String wireName) {
    for (final scope in ArtifactOwnerScope.values) {
      if (scope.wireName == wireName) {
        return scope;
      }
    }
    throw FormatException('unknown artifact owner scope: $wireName');
  }
}

/// Immutable identity and integrity record for one artifact.
///
/// Instances are validated on construction and hold only `final` fields, so a
/// manifest cannot be mutated after it exists and cannot disagree with itself.
class ArtifactManifest {
  /// Validates every field. Throws [ArgumentError] for an invalid one.
  ///
  /// [createdAt] must already be UTC — pass `DateTime.utc(...)` or
  /// `.toUtc()` — because a manifest that carries a local instant would
  /// serialize to a different moment depending on the host's time zone.
  ArtifactManifest({
    required this.id,
    required this.mimeType,
    required this.byteLength,
    required this.sha256Hex,
    required this.createdAt,
    required this.sourceId,
    required this.ownerScope,
    required this.ownerId,
    String? displayName,
  }) : displayName = _validateDisplayName(displayName) {
    _validateId(id);
    _validateMimeType(mimeType);
    if (byteLength < 0) {
      throw ArgumentError.value(
        byteLength,
        'byteLength',
        'byteLength must not be negative',
      );
    }
    _validateSha256Hex(sha256Hex);
    if (!createdAt.isUtc) {
      throw ArgumentError.value(
        createdAt,
        'createdAt',
        'createdAt must be UTC; pass DateTime.utc(...) or .toUtc()',
      );
    }
    _validateIdentityValue(sourceId, 'sourceId');
    _validateIdentityValue(ownerId, 'ownerId');
  }

  /// Schema version this model reads and writes.
  static const int schemaVersion = 1;

  /// Prefix of the authority-form artifact URI.
  static const String uriPrefix = 'artifact://';

  /// Opaque artifact identifier, `[a-z0-9][a-z0-9._~-]*`.
  final String id;

  /// Lowercase MIME type of the artifact bytes, `type/subtype`, without
  /// parameters.
  final String mimeType;

  /// Exact size of the artifact bytes.
  final int byteLength;

  /// Lowercase hex SHA-256 of the artifact bytes, exactly 64 characters.
  final String sha256Hex;

  /// Creation instant, always UTC.
  final DateTime createdAt;

  /// Identifier of whatever produced the artifact (a tool, a run, an import).
  final String sourceId;

  /// Scope that owns the artifact.
  final ArtifactOwnerScope ownerScope;

  /// Identifier of the owning conversation, workspace, or task.
  final String ownerId;

  /// Optional human-readable label.
  ///
  /// Safe to render and safe to use as a file-name component: no path
  /// separator, no `..`, no control character, and none of `< > : " | ? *`.
  /// It is never a path and never part of the artifact's identity.
  final String? displayName;

  /// Authority-form URI for [id]: `artifact://<id>`.
  String get uri => '$uriPrefix$id';

  /// Renders the authority-form URI for [id], validating it first.
  static String uriFor(String id) {
    _validateId(id);
    return '$uriPrefix$id';
  }

  /// Extracts the identifier from an authority-form artifact URI.
  ///
  /// Rejects the opaque form `artifact:<id>`, any path, query, or fragment,
  /// and any id that fails the identifier rules.
  static String idFromUri(String uriString) {
    if (!uriString.startsWith(uriPrefix)) {
      throw FormatException(
        'not an artifact URI (expected $uriPrefix<id>): $uriString',
      );
    }
    final id = uriString.substring(uriPrefix.length);
    try {
      _validateId(id);
    } on ArgumentError catch (error) {
      throw FormatException('invalid artifact id in URI $uriString: $error');
    }
    final parsed = Uri.parse(uriString);
    if (parsed.scheme != 'artifact' ||
        parsed.host != id ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasPort ||
        !parsed.hasEmptyPath ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw FormatException('artifact URI must be bare: $uriString');
    }
    return id;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'id': id,
      'uri': uri,
      'mimeType': mimeType,
      'byteLength': byteLength,
      'sha256Hex': sha256Hex,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'sourceId': sourceId,
      'ownerScope': ownerScope.wireName,
      'ownerId': ownerId,
      if (displayName != null) 'displayName': displayName,
    };
  }

  /// Parses a manifest, rejecting anything [toJson] would not reproduce.
  factory ArtifactManifest.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version is! int || version != schemaVersion) {
      throw FormatException(
        'unsupported artifact manifest schemaVersion: $version',
      );
    }
    for (final key in json.keys) {
      if (!_jsonKeys.contains(key)) {
        throw FormatException('unknown artifact manifest field: $key');
      }
    }

    final id = _readString(json, 'id');
    final uri = _readString(json, 'uri');
    if (uri != '$uriPrefix$id') {
      throw FormatException('artifact manifest uri does not match id: $uri');
    }

    final byteLength = json['byteLength'];
    if (byteLength is! int) {
      throw FormatException(
        'artifact manifest byteLength must be an integer: $byteLength',
      );
    }

    final createdAtRaw = _readString(json, 'createdAt');
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null || !createdAt.isUtc) {
      throw FormatException(
        'artifact manifest createdAt must be an ISO-8601 UTC instant: '
        '$createdAtRaw',
      );
    }

    try {
      return ArtifactManifest(
        id: id,
        mimeType: _readString(json, 'mimeType'),
        byteLength: byteLength,
        sha256Hex: _readString(json, 'sha256Hex'),
        createdAt: createdAt,
        sourceId: _readString(json, 'sourceId'),
        ownerScope: ArtifactOwnerScope.fromWireName(
          _readString(json, 'ownerScope'),
        ),
        ownerId: _readString(json, 'ownerId'),
        displayName: _readOptionalString(json, 'displayName'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('invalid artifact manifest: $error');
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArtifactManifest &&
        other.id == id &&
        other.mimeType == mimeType &&
        other.byteLength == byteLength &&
        other.sha256Hex == sha256Hex &&
        other.createdAt == createdAt &&
        other.sourceId == sourceId &&
        other.ownerScope == ownerScope &&
        other.ownerId == ownerId &&
        other.displayName == displayName;
  }

  @override
  int get hashCode => Object.hash(
    id,
    mimeType,
    byteLength,
    sha256Hex,
    createdAt,
    sourceId,
    ownerScope,
    ownerId,
    displayName,
  );

  @override
  String toString() {
    final label = displayName;
    return 'ArtifactManifest(id: $id, uri: $uri, mimeType: $mimeType, '
        'byteLength: $byteLength, sha256Hex: $sha256Hex, '
        'createdAt: ${createdAt.toUtc().toIso8601String()}, '
        'sourceId: $sourceId, ownerScope: ${ownerScope.wireName}, '
        'ownerId: $ownerId'
        '${label == null ? '' : ', displayName: $label'})';
  }
}

const Set<String> _jsonKeys = <String>{
  'schemaVersion',
  'id',
  'uri',
  'mimeType',
  'byteLength',
  'sha256Hex',
  'createdAt',
  'sourceId',
  'ownerScope',
  'ownerId',
  'displayName',
};

final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9._~-]*$');

final RegExp _mimeTypePattern = RegExp(
  r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$',
);

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

final RegExp _fileNameForbidden = RegExp(r'[<>:"/\\|?*]');

const int _maxDisplayNameLength = 255;

String _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException(
      'artifact manifest $key must be a string: $value',
    );
  }
  return value;
}

String? _readOptionalString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  return _readString(json, key);
}

void _validateId(String id) {
  if (id.isEmpty) {
    throw ArgumentError.value(id, 'id', 'artifactId must not be empty');
  }
  if (id.contains('/') || id.contains('\\')) {
    throw ArgumentError.value(
      id,
      'id',
      'artifactId must not contain path separators',
    );
  }
  if (id.contains('?')) {
    throw ArgumentError.value(
      id,
      'id',
      'artifactId must not contain query syntax',
    );
  }
  if (id.contains('#')) {
    throw ArgumentError.value(
      id,
      'id',
      'artifactId must not contain fragment syntax',
    );
  }
  if (id.contains('..')) {
    throw ArgumentError.value(
      id,
      'id',
      'artifactId must not contain ".." segments',
    );
  }
  if (_containsControlCharacter(id)) {
    throw ArgumentError.value(
      id,
      'id',
      'artifactId must not contain control characters',
    );
  }
  if (!_idPattern.hasMatch(id)) {
    throw ArgumentError.value(
      id,
      'id',
      'artifactId must match [a-z0-9][a-z0-9._~-]*',
    );
  }
}

void _validateMimeType(String mimeType) {
  if (!_mimeTypePattern.hasMatch(mimeType)) {
    throw ArgumentError.value(
      mimeType,
      'mimeType',
      'mimeType must be a lowercase type/subtype without parameters',
    );
  }
}

void _validateSha256Hex(String sha256Hex) {
  if (!_sha256Pattern.hasMatch(sha256Hex)) {
    throw ArgumentError.value(
      sha256Hex,
      'sha256Hex',
      'sha256Hex must be exactly 64 lowercase hexadecimal characters',
    );
  }
}

void _validateIdentityValue(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be blank');
  }
  if (_containsControlCharacter(value)) {
    throw ArgumentError.value(
      value,
      name,
      '$name must not contain control characters',
    );
  }
}

String? _validateDisplayName(String? displayName) {
  if (displayName == null) return null;
  if (displayName.trim().isEmpty) {
    throw ArgumentError.value(displayName, 'displayName', 'must not be blank');
  }
  if (displayName.length > _maxDisplayNameLength) {
    throw ArgumentError.value(
      displayName,
      'displayName',
      'must be at most $_maxDisplayNameLength characters',
    );
  }
  if (_fileNameForbidden.hasMatch(displayName)) {
    throw ArgumentError.value(
      displayName,
      'displayName',
      'must not contain < > : " / \\ | ? *',
    );
  }
  if (displayName == '.' || displayName.contains('..')) {
    throw ArgumentError.value(
      displayName,
      'displayName',
      'must not be "." or contain ".."',
    );
  }
  if (_containsControlCharacter(displayName)) {
    throw ArgumentError.value(
      displayName,
      'displayName',
      'must not contain control characters',
    );
  }
  return displayName;
}

bool _containsControlCharacter(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || (codeUnit >= 0x7F && codeUnit <= 0x9F)) {
      return true;
    }
  }
  return false;
}
