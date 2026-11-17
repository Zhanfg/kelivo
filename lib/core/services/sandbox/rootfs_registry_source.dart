/// Pure data contract for a versioned, untrusted rootfs release manifest.
///
/// The existing pinned [RootfsCatalog] remains authoritative for installations.
/// Parsing this model never downloads archives or changes the default image.
enum RootfsArchiveFormat {
  tarGz('tar.gz'),
  tarXz('tar.xz');

  const RootfsArchiveFormat(this.wireValue);
  final String wireValue;

  static RootfsArchiveFormat fromWire(String value) {
    for (final item in values) {
      if (item.wireValue == value) return item;
    }
    throw FormatException('Unsupported rootfs archive format: ' + value);
  }
}

/// Download locator and digest for one host architecture.
final class RootfsArchiveDescriptor {
  RootfsArchiveDescriptor({
    required this.arch,
    required this.url,
    required this.sha256,
    required this.format,
  }) {
    if (!const {'arm64', 'armhf', 'amd64'}.contains(arch)) {
      throw ArgumentError.value(arch, 'arch', 'Unsupported architecture');
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.port != 443) {
      throw ArgumentError.value(url, 'url', 'Expected HTTPS archive URL');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw ArgumentError.value(sha256, 'sha256', 'Expected lowercase SHA-256');
    }
    if (!parsed.path.endsWith('.' + format.wireValue)) {
      throw ArgumentError('Archive format does not match URL extension');
    }
  }

  final String arch;
  final String url;
  final String sha256;
  final RootfsArchiveFormat format;

  Map<String, Object?> toJson() => {
    'arch': arch,
    'url': url,
    'sha256': sha256,
    'format': format.wireValue,
  };

  factory RootfsArchiveDescriptor.fromJson(Map<String, Object?> value) {
    _exactKeys(value, {'arch', 'url', 'sha256', 'format'});
    try {
      return RootfsArchiveDescriptor(
        arch: _string(value, 'arch'),
        url: _string(value, 'url'),
        sha256: _string(value, 'sha256'),
        format: RootfsArchiveFormat.fromWire(_string(value, 'format')),
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid rootfs archive: ' + e.toString());
    }
  }
}

/// Candidate release. A release can be shown in the UI but cannot be
/// installed until its manifest source and archive digest are verified.
final class RootfsRegistryRelease {
  RootfsRegistryRelease({
    required this.id,
    required this.distro,
    required this.version,
    required this.codename,
    required List<RootfsArchiveDescriptor> archives,
  }) : archives = List.unmodifiable(archives) {
    if (!RegExp(r'^[a-z][a-z0-9-]{1,30}$').hasMatch(distro) ||
        !RegExp(r'^[a-z][a-z0-9-]{0,31}$').hasMatch(codename) ||
        !RegExp(r'^[0-9]+(?:\.[0-9]+){0,3}$').hasMatch(version) ||
        id != distro + '-' + version ||
        archives.isEmpty ||
        archives.map((a) => a.arch).toSet().length != archives.length) {
      throw ArgumentError('Invalid rootfs release identity or archives');
    }
  }

  final String id;
  final String distro;
  final String version;
  final String codename;
  final List<RootfsArchiveDescriptor> archives;

  RootfsArchiveDescriptor? archiveFor(String arch) {
    for (final archive in archives) {
      if (archive.arch == arch) return archive;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'distro': distro,
    'version': version,
    'codename': codename,
    'archives': archives.map((a) => a.toJson()).toList(),
  };

  factory RootfsRegistryRelease.fromJson(Map<String, Object?> value) {
    _exactKeys(value, {'id', 'distro', 'version', 'codename', 'archives'});
    final items = value['archives'];
    if (items is! List) throw const FormatException('archives must be a list');
    try {
      return RootfsRegistryRelease(
        id: _string(value, 'id'),
        distro: _string(value, 'distro'),
        version: _string(value, 'version'),
        codename: _string(value, 'codename'),
        archives: items.map((x) {
          if (x is! Map) throw const FormatException('Invalid archive entry');
          return RootfsArchiveDescriptor.fromJson(Map<String, Object?>.from(x));
        }).toList(),
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid release: ' + e.toString());
    }
  }
}

/// Signed-source metadata is intentionally not part of this contract:
/// validating this object DOES NOT authenticate its publisher.
///
/// The network provider must verify a trusted signature or independently
/// pinned digest before accepting any candidate release for installation.
final class RootfsRegistryManifest {
  RootfsRegistryManifest({
    required this.sourceId,
    required this.publishedAt,
    required List<RootfsRegistryRelease> releases,
  }) : releases = List.unmodifiable(releases) {
    if (!RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(sourceId) ||
        !publishedAt.isUtc ||
        releases.map((e) => e.id).toSet().length != releases.length) {
      throw ArgumentError('Invalid registry source, time or duplicate release');
    }
  }

  static const schemaVersion = 1;
  final String sourceId;
  final DateTime publishedAt;
  final List<RootfsRegistryRelease> releases;

  RootfsRegistryRelease? byId(String id) {
    for (final entry in releases) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'sourceId': sourceId,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'releases': releases.map((e) => e.toJson()).toList(),
  };

  factory RootfsRegistryManifest.fromJson(Map<String, Object?> value) {
    _exactKeys(value, {'schemaVersion', 'sourceId', 'publishedAt', 'releases'});
    if (value['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported rootfs registry schema');
    }
    final dateText = _string(value, 'publishedAt');
    final date = DateTime.tryParse(dateText);
    if (!dateText.endsWith('Z') || date == null || !date.isUtc) {
      throw const FormatException('publishedAt must use ISO-8601 UTC');
    }
    final items = value['releases'];
    if (items is! List) throw const FormatException('releases must be a list');
    try {
      return RootfsRegistryManifest(
        sourceId: _string(value, 'sourceId'),
        publishedAt: date,
        releases: items.map((e) {
          if (e is! Map) throw const FormatException('Invalid release');
          return RootfsRegistryRelease.fromJson(Map<String, Object?>.from(e));
        }).toList(),
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid rootfs registry: ' + e.toString());
    }
  }
}

String _string(Map<String, Object?> obj, String key) {
  final value = obj[key];
  if (value is! String) throw FormatException(key + ' must be string');
  return value;
}

void _exactKeys(Map<String, Object?> value, Set<String> allowed) {
  if (value.keys.toSet().difference(allowed).isNotEmpty ||
      allowed.difference(value.keys.toSet()).isNotEmpty) {
    throw const FormatException('Unexpected or missing registry fields');
  }
}
