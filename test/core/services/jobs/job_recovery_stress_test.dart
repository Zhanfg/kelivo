import 'dart:math';

import 'package:Kelivo/core/services/jobs/job_executor.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026);

JobRecord _job(String id) => JobRecord(
  jobId: 'job_${id.padLeft(8, '0')}',
  kind: 'download',
  ownerId: 'owner:test',
  state: JobState.queued,
  createdAt: _time,
  updatedAt: _time,
  idempotencyKey: 'idem:$id',
);

void main() {
  group('W07 recovery contract', () {
    test('interrupted work can be requeued explicitly', () {
      final first = _job('1');
      final running = first.transition(JobState.running, at: _time);
      final stopped = running.transition(JobState.interrupted, at: _time);
      expect(stopped.isTerminal, isFalse);
      final queued = stopped.transition(JobState.queued, at: _time);
      expect(queued.state, JobState.queued);
      expect(
        () => stopped.transition(JobState.completed, at: _time),
        throwsStateError,
      );
    });

    test('unknown side effects require review', () {
      final first = _job('2');
      final running = first.transition(JobState.running, at: _time);
      final unknown = running.transition(JobState.outcomeUnknown, at: _time);
      expect(unknown.isTerminal, isFalse);
      expect(
        () => unknown.transition(JobState.queued, at: _time),
        throwsStateError,
      );
      expect(
        () => unknown.transition(JobState.completed, at: _time),
        throwsStateError,
      );
      final reviewed = unknown.transition(
        JobState.completed,
        at: _time,
        outcomeReviewed: true,
      );
      expect(reviewed.state, JobState.completed);
    });

    test('timestamps are monotonic', () {
      final later = _time.add(const Duration(seconds: 2));
      final earlier = _time.add(const Duration(seconds: 1));
      final running = _job('3').transition(JobState.running, at: later);
      expect(
        () => running.transition(JobState.failed, at: earlier),
        throwsArgumentError,
      );
    });

    test('terminal jobs reject new transitions', () {
      final running = _job('4').transition(JobState.running, at: _time);
      final done = running.transition(JobState.completed, at: _time);
      expect(
        () => done.transition(JobState.queued, at: _time),
        throwsStateError,
      );
    });
  });

  group('W07 fake executor invariants', () {
    test('duplicate submit cannot create duplicate work', () async {
      final runner = FakeJobExecutor(clock: () => _time);
      final record = _job('5');
      await runner.submit(record);
      await expectLater(runner.submit(record), throwsStateError);
      expect(runner.list(), hasLength(1));
      expect(runner.runNext()?.jobId, record.jobId);
      expect(runner.runNext(), isNull);
    });

    test('cancel is idempotent and blocks finish', () async {
      final runner = FakeJobExecutor(clock: () => _time);
      final record = _job('6');
      await runner.submit(record);
      final cancelled = await runner.cancel(record.jobId);
      expect(await runner.cancel(record.jobId), same(cancelled));
      expect(runner.runNext(), isNull);
      expect(
        () => runner.finish(record.jobId, succeeded: true),
        throwsStateError,
      );
    });

    test('cancel before or after start blocks completion', () async {
      for (final before in [true, false]) {
        final runner = FakeJobExecutor(clock: () => _time);
        final record = _job(before ? '7' : '8');
        await runner.submit(record);
        if (before) {
          await runner.cancel(record.jobId);
          expect(runner.runNext(), isNull);
        } else {
          expect(runner.runNext()?.state, JobState.running);
          await runner.cancel(record.jobId);
        }
        expect(runner.status(record.jobId)?.state, JobState.cancelled);
        expect(
          () => runner.finish(record.jobId, succeeded: true),
          throwsStateError,
        );
      }
    });

    test('seeded interleavings preserve terminal outcomes', () async {
      final random = Random(109);
      final runner = FakeJobExecutor(clock: () => _time);
      final ids = <String>[];
      for (var i = 0; i < 80; i++) {
        final record = _job('stress$i');
        ids.add(record.jobId);
        await runner.submit(record);
      }
      final cancelled = <String>{};
      for (final id in ids) {
        if (random.nextBool()) {
          cancelled.add(id);
          await runner.cancel(id);
        }
      }
      final executed = <String>{};
      while (true) {
        final current = runner.runNext();
        if (current == null) break;
        expect(executed.add(current.jobId), isTrue);
        runner.finish(current.jobId, succeeded: random.nextBool());
      }
      expect(executed.intersection(cancelled), isEmpty);
      expect(executed.length + cancelled.length, ids.length);
      for (final id in ids) {
        expect(runner.status(id)?.isTerminal, isTrue);
        expect(() => runner.finish(id, succeeded: true), throwsStateError);
      }
      expect(runner.runNext(), isNull);
    });
  });
}
