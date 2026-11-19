import 'dart:math';

import 'package:Kelivo/core/services/jobs/job_executor.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _epoch = DateTime.utc(2026, 11, 19);

JobRecord _queued(String id) => JobRecord(
  jobId: 'job_${id.padLeft(8, '0')}',
  kind: 'download',
  ownerId: 'owner:test',
  state: JobState.queued,
  createdAt: _epoch,
  updatedAt: _epoch,
  idempotencyKey: 'idem:$id',
);

void main() {
  group('W07: Job transition and crash-state contract', () {
    test('running to interrupted is explicit and not terminal', () {
      final running = _queued('1').transition(JobState.running, at: _epoch);
      final interrupted = running.transition(
        JobState.interrupted,
        at: _epoch.add(const Duration(seconds: 1)),
      );
      expect(interrupted.isTerminal, isFalse);
      expect(interrupted.state, JobState.interrupted);
      final resumed = interrupted.transition(
        JobState.queued,
        at: _epoch.add(const Duration(seconds: 2)),
      );
      expect(resumed.state, JobState.queued);
      expect(
        () => interrupted.transition(
          JobState.completed,
          at: _epoch.add(const Duration(seconds: 2)),
        ),
        throwsStateError,
      );
    });

    test('unknown outcomes cannot auto-retry or resolve unreviewed', () {
      final unknown = _queued('2')
          .transition(JobState.running, at: _epoch)
          .transition(JobState.outcomeUnknown, at: _epoch);
      expect(unknown.isTerminal, isFalse);
      expect(
        () => unknown.transition(JobState.queued, at: _epoch),
        throwsStateError,
      );
      expect(
        () => unknown.transition(JobState.completed, at: _epoch),
        throwsStateError,
      );
      final reviewed = unknown.transition(
        JobState.completed,
        at: _epoch,
        outcomeReviewed: true,
      );
      expect(reviewed.state, JobState.completed);
    });

    test('state transition timestamps never move backwards', () {
      final running = _queued('3').transition(
        JobState.running,
        at: _epoch.add(const Duration(seconds: 2)),
      );
      expect(
        () => running.transition(
          JobState.failed,
          at: _epoch.add(const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
    });

    test('terminal states cannot transition again', () {
      final completed = _queued('4')
          .transition(JobState.running, at: _epoch)
          .transition(JobState.completed, at: _epoch);
      expect(
        () => completed.transition(JobState.queued, at: _epoch),
        throwsStateError,
      );
      expect(
        () => completed.transition(JobState.failed, at: _epoch),
        throwsStateError,
      );
    });
  });

  group('W07: deterministic fake scheduler stress and cancellation', () {
    test('duplicate submission is rejected without duplicate work', () async {
      final executor = FakeJobExecutor(clock: () => _epoch);
      final job = _queued('5');
      await executor.submit(job);
      await expectLater(executor.submit(job), throwsStateError);
      expect(executor.list(), hasLength(1));
      expect(executor.runNext()?.jobId, job.jobId);
      expect(executor.runNext(), isNull);
    });

    test('repeated cancellation is idempotent', () async {
      final executor = FakeJobExecutor(clock: () => _epoch);
      final job = _queued('6');
      await executor.submit(job);
      final cancelled = await executor.cancel(job.jobId);
      expect(await executor.cancel(job.jobId), same(cancelled));
      expect(executor.runNext(), isNull);
      expect(
        () => executor.finish(job.jobId, succeeded: true),
        throwsStateError,
      );
    });

    test('cancel/run interleavings have deterministic outcomes', () async {
      for (final cancelBeforeRun in [true, false]) {
        final executor = FakeJobExecutor(clock: () => _epoch);
        final job = _queued(cancelBeforeRun ? '7' : '8');
        await executor.submit(job);
        if (cancelBeforeRun) {
          await executor.cancel(job.jobId);
          expect(executor.runNext(), isNull);
        } else {
          expect(executor.runNext()?.state, JobState.running);
          await executor.cancel(job.jobId);
        }
        expect(executor.status(job.jobId)?.state, JobState.cancelled);
        expect(
        () => executor.finish(job.jobId, succeeded: true),
        throwsStateError,
      );
      }
    });

    test('seeded interleavings preserve terminal states', () async {
      final random = Random(109);
      final executor = FakeJobExecutor(clock: () => _epoch);
      final ids = <String>[];
      for (var i = 0; i < 80; i++) {
        final job = _queued('stress$i');
        ids.add(job.jobId);
        await executor.submit(job);
      }
      final cancelled = <String>{};
      for (final id in ids) {
        if (random.nextBool()) {
          cancelled.add(id);
          await executor.cancel(id);
        }
      }
      final executed = <String>{};
      while (true) {
        final current = executor.runNext();
        if (current == null) break;
        expect(executed.add(current.jobId), isTrue);
        executor.finish(current.jobId, succeeded: random.nextBool());
      }
      expect(executed.intersection(cancelled), isEmpty);
      expect(executed.length + cancelled.length, ids.length);
      for (final id in ids) {
        expect(executor.status(id)?.isTerminal, isTrue);
        expect(
          () => executor.finish(id, succeeded: true),
          throwsStateError,
        );
      }
      expect(executor.runNext(), isNull);
    });
  });
}
