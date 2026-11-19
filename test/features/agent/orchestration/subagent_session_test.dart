import 'package:Kelivo/features/agent/orchestration/subagent_session.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026, 11, 20);

SubagentSession _session(
  String id, {
  String owner = 'owner:test',
  String? parent,
}) => SubagentSession(
  sessionId: 'session:$id',
  ownerId: owner,
  parentSessionId: parent,
  taskId: 'task:$id',
  contextRef: 'context:$id',
  createdAt: _time,
  updatedAt: _time,
);

void main() {
  test('session state transition and serialization', () {
    final first = _session('parent');
    final running = first.transition(SubagentSessionState.running, at: _time);
    final encoded = running.toJson();
    expect(SubagentSession.fromJson(encoded).toJson(), encoded);
    expect(encoded.containsKey('transcript'), isFalse);
    expect(encoded.containsKey('token'), isFalse);
  });

  test('running state is interrupted on restart, never auto-run', () {
    final running = _session('restart')
        .transition(SubagentSessionState.running, at: _time);
    final interrupted = running.interruptedAfterRestart(_time);
    expect(interrupted.state, SubagentSessionState.interrupted);
    expect(interrupted.interruptedAfterRestart(_time), same(interrupted));
    expect(
      interrupted.transition(SubagentSessionState.queued, at: _time).state,
      SubagentSessionState.queued,
    );
  });

  test('unknown side effects require explicit review', () {
    final running = _session('unknown')
        .transition(SubagentSessionState.running, at: _time);
    final unknown = running.transition(
      SubagentSessionState.outcomeUnknown,
      at: _time,
    );
    expect(
      () => unknown.transition(SubagentSessionState.completed, at: _time),
      throwsStateError,
    );
    expect(
      unknown
          .transition(
            SubagentSessionState.failed,
            at: _time,
            reviewedUnknownOutcome: true,
          )
          .state,
      SubagentSessionState.failed,
    );
  });

  test('terminal sessions reject further transitions', () {
    final done = _session('done')
        .transition(SubagentSessionState.running, at: _time)
        .transition(SubagentSessionState.completed, at: _time);
    expect(done.isTerminal, isTrue);
    expect(
      () => done.transition(SubagentSessionState.running, at: _time),
      throwsStateError,
    );
  });

  test('state time never moves backwards', () {
    final later = _time.add(const Duration(seconds: 2));
    final running = _session('time')
        .transition(SubagentSessionState.running, at: later);
    expect(
      () => running.transition(SubagentSessionState.failed, at: _time),
      throwsArgumentError,
    );
  });

  test('parent-child session catalog enforces owner isolation', () {
    final catalog = SubagentSessionCatalog();
    catalog.register(_session('parent'));
    final child = _session('child', parent: 'session:parent');
    catalog.register(child);
    expect(catalog.childrenOf('session:parent'), [same(child)]);
    expect(
      () => catalog.register(
        _session('foreign', parent: 'session:parent', owner: 'owner:other'),
      ),
      throwsStateError,
    );
    expect(() => catalog.register(child), throwsStateError);
    expect(
      () => catalog.register(_session('orphan', parent: 'session:missing')),
      throwsStateError,
    );
  });

  test('malformed, unknown version and sensitive fields fail closed', () {
    final json = _session('safe').toJson();
    expect(
      () => SubagentSession.fromJson({...json, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => SubagentSession.fromJson({...json, 'state': 'shell'}),
      throwsFormatException,
    );
    expect(
      () => SubagentSession.fromJson({...json, 'prompt': 'leak'}),
      throwsFormatException,
    );
    expect(
      () => SubagentSession.fromJson({...json, 'createdAt': 'bad'}),
      throwsFormatException,
    );
  });

  test('rejects self parenting, secretlike handles, invalid context', () {
    expect(() => _session('self', parent: 'session:self'), throwsArgumentError);
    expect(
      () => SubagentSession(
        sessionId: 'session:bad',
        ownerId: 'owner:test',
        taskId: 'task:bad',
        contextRef: '../private context',
        createdAt: _time,
        updatedAt: _time,
      ),
      throwsArgumentError,
    );
  });
}
