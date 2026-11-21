/// #54 remote node contract and simulation only.
/// This file never starts SSH, opens a socket or handles credentials.
enum RemoteNodeLifecycle {
  disconnected,
  connecting,
  connected,
  interrupted,
  closed,
}

enum RemoteReattachDecision { attach, reviewRequired, denied }

final class RemoteNodeIdentity {
  RemoteNodeIdentity({
    required this.id,
    required this.transport,
    required this.taskScope,
  }) {
    final safe = RegExp(r'^[a-zA-Z0-9_.:-]{1,96}$');
    if (!safe.hasMatch(id) ||
        !safe.hasMatch(taskScope) ||
        transport != 'ssh' && transport != 'container') {
      throw ArgumentError('Invalid remote node identity');
    }
  }
  final String id;
  final String transport;
  final String taskScope;
}

final class RemoteNodeSession {
  RemoteNodeSession(this.identity);
  final RemoteNodeIdentity identity;
  RemoteNodeLifecycle _state = RemoteNodeLifecycle.disconnected;
  RemoteNodeLifecycle get state => _state;
  final Set<String> _attachedTasks = {};

  void connect({required bool authorized, required bool hostVerified}) {
    if (_state != RemoteNodeLifecycle.disconnected &&
        _state != RemoteNodeLifecycle.interrupted) {
      throw StateError('Invalid remote node state');
    }
    if (!authorized || !hostVerified) {
      throw StateError('Authorization and host verification required');
    }
    _state = RemoteNodeLifecycle.connecting;
  }

  void markConnected() {
    if (_state != RemoteNodeLifecycle.connecting) {
      throw StateError('Unsolicited connection');
    }
    _state = RemoteNodeLifecycle.connected;
  }

  void interrupted() {
    if (_state != RemoteNodeLifecycle.connected) {
      throw StateError('Only a connected session can be interrupted');
    }
    _state = RemoteNodeLifecycle.interrupted;
  }

  RemoteReattachDecision reattach({
    required String taskId,
    required String requestedScope,
    required bool verifiedTaskIdentity,
    required bool outcomeKnown,
  }) {
    if (_state != RemoteNodeLifecycle.connected ||
        requestedScope != identity.taskScope ||
        !verifiedTaskIdentity ||
        taskId.trim().isEmpty) {
      return RemoteReattachDecision.denied;
    }
    if (!outcomeKnown) return RemoteReattachDecision.reviewRequired;
    if (!_attachedTasks.add(taskId)) {
      return RemoteReattachDecision.denied;
    }
    return RemoteReattachDecision.attach;
  }

  void close() {
    _state = RemoteNodeLifecycle.closed;
    _attachedTasks.clear();
  }

  /// No secret payload or private key is modeled or serialized.
  Map<String, String> publicStatus() => Map.unmodifiable({
    'nodeId': identity.id,
    'transport': identity.transport,
    'state': _state.name,
  });
}
