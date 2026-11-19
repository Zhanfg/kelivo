import 'dart:async';

import 'package:Kelivo/features/agent/orchestration/subagent_dispatcher.dart';
import 'package:Kelivo/features/agent/orchestration/subagent_session.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeRunner implements SubagentTaskRunner {
  final Map<String, Completer<String?>> pending = {};
  final List<String> cancellations = [];
  @override
  Future<String?> execute(SubagentSession session) {
    final completer = Completer<String?>();
    pending[session.sessionId] = completer;
    return completer.future;
  }

  @override
  Future<void> cancel(String sessionId) async {
    cancellations.add(sessionId);
  }

  void finish(String sessionId, [String? ref]) {
    pending[sessionId]!.complete(ref);
  }
}

SubagentSession _session(String name) {
  final at = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
  return SubagentSession(
    sessionId: 'session:$name',
    ownerId: 'owner:test',
    taskId: 'task:$name',
    contextRef: 'context:$name',
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  late FakeRunner runner;
  late SubagentDispatcher dispatcher;
  setUp(() {
    runner = FakeRunner();
    dispatcher = SubagentDispatcher(runner: runner, maxConcurrent: 2);
  });

  test('spawn returns quickly, collect obtains explicit result', () async {
    final receipt = dispatcher.spawn(_session('a'));
    expect(receipt.session.state, SubagentSessionState.running);
    expect(dispatcher.runningCount, 1);
    runner.finish('session:a', 'artifact:result');
    final result = await dispatcher.collect('session:a');
    expect(result.state, SubagentSessionState.completed);
    expect(result.resultRef, 'artifact:result');
    expect(dispatcher.runningCount, 0);
  });

  test(
    'bounded concurrency rejects third launch without side effect',
    () async {
      dispatcher.spawn(_session('a'));
      dispatcher.spawn(_session('b'));
      expect(() => dispatcher.spawn(_session('c')), throwsStateError);
      expect(runner.pending, hasLength(2));
      runner.finish('session:a');
      await dispatcher.collect('session:a');
      dispatcher.spawn(_session('c'));
      runner.finish('session:b');
      runner.finish('session:c');
      await dispatcher.collect('session:b');
      await dispatcher.collect('session:c');
    },
  );

  test('cancel request never reports an unverified terminal success', () async {
    dispatcher.spawn(_session('a'));
    await dispatcher.requestCancel('session:a');
    runner.finish('session:a', 'artifact:unknown');
    final result = await dispatcher.collect('session:a');
    expect(result.state, SubagentSessionState.outcomeUnknown);
    expect(runner.cancellations, ['session:a']);
    expect(
      () => result.transition(
        SubagentSessionState.completed,
        at: DateTime.now().toUtc(),
      ),
      throwsStateError,
    );
  });

  test('duplicate session identities are rejected', () async {
    dispatcher.spawn(_session('a'));
    expect(() => dispatcher.spawn(_session('a')), throwsStateError);
    runner.finish('session:a');
    await dispatcher.collect('session:a');
    expect(() => dispatcher.spawn(_session('a')), throwsStateError);
  });

  test('failed Agent executes without automatic replay', () async {
    dispatcher.spawn(_session('a'));
    runner.pending['session:a']!.completeError(StateError('backend'));
    final result = await dispatcher.collect('session:a');
    expect(result.state, SubagentSessionState.failed);
    expect(runner.pending, hasLength(1));
  });

  test('unknown collect and invalid queue admission are rejected', () {
    expect(() => dispatcher.collect('session:missing'), throwsStateError);
    final running = _session(
      'other',
    ).transition(SubagentSessionState.running, at: DateTime.now().toUtc());
    expect(() => dispatcher.spawn(running), throwsStateError);
  });

  test('cancellation request is idempotent', () async {
    dispatcher.spawn(_session('a'));
    await dispatcher.requestCancel('session:a');
    await dispatcher.requestCancel('session:a');
    expect(runner.cancellations, hasLength(1));
    runner.finish('session:a');
    await dispatcher.collect('session:a');
  });
}
