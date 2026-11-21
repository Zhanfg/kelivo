import 'package:Kelivo/features/agent/orchestration/subagent_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #43: regression against merged session contract only.
/// Draft PR #24 was examined for scope but its code is not imported.
/// No Android process termination or real side-effect recovery is executed.
void main() {
  final start = DateTime.utc(2026, 11, 21);
  SubagentSession fresh(String id) => SubagentSession(
    sessionId: 'session:$id',
    ownerId: 'owner:test',
    taskId: 'task:$id',
    contextRef: 'context:$id',
    createdAt: start,
    updatedAt: start,
  );

  test('running session becomes interrupted and cannot resume implicitly', () {
    final running = fresh(
      'work',
    ).transition(SubagentSessionState.running, at: start);
    final persisted = SubagentSession.fromJson(running.toJson());
    final interrupted = persisted.interruptedAfterRestart(
      start.add(const Duration(seconds: 1)),
    );
    expect(interrupted.state, SubagentSessionState.interrupted);
    expect(interrupted.isTerminal, isFalse);
    expect(
      interrupted.interruptedAfterRestart(
        start.add(const Duration(seconds: 2)),
      ),
      same(interrupted),
    );
    expect(
      () => interrupted.transition(
        SubagentSessionState.completed,
        at: start.add(const Duration(seconds: 3)),
      ),
      throwsStateError,
    );
  });

  test('unknown side effect cannot replay without explicit reconciliation', () {
    final running = fresh(
      'write',
    ).transition(SubagentSessionState.running, at: start);
    final unknown = running.transition(
      SubagentSessionState.outcomeUnknown,
      at: start.add(const Duration(seconds: 1)),
    );
    final restored = SubagentSession.fromJson(unknown.toJson());
    expect(
      () => restored.transition(
        SubagentSessionState.completed,
        at: start.add(const Duration(seconds: 2)),
      ),
      throwsStateError,
    );
    expect(
      () => restored.transition(
        SubagentSessionState.queued,
        at: start.add(const Duration(seconds: 2)),
      ),
      throwsStateError,
    );
    final reviewed = restored.transition(
      SubagentSessionState.failed,
      at: start.add(const Duration(seconds: 2)),
      reviewedUnknownOutcome: true,
    );
    expect(reviewed.isTerminal, isTrue);
  });

  test('terminal and cross-owner records never acquire new execution', () {
    final done = fresh('done')
        .transition(SubagentSessionState.running, at: start)
        .transition(SubagentSessionState.completed, at: start);
    expect(
      () => done.transition(SubagentSessionState.running, at: start),
      throwsStateError,
    );
    final parent = fresh('parent');
    final catalog = SubagentSessionCatalog()..register(parent);
    final intruder = SubagentSession(
      sessionId: 'session:foreign',
      ownerId: 'owner:foreign',
      parentSessionId: parent.sessionId,
      taskId: 'task:foreign',
      contextRef: 'context:foreign',
      createdAt: start,
      updatedAt: start,
    );
    expect(() => catalog.register(intruder), throwsStateError);
  });

  test('recovered records contain opaque handles, not command payloads', () {
    final encoded = fresh('safe').toJson();
    expect(encoded.keys, isNot(contains('command')));
    expect(encoded.keys, isNot(contains('token')));
    expect(
      () => SubagentSession.fromJson({...encoded, 'command': 'shell'}),
      throwsFormatException,
    );
    expect(
      () => SubagentSession.fromJson({...encoded, 'state': 'executing'}),
      throwsFormatException,
    );
  });
}
