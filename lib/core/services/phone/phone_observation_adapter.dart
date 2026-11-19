/// Platform-neutral observation receipt for Phone Use. This schema carries
/// sanitized node metadata and opaque screenshot references, not image bytes.
enum PhoneObservationSource { accessibility, screenshot, combined }

/// Normalized rectangle coordinates in the range [0, 1].
final class PhoneNodeBounds {
  PhoneNodeBounds(this.left, this.top, this.right, this.bottom) {
    if (![
          left,
          top,
          right,
          bottom,
        ].every((value) => value.isFinite && value >= 0 && value <= 1) ||
        left > right ||
        top > bottom) {
      throw ArgumentError('Invalid normalized bounds');
    }
  }

  final double left;
  final double top;
  final double right;
  final double bottom;

  List<double> toJson() => [left, top, right, bottom];

  factory PhoneNodeBounds.fromJson(Object? value) {
    if (value is! List || value.length != 4 || value.any((v) => v is! num)) {
      throw const FormatException('Invalid node bounds');
    }
    try {
      return PhoneNodeBounds(
        (value[0] as num).toDouble(),
        (value[1] as num).toDouble(),
        (value[2] as num).toDouble(),
        (value[3] as num).toDouble(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid normalized node bounds');
    }
  }
}

/// Sensitive fields MUST be omitted at capture time (not merely hidden in UI).
final class PhoneObservedNode {
  PhoneObservedNode({
    required this.id,
    required this.bounds,
    this.parentId,
    this.label,
    this.sensitive = false,
  }) {
    for (final identifier in [id, if (parentId != null) parentId!]) {
      if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(identifier)) {
        throw ArgumentError('Unsafe node identifier');
      }
    }
    if (parentId == id) throw ArgumentError('Node self-parenting');
    if (sensitive && label != null) {
      throw ArgumentError('Sensitive node label must be redacted');
    }
    if (label != null && (label!.length > 512 || label!.contains('\u0000'))) {
      throw ArgumentError('Unsafe node label');
    }
  }

  final String id;
  final String? parentId;
  final PhoneNodeBounds bounds;
  final String? label;
  final bool sensitive;

  Map<String, Object?> toJson() => {
    'id': id,
    'parentId': parentId,
    'bounds': bounds.toJson(),
    'label': label,
    'sensitive': sensitive,
  };

  factory PhoneObservedNode.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.keys.toSet().difference({
          'id',
          'parentId',
          'bounds',
          'label',
          'sensitive',
        }).isNotEmpty ||
        raw['id'] is! String ||
        raw['sensitive'] is! bool ||
        (raw['label'] != null && raw['label'] is! String) ||
        (raw['parentId'] != null && raw['parentId'] is! String)) {
      throw const FormatException('Invalid observed node');
    }
    try {
      return PhoneObservedNode(
        id: raw['id'] as String,
        parentId: raw['parentId'] as String?,
        bounds: PhoneNodeBounds.fromJson(raw['bounds']),
        label: raw['label'] as String?,
        sensitive: raw['sensitive'] as bool,
      );
    } on ArgumentError {
      throw const FormatException('Invalid observed node metadata');
    }
  }
}

final class PhoneObservation {
  PhoneObservation({
    required this.deviceRef,
    required this.windowRef,
    required this.source,
    required DateTime capturedAt,
    required List<PhoneObservedNode> nodes,
    this.screenshotRef,
  }) : capturedAt = capturedAt.toUtc(),
       nodes = List.unmodifiable(nodes) {
    final refPattern = RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$');
    if (!refPattern.hasMatch(deviceRef) ||
        !refPattern.hasMatch(windowRef) ||
        (screenshotRef != null && !refPattern.hasMatch(screenshotRef!))) {
      throw ArgumentError('Unsafe observation identifier');
    }
    if (nodes.length > 2000) throw ArgumentError('Too many nodes');
    if (source == PhoneObservationSource.screenshot && screenshotRef == null) {
      throw ArgumentError('Screenshot source requires an artifact reference');
    }
    final byId = {for (final node in nodes) node.id: node};
    if (byId.length != nodes.length) throw ArgumentError('Duplicate node IDs');
    for (final node in nodes) {
      final visited = <String>{};
      var current = node;
      while (current.parentId != null) {
        if (!visited.add(current.id)) {
          throw ArgumentError('Cyclic accessibility hierarchy');
        }
        final parent = byId[current.parentId];
        if (parent == null) throw ArgumentError('Missing node parent');
        current = parent;
      }
    }
  }

  static const schemaVersion = 1;

  final String deviceRef;
  final String windowRef;
  final PhoneObservationSource source;
  final DateTime capturedAt;
  final String? screenshotRef;
  final List<PhoneObservedNode> nodes;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'deviceRef': deviceRef,
    'windowRef': windowRef,
    'source': source.name,
    'capturedAt': capturedAt.toIso8601String(),
    'screenshotRef': screenshotRef,
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };

  factory PhoneObservation.fromJson(Map<String, Object?> raw) {
    if (raw.keys.toSet().difference({
          'schemaVersion',
          'deviceRef',
          'windowRef',
          'source',
          'capturedAt',
          'screenshotRef',
          'nodes',
        }).isNotEmpty ||
        raw['schemaVersion'] != schemaVersion ||
        raw['deviceRef'] is! String ||
        raw['windowRef'] is! String ||
        raw['source'] is! String ||
        raw['capturedAt'] is! String ||
        raw['nodes'] is! List ||
        (raw['screenshotRef'] != null && raw['screenshotRef'] is! String)) {
      throw const FormatException('Unsupported Phone Use observation');
    }
    final names = PhoneObservationSource.values.where(
      (value) => value.name == raw['source'],
    );
    final date = DateTime.tryParse(raw['capturedAt'] as String);
    if (names.length != 1 ||
        date == null ||
        !date.isUtc ||
        !(raw['capturedAt'] as String).endsWith('Z')) {
      throw const FormatException('Invalid observation source/time');
    }
    try {
      return PhoneObservation(
        deviceRef: raw['deviceRef'] as String,
        windowRef: raw['windowRef'] as String,
        source: names.single,
        capturedAt: date,
        screenshotRef: raw['screenshotRef'] as String?,
        nodes: (raw['nodes'] as List).map(PhoneObservedNode.fromJson).toList(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid observation hierarchy');
    }
  }
}
