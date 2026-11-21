/// Passive process/service/listener observations. Never executes or kills.
enum EnvironmentNetworkScope { sharedHost, isolatedGuest, unknown }

enum ObservedProcessKind { user, agent, system, unknown }

enum ObservedTransport { tcp, udp }

final class ObservedProcess {
  ObservedProcess({
    required this.pid,
    required this.kind,
    required this.label,
  }) {
    if (pid <= 0 ||
        label.trim().isEmpty ||
        label.length > 96 ||
        label.contains(RegExp(r'[\x00-\x1f]'))) {
      throw ArgumentError('Invalid process snapshot');
    }
  }
  final int pid;
  final ObservedProcessKind kind;
  final String label;
}

final class ObservedListener {
  ObservedListener({
    required this.port,
    required this.transport,
    required this.loopbackOnly,
    this.processId,
  }) {
    if (port < 1 || port > 65535 || processId != null && processId! <= 0) {
      throw ArgumentError('Invalid listener snapshot');
    }
  }
  final int port;
  final ObservedTransport transport;
  final bool loopbackOnly;
  final int? processId;
}

final class EnvironmentProcessPortSnapshot {
  EnvironmentProcessPortSnapshot({
    required this.environmentId,
    required this.networkScope,
    required List<ObservedProcess> processes,
    required List<ObservedListener> listeners,
  }) : processes = List.unmodifiable(processes),
       listeners = List.unmodifiable(listeners) {
    if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,128}$').hasMatch(environmentId)) {
      throw ArgumentError('Invalid environment ID');
    }
    if (this.processes.map((p) => p.pid).toSet().length !=
        this.processes.length) {
      throw ArgumentError('Duplicated process IDs');
    }
  }
  final String environmentId;
  final EnvironmentNetworkScope networkScope;
  final List<ObservedProcess> processes;
  final List<ObservedListener> listeners;

  bool get hasIsolatedNetwork =>
      networkScope == EnvironmentNetworkScope.isolatedGuest;

  /// PRoot shares host networking and must not be labeled network-isolated.
  factory EnvironmentProcessPortSnapshot.androidProot({
    required String environmentId,
    List<ObservedProcess> processes = const [],
    List<ObservedListener> listeners = const [],
  }) => EnvironmentProcessPortSnapshot(
    environmentId: environmentId,
    networkScope: EnvironmentNetworkScope.sharedHost,
    processes: processes,
    listeners: listeners,
  );
}
