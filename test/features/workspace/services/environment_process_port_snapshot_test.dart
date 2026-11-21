import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/services/environment_process_port_snapshot.dart';

void main() {
  test('PRoot cannot masquerade as isolated network environment', () {
    final snapshot = EnvironmentProcessPortSnapshot.androidProot(
      environmentId: 'env:proot',
      processes: [
        ObservedProcess(
          pid: 100,
          kind: ObservedProcessKind.user,
          label: 'shell',
        ),
        ObservedProcess(
          pid: 101,
          kind: ObservedProcessKind.agent,
          label: 'agent',
        ),
      ],
      listeners: [
        ObservedListener(
          port: 8022,
          transport: ObservedTransport.tcp,
          loopbackOnly: true,
          processId: 100,
        ),
      ],
    );
    expect(snapshot.hasIsolatedNetwork, isFalse);
    expect(snapshot.networkScope, EnvironmentNetworkScope.sharedHost);
    expect(snapshot.processes.map((p) => p.kind), [
      ObservedProcessKind.user,
      ObservedProcessKind.agent,
    ]);
    expect(snapshot.listeners.single.loopbackOnly, isTrue);
  });
  test('invalid PID, port and duplicate processes rejected', () {
    expect(
      () => ObservedProcess(
        pid: 0,
        kind: ObservedProcessKind.unknown,
        label: 'bad',
      ),
      throwsArgumentError,
    );
    expect(
      () => ObservedListener(
        port: 65536,
        transport: ObservedTransport.udp,
        loopbackOnly: false,
      ),
      throwsArgumentError,
    );
    final p = ObservedProcess(
      pid: 1,
      kind: ObservedProcessKind.user,
      label: 'init',
    );
    expect(
      () => EnvironmentProcessPortSnapshot(
        environmentId: 'e',
        networkScope: EnvironmentNetworkScope.unknown,
        processes: [p, p],
        listeners: [],
      ),
      throwsArgumentError,
    );
  });
  test('observations are copied, read-only and cannot stop processes', () {
    final source = <ObservedProcess>[
      ObservedProcess(
        pid: 9,
        kind: ObservedProcessKind.system,
        label: 'system',
      ),
    ];
    final snapshot = EnvironmentProcessPortSnapshot.androidProot(
      environmentId: 'env:one',
      processes: source,
    );
    source.clear();
    expect(snapshot.processes.length, 1);
    expect(() => snapshot.processes.clear(), throwsUnsupportedError);
  });
}
