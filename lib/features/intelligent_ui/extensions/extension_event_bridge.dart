import 'dart:collection';

/// UI extension messages are typed receipts, not executable commands.
enum ExtensionEventKind { props, event, value, acknowledgement }

final class ExtensionEvent {
  ExtensionEvent({
    required this.namespace,
    required this.instanceId,
    required this.sequence,
    required this.kind,
    required this.payload,
    required this.origin,
  }) {
    final identifier = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.:-]{0,79}$');
    if (!identifier.hasMatch(namespace) ||
        !identifier.hasMatch(instanceId) ||
        sequence < 1 ||
        sequence > 0x7fffffff ||
        payload.length > 32 ||
        !{ExtensionOrigin.host, ExtensionOrigin.extension}.contains(origin)) {
      throw ArgumentError('Malformed extension event envelope');
    }
    if (!_safeMap(payload, 0)) {
      throw ArgumentError('Invalid extension value payload');
    }
  }

  final String namespace;
  final String instanceId;
  final int sequence;
  final ExtensionEventKind kind;
  final ExtensionOrigin origin;
  final Map<String, Object?> payload;

  static bool _safeMap(Map<String, Object?> map, int depth) {
    if (depth > 6) return false;
    for (final entry in map.entries) {
      if (entry.key.length > 80 || entry.key.startsWith('__')) return false;
      if (!_safeValue(entry.value, depth + 1)) return false;
    }
    return true;
  }

  static bool _safeValue(Object? value, int depth) {
    if (value == null || value is bool) return true;
    if (value is int) return true;
    if (value is double) return value.isFinite;
    if (value is String) return value.length <= 4096;
    if (value is List) {
      return value.length <= 128 &&
          depth <= 6 &&
          value.every((item) => _safeValue(item, depth + 1));
    }
    if (value is Map<String, Object?>) return _safeMap(value, depth + 1);
    return false;
  }
}

enum ExtensionOrigin { host, extension }

/// Explicit namespace+instance authorization. No cross-origin forwarding.
final class ExtensionEventBridge {
  ExtensionEventBridge({
    required this.namespace,
    required this.instanceId,
    this.maxOutstanding = 16,
  }) {
    if (maxOutstanding < 1 || maxOutstanding > 256) {
      throw ArgumentError('Invalid backpressure budget');
    }
  }

  final String namespace;
  final String instanceId;
  final int maxOutstanding;

  final Queue<ExtensionEvent> _outstanding = Queue();
  final Set<int> _recentSequences = <int>{};
  int _lastSequence = 0;

  int get outstandingCount => _outstanding.length;

  /// A receipt means only validation and queue admission; no host side effect.
  void receive(ExtensionEvent envelope) {
    if (envelope.namespace != namespace || envelope.instanceId != instanceId) {
      throw StateError('Extension event crossed its capability scope');
    }
    if (envelope.origin == ExtensionOrigin.extension &&
        envelope.kind == ExtensionEventKind.props) {
      throw StateError('Untrusted extension cannot set host props');
    }
    if (envelope.kind == ExtensionEventKind.acknowledgement) {
      acknowledge(envelope.sequence);
      return;
    }
    if (envelope.sequence <= _lastSequence ||
        _recentSequences.contains(envelope.sequence)) {
      throw StateError('Replay or out-of-order event');
    }
    if (_outstanding.length >= maxOutstanding) {
      throw StateError('Extension bridge backpressure limit reached');
    }
    _lastSequence = envelope.sequence;
    _recentSequences.add(envelope.sequence);
    _outstanding.add(envelope);
  }

  ExtensionEvent? peek() => _outstanding.isEmpty ? null : _outstanding.first;

  void acknowledge(int sequence) {
    if (_outstanding.isEmpty || _outstanding.first.sequence != sequence) {
      throw StateError('Only the oldest outstanding event may be acknowledged');
    }
    _outstanding.removeFirst();
  }

  /// Disposal clears queued receipts but never replays or executes them.
  void clear() => _outstanding.clear();
}
