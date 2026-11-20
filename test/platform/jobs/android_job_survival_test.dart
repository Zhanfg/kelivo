import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';

/// Simulated Android lifecycle fixtures, not physical Android system tests.
/// Actual process death, Doze and OEM battery policies must be tested on device.
void main() {
  final time = DateTime.utc(2026, 11, 21);
  JobRecord job() => JobRecord(
    jobId: 'job_android_lifecycle_01',
    kind: 'http_download',
    ownerId: 'workspace:one',
    state: JobState.running,
    createdAt: time,
    updatedAt: time,
    maxAttempts: 3,
    idempotencyKey: 'android-restart-1',
  );

  test('process death transitions running to interrupted', () {
    final interrupted = job().transition(
      JobState.interrupted,
      at: time.add(const Duration(seconds: 1)),
    );
    expect(interrupted.state, JobState.interrupted);
    expect(
      JobRecord.fromJson(interrupted.toJson()).state,
      JobState.interrupted,
    );
  });

  test('unknown side effects cannot be automatically replayed', () {
    final unknown = job().transition(
      JobState.outcomeUnknown,
      at: time.add(const Duration(seconds: 1)),
    );
    expect(
      () => unknown.transition(
        JobState.completed,
        at: time.add(const Duration(seconds: 2)),
      ),
      throwsStateError,
    );
    expect(
      () => unknown.transition(
        JobState.running,
        at: time.add(const Duration(seconds: 2)),
      ),
      throwsStateError,
    );
  });

  test('explicit review allows eventual resolution only', () {
    final unknown = job().transition(
      JobState.outcomeUnknown,
      at: time.add(const Duration(seconds: 1)),
    );
    final resolved = unknown.transition(
      JobState.failed,
      at: time.add(const Duration(seconds: 2)),
      outcomeReviewed: true,
    );
    expect(resolved.isTerminal, isTrue);
    expect(
      () => resolved.transition(
        JobState.running,
        at: time.add(const Duration(seconds: 3)),
      ),
      throwsStateError,
    );
  });

  test('paused work cannot jump directly to completed after restore', () {
    final paused = job().transition(
      JobState.paused,
      at: time.add(const Duration(seconds: 1)),
    );
    expect(
      () => paused.transition(
        JobState.completed,
        at: time.add(const Duration(seconds: 2)),
      ),
      throwsStateError,
    );
    expect(
      paused
          .transition(JobState.queued, at: time.add(const Duration(seconds: 2)))
          .state,
      JobState.queued,
    );
  });

  test('cancellation is terminal even after simulated restart', () {
    final cancelled = job().transition(
      JobState.cancelled,
      at: time.add(const Duration(seconds: 1)),
    );
    final restored = JobRecord.fromJson(cancelled.toJson());
    expect(restored.isTerminal, isTrue);
    expect(
      () => restored.transition(
        JobState.running,
        at: time.add(const Duration(seconds: 2)),
      ),
      throwsStateError,
    );
  });
}
