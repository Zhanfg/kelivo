import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/runtime/remote_execution_node_contract.dart';

void main() {
  RemoteNodeSession session() => RemoteNodeSession(
    RemoteNodeIdentity(
      id: 'remote:one',
      transport: 'ssh',
      taskScope: 'task:approved',
    ),
  );

  test('unauthorized or unverified host cannot connect', () {
    final s = session();
    expect(
      () => s.connect(authorized: false, hostVerified: true),
      throwsStateError,
    );
    expect(
      () => s.connect(authorized: true, hostVerified: false),
      throwsStateError,
    );
    expect(s.state, RemoteNodeLifecycle.disconnected);
  });

  test(
    'connection requires explicit readiness; disconnect requires review',
    () {
      final s = session();
      s.connect(authorized: true, hostVerified: true);
      expect(s.state, RemoteNodeLifecycle.connecting);
      expect(
        s.reattach(
          taskId: 'job:1',
          requestedScope: 'task:approved',
          verifiedTaskIdentity: true,
          outcomeKnown: true,
        ),
        RemoteReattachDecision.denied,
      );
      s.markConnected();
      s.interrupted();
      expect(
        s.reattach(
          taskId: 'job:1',
          requestedScope: 'task:approved',
          verifiedTaskIdentity: true,
          outcomeKnown: false,
        ),
        RemoteReattachDecision.denied,
      );
      s.connect(authorized: true, hostVerified: true);
      s.markConnected();
      expect(
        s.reattach(
          taskId: 'job:1',
          requestedScope: 'task:approved',
          verifiedTaskIdentity: true,
          outcomeKnown: false,
        ),
        RemoteReattachDecision.reviewRequired,
      );
    },
  );

  test('scoped known jobs reattach once without replay', () {
    final s = session();
    s.connect(authorized: true, hostVerified: true);
    s.markConnected();
    expect(
      s.reattach(
        taskId: 'job:1',
        requestedScope: 'task:other',
        verifiedTaskIdentity: true,
        outcomeKnown: true,
      ),
      RemoteReattachDecision.denied,
    );
    expect(
      s.reattach(
        taskId: 'job:1',
        requestedScope: 'task:approved',
        verifiedTaskIdentity: true,
        outcomeKnown: true,
      ),
      RemoteReattachDecision.attach,
    );
    expect(
      s.reattach(
        taskId: 'job:1',
        requestedScope: 'task:approved',
        verifiedTaskIdentity: true,
        outcomeKnown: true,
      ),
      RemoteReattachDecision.denied,
    );
  });

  test('status exposes no credential fields, close disables reattachment', () {
    final s = session();
    s.connect(authorized: true, hostVerified: true);
    s.markConnected();
    final status = s.publicStatus();
    expect(status.keys, unorderedEquals(['nodeId', 'transport', 'state']));
    s.close();
    expect(
      s.reattach(
        taskId: 'job:2',
        requestedScope: 'task:approved',
        verifiedTaskIdentity: true,
        outcomeKnown: true,
      ),
      RemoteReattachDecision.denied,
    );
  });
}
