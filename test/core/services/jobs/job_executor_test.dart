import 'package:Kelivo/core/services/jobs/job_executor.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';
import 'package:flutter_test/flutter_test.dart';

JobRecord job(String id, {String owner = 'alice'}) => JobRecord(
  jobId: id,
  kind: 'download',
  ownerId: owner,
  state: JobState.queued,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('submit, status, list, run and completion', () async {
    final queue = FakeJobExecutor(clock: () => DateTime.utc(2026, 1, 2));
    await queue.submit(job('job_abcdefgh'));
    await queue.submit(job('job_ijklmnop', owner: 'bob'));
    expect(queue.list(ownerId: 'alice'), hasLength(1));
    expect(queue.runNext()!.state, JobState.running);
    expect(
      queue.finish('job_abcdefgh', succeeded: true).state,
      JobState.completed,
    );
    expect(queue.runNext()!.jobId, 'job_ijklmnop');
    expect(queue.runNext(), isNull);
  });

  test(
    'cancel prevents execution and is idempotent for terminal job',
    () async {
      final queue = FakeJobExecutor();
      await queue.submit(job('job_abcdefgh'));
      final cancelled = await queue.cancel('job_abcdefgh');
      expect(cancelled.state, JobState.cancelled);
      expect(await queue.cancel('job_abcdefgh'), same(cancelled));
      expect(queue.runNext(), isNull);
      expect(
        () => queue.finish('job_abcdefgh', succeeded: true),
        throwsStateError,
      );
    },
  );

  test('duplicate id and nonqueued submissions rejected', () async {
    final queue = FakeJobExecutor();
    final value = job('job_abcdefgh');
    await queue.submit(value);
    await expectLater(queue.submit(value), throwsStateError);
    final running = value.transition(JobState.running, at: DateTime.utc(2026));
    await expectLater(queue.submit(running), throwsStateError);
    await expectLater(queue.cancel('job_unknown'), throwsStateError);
  });
}
