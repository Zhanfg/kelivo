/// Serializable Environment Hub data model (not a process controller).
///
/// It exposes observed state for a future manual dashboard, and grants no
/// permission to execute commands, open listeners, or access the host.
enum EnvironmentBackend {
  androidProot('android_proot'),
  iosIsh('ios_ish'),
  nativeShell('native_shell'),
  remoteSsh('remote_ssh'),
  container('container'),
  wsl('wsl');

  const EnvironmentBackend(this.wireName);
  final String wireName;

  static EnvironmentBackend parse(String raw) {
    for (final item in values) {
      if (item.wireName == raw) return item;
    }
    throw FormatException('Unknown environment backend');
  }
}

enum EnvironmentLifecycle {
  notInstalled('not_installed'),
  installing('installing'),
  stopped('stopped'),
  running('running'),
  repairing('repairing'),
  failed('failed'),
  unsupported('unsupported');

  const EnvironmentLifecycle(this.wireName);
  final String wireName;

  static EnvironmentLifecycle parse(String raw) {
    for (final item in values) {
      if (item.wireName == raw) return item;
    }
    throw FormatException('Unknown environment state');
  }
}

enum EnvironmentPortProtocol {
  tcp('tcp'),
  udp('udp');

  const EnvironmentPortProtocol(this.wireName);
  final String wireName;

  static EnvironmentPortProtocol parse(String raw) {
    for (final item in values) {
      if (item.wireName == raw) return item;
    }
    throw FormatException('Unknown port protocol');
  }
}

/// Read-only observation; does not expose sockets or authorization handles.
final class EnvironmentPortSnapshot {
  EnvironmentPortSnapshot({
    required this.port,
    required this.protocol,
    required this.loopbackOnly,
  }) {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Invalid port');
    }
  }

  final int port;
  final EnvironmentPortProtocol protocol;
  final bool loopbackOnly;

  Map<String, Object?> toJson() => {
    'port': port,
    'protocol': protocol.wireName,
    'loopbackOnly': loopbackOnly,
  };

  factory EnvironmentPortSnapshot.fromJson(Map<String, Object?> json) {
    _keys(json, {'port', 'protocol', 'loopbackOnly'});
    try {
      final port = json['port'];
      final local = json['loopbackOnly'];
      if (port is! int || local is! bool) {
        throw const FormatException('Invalid port field type');
      }
      return EnvironmentPortSnapshot(
        port: port,
        protocol: EnvironmentPortProtocol.parse(_str(json, 'protocol')),
        loopbackOnly: local,
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid port: $e');
    }
  }
}

/// A single installed or discoverable environment instance.
final class EnvironmentInstanceSnapshot {
  EnvironmentInstanceSnapshot({
    required this.id,
    required this.label,
    required this.backend,
    required this.lifecycle,
    this.distribution,
    this.version,
    this.usedBytes,
    this.capacityBytes,
    List<EnvironmentPortSnapshot> ports = const [],
  }) : ports = List.unmodifiable(ports) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{2,79}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid environment ID');
    }
    if (label.trim().isEmpty || label.length > 96 || _controls(label)) {
      throw ArgumentError.value(label, 'label', 'Invalid display label');
    }
    for (final detail in [distribution, version]) {
      if (detail != null &&
          (!RegExp(
            r'^[a-zA-Z0-9][a-zA-Z0-9 ._+()-]{0,63}$',
          ).hasMatch(detail))) {
        throw ArgumentError('Invalid distribution/version token');
      }
    }
    if (usedBytes != null && usedBytes! < 0 ||
        capacityBytes != null && capacityBytes! < 0 ||
        usedBytes != null &&
            capacityBytes != null &&
            usedBytes! > capacityBytes!) {
      throw ArgumentError('Invalid capacity information');
    }
    if (ports.map((p) => '${p.protocol.wireName}:${p.port}').toSet().length !=
        ports.length) {
      throw ArgumentError('Duplicate observed ports');
    }
  }

  final String id;
  final String label;
  final EnvironmentBackend backend;
  final EnvironmentLifecycle lifecycle;
  final String? distribution;
  final String? version;
  final int? usedBytes;
  final int? capacityBytes;
  final List<EnvironmentPortSnapshot> ports;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'backend': backend.wireName,
    'lifecycle': lifecycle.wireName,
    if (distribution != null) 'distribution': distribution,
    if (version != null) 'version': version,
    if (usedBytes != null) 'usedBytes': usedBytes,
    if (capacityBytes != null) 'capacityBytes': capacityBytes,
    'ports': ports.map((p) => p.toJson()).toList(),
  };

  factory EnvironmentInstanceSnapshot.fromJson(Map<String, Object?> json) {
    _keys(
      json,
      {
        'id',
        'label',
        'backend',
        'lifecycle',
        'ports',
        'distribution',
        'version',
        'usedBytes',
        'capacityBytes',
      },
      required: {'id', 'label', 'backend', 'lifecycle', 'ports'},
    );
    final rawPorts = json['ports'];
    if (rawPorts is! List) {
      throw const FormatException('ports must be list');
    }
    final used = json['usedBytes'];
    final capacity = json['capacityBytes'];
    if (used != null && used is! int || capacity != null && capacity is! int) {
      throw const FormatException('Disk usage requires integer bytes');
    }
    try {
      return EnvironmentInstanceSnapshot(
        id: _str(json, 'id'),
        label: _str(json, 'label'),
        backend: EnvironmentBackend.parse(_str(json, 'backend')),
        lifecycle: EnvironmentLifecycle.parse(_str(json, 'lifecycle')),
        distribution: _maybeStr(json, 'distribution'),
        version: _maybeStr(json, 'version'),
        usedBytes: used as int?,
        capacityBytes: capacity as int?,
        ports: rawPorts.map((item) {
          if (item is! Map) throw const FormatException('Invalid port entry');
          return EnvironmentPortSnapshot.fromJson(
            Map<String, Object?>.from(item),
          );
        }).toList(),
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid environment instance: $e');
    }
  }
}

/// Entire read-only environment dashboard snapshot. No secrets/paths/actions.
final class EnvironmentHubSnapshot {
  EnvironmentHubSnapshot({
    required this.observedAt,
    required List<EnvironmentInstanceSnapshot> instances,
    this.selectedId,
  }) : instances = List.unmodifiable(instances) {
    if (!observedAt.isUtc ||
        instances.map((i) => i.id).toSet().length != instances.length ||
        selectedId != null && !instances.any((i) => i.id == selectedId)) {
      throw ArgumentError('Invalid hub timestamp, duplicate or selection');
    }
  }

  static const schemaVersion = 1;
  final DateTime observedAt;
  final List<EnvironmentInstanceSnapshot> instances;
  final String? selectedId;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'instances': instances.map((i) => i.toJson()).toList(),
    if (selectedId != null) 'selectedId': selectedId,
  };

  factory EnvironmentHubSnapshot.fromJson(Map<String, Object?> json) {
    _keys(
      json,
      {'schemaVersion', 'observedAt', 'instances', 'selectedId'},
      required: {'schemaVersion', 'observedAt', 'instances'},
    );
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported Environment Hub schema');
    }
    final rawTime = _str(json, 'observedAt');
    final time = DateTime.tryParse(rawTime);
    if (!rawTime.endsWith('Z') || time == null || !time.isUtc) {
      throw const FormatException('Observed time must be UTC ISO-8601');
    }
    final entries = json['instances'];
    if (entries is! List) {
      throw const FormatException('instances must be a list');
    }
    try {
      return EnvironmentHubSnapshot(
        observedAt: time,
        selectedId: _maybeStr(json, 'selectedId'),
        instances: entries.map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid environment entry');
          }
          return EnvironmentInstanceSnapshot.fromJson(
            Map<String, Object?>.from(item),
          );
        }).toList(),
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid hub snapshot: $e');
    }
  }
}

bool _controls(String input) => input.runes.any((r) => r < 32 || r == 127);

String _str(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw is! String) throw FormatException('$key must be string');
  return raw;
}

String? _maybeStr(Map<String, Object?> json, String key) {
  if (json[key] == null) return null;
  return _str(json, key);
}

void _keys(
  Map<String, Object?> json,
  Set<String> allowed, {
  Set<String>? required,
}) {
  final present = json.keys.toSet();
  if (present.difference(allowed).isNotEmpty ||
      (required ?? allowed).difference(present).isNotEmpty) {
    throw const FormatException('Unexpected or missing fields');
  }
}
