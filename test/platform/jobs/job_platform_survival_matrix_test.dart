import 'package:Kelivo/core/services/jobs/job_record.dart';
import 'package:flutter_test/flutter_test.dart';

/// #38 static platform lifecycle contracts, not actual OS survival results.
enum PlatformJobEvent { background, suspended, processKilled, userReopened }

enum PlatformResumeDecision { keepRunning, reconcile, notGuaranteed }

PlatformResumeDecision expectedDecision(
  String platform,
  PlatformJobEvent event,
) {
  if (!{'android', 'ios', 'desktop'}.contains(platform)) {
    throw ArgumentError('Unknown platform');
  }
  if (event == PlatformJobEvent.processKilled ||
      event == PlatformJobEvent.userReopened) {
    return PlatformResumeDecision.reconcile;
  }
  if (platform == 'ios') return PlatformResumeDecision.notGuaranteed;
  return PlatformResumeDecision.notGuaranteed;
}

void main() {
  test('no platform promises unlimited background execution', () {
    for (final platform in ['android', 'ios', 'desktop']) {
      expect(
        expectedDecision(platform, PlatformJobEvent.background),
        PlatformResumeDecision.notGuaranteed,
      );
      expect(
        expectedDecision(platform, PlatformJobEvent.suspended),
        PlatformResumeDecision.notGuaranteed,
      );
    }
  });

  test('restarted processes require persisted-state reconciliation', () {
    for (final platform in ['android', 'ios', 'desktop']) {
      expect(
        expectedDecision(platform, PlatformJobEvent.processKilled),
        PlatformResumeDecision.reconcile,
      );
      expect(
        expectedDecision(platform, PlatformJobEvent.userReopened),
        PlatformResumeDecision.reconcile,
      );
    }
  });

  test('unknown-outcome JobRecord never automatically retries', () {
    final now = DateTime.utc(2026, 11, 21);
    final job = JobRecord(
      jobId: 'job_platform_0001',
      kind: 'process',
      ownerId: 'owner:one',
      state: JobState.outcomeUnknown,
      createdAt: now,
      updatedAt: now,
    );
    expect(() => job.transition(JobState.completed, at: now), throwsStateError);
    expect(job.isTerminal, isFalse);
  });

  test('device survival evidence is still missing on all platforms', () {
    // Real Android background reclaim, iOS suspension and desktop service
    // restarts require independent platform acceptance, not this matrix.
    expect(
      () => expectedDecision('unknown', PlatformJobEvent.background),
      throwsArgumentError,
    );
  });
}
