import 'dart:async';

import 'subagent_session.dart';

/// An external Agent runner must enforce capability authorization before
/// accepting a task. The dispatcher does not execute prompts or host tools.
abstract interface class SubagentTaskRunner {
  Future<String?> execute(SubagentSession session);
  Future<void> cancel(String sessionId);
}

final class SubagentTaskHandle {
  SubagentTaskHandle(this.session, this.finished);
  final SubagentSession session;
  final Future<SubagentSession> finished;
}

/// Bounded, explicit sub-Agent adapter. No auto-retry of unknown side effects.
final class SubagentDispatcher {
  SubagentDispatcher({required this.runner, this.maxConcurrent = 2}) {
    if (maxConcurrent < 1 || maxConcurrent > 16) {
      throw ArgumentError('Invalid concurrent Agent budget');
    }
  }

  final SubagentTaskRunner runner;
  final int maxConcurrent;
  final Map<String, SubagentSession> _records = {};
  final Map<String, Completer<SubagentSession>> _outcomes = {};
  final Set<String> _running = {};
  final Set<String> _cancelRequested = {};

  int get runningCount => _running.length;
  SubagentSession? lookup(String id) => _records[id];

  /// No unbounded queue: callers must retry admission later.
  SubagentTaskHandle spawn(SubagentSession session) {
    if (_running.length >= maxConcurrent) {
      throw StateError('Sub-Agent concurrency budget exhausted');
    }
    if (_records.containsKey(session.sessionId) ||
        session.state != SubagentSessionState.queued) {
      throw StateError('Duplicate or invalid sub-Agent launch');
    }
    final active = session.transition(
      SubagentSessionState.running,
      at: DateTime.now().toUtc(),
    );
    final completer = Completer<SubagentSession>();
    _records[active.sessionId] = active;
    _outcomes[active.sessionId] = completer;
    _running.add(active.sessionId);
    unawaited(_drive(active, completer));
    return SubagentTaskHandle(active, completer.future);
  }

  Future<void> _drive(
    SubagentSession active,
    Completer<SubagentSession> completer,
  ) async {
    try {
      final reference = await runner.execute(active);
      final current = _records[active.sessionId]!;
      if (_cancelRequested.contains(active.sessionId)) {
        // A remote cancellation acknowledgement cannot guarantee that the
        // side effect did not occur: mark unknown, never restart automatically.
        _finish(current, SubagentSessionState.outcomeUnknown, completer);
      } else {
        final finished = current.transition(
          SubagentSessionState.completed,
          at: DateTime.now().toUtc(),
          newResultRef: reference,
        );
        _records[active.sessionId] = finished;
        completer.complete(finished);
      }
    } catch (_) {
      final current = _records[active.sessionId]!;
      _finish(
        current,
        _cancelRequested.contains(active.sessionId)
            ? SubagentSessionState.outcomeUnknown
            : SubagentSessionState.failed,
        completer,
      );
    } finally {
      _running.remove(active.sessionId);
    }
  }

  void _finish(
    SubagentSession current,
    SubagentSessionState state,
    Completer<SubagentSession> completer,
  ) {
    final next = current.transition(state, at: DateTime.now().toUtc());
    _records[current.sessionId] = next;
    if (!completer.isCompleted) completer.complete(next);
  }

  /// Attempts cooperative cancellation. Never declares success from request
  /// alone; the execution outcome is resolved by collect().
  Future<void> requestCancel(String id) async {
    if (!_running.contains(id)) {
      throw StateError('No running sub-Agent with that identity');
    }
    if (!_cancelRequested.add(id)) return;
    try {
      await runner.cancel(id);
    } catch (_) {
      // Keep unknown-outcome status when an executing task eventually settles.
    }
  }

  Future<SubagentSession> collect(String id) {
    final outcome = _outcomes[id];
    if (outcome == null) throw StateError('Unknown sub-Agent result handle');
    return outcome.future;
  }
}
