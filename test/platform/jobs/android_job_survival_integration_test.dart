import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';

/// Opt-in Android Job survival evidence validator.
/// No test on CI starts/kills a process, overrides battery restrictions,
/// force-stops an app or changes OS settings.
/// A device operator must produce real before/after sanitized receipts.
final bool _deviceTest = Platform.environment['KELIVO_JOB_DEVICE_TEST'] == '1';

void main() {
  final observed = DateTime.utc(2026, 11, 21);
  JobRecord fixture(JobState state) => JobRecord(
    jobId: 'job_android_recovery_2026',
    kind: 'http_download',
    ownerId: 'workspace:device',
    state: state,
    createdAt: observed,
    updatedAt: observed,
    maxAttempts: 3,
    idempotencyKey: 'job-recovery-check',
  );

  test(
    'interrupted job survives serialization but cannot claim completion',
    () {
      final job = JobRecord.fromJson(fixture(JobState.interrupted).toJson());
      expect(job.state, JobState.interrupted);
      expect(job.isTerminal, isFalse);
      expect(job.resultRef, isNull);
    },
  );

  test(
    'unknown side effect cannot automatically transition back to running',
    () {
      final unknown = fixture(JobState.outcomeUnknown);
      expect(
        () => unknown.transition(
          JobState.running,
          at: observed.add(const Duration(seconds: 1)),
        ),
        throwsStateError,
      );
      expect(
        () => unknown.transition(
          JobState.completed,
          at: observed.add(const Duration(seconds: 1)),
        ),
        throwsStateError,
      );
      final reviewed = unknown.transition(
        JobState.failed,
        at: observed.add(const Duration(seconds: 1)),
        outcomeReviewed: true,
      );
      expect(reviewed.isTerminal, isTrue);
    },
  );

  test('opt-in real Android before/after recovery evidence', () async {
    final serial = Platform.environment['ANDROID_SERIAL'];
    final before = Platform.environment['KELIVO_JOB_BEFORE_JSON'];
    final after = Platform.environment['KELIVO_JOB_AFTER_JSON'];
    final scenario = Platform.environment['KELIVO_JOB_SCENARIO'];
    if (serial == null ||
        serial.isEmpty ||
        before == null ||
        after == null ||
        scenario == null ||
        !{
          'process-death',
          'doze',
          'reboot',
          'background-restriction',
          'force-stop-manual-relaunch',
        }.contains(scenario)) {
      throw StateError(
        'Specify explicit device, scenario, before/after receipts',
      );
    }
    final sdk = await Process.run('adb', [
      '-s',
      serial,
      'shell',
      'getprop',
      'ro.build.version.sdk',
    ]).timeout(const Duration(seconds: 20));
    if (sdk.exitCode != 0) throw StateError('Android SDK probe failed');
    expect(
      int.tryParse(sdk.stdout.toString().trim()),
      greaterThanOrEqualTo(24),
    );
    Future<JobRecord> readSanitized(String path) async {
      final f = File(path);
      if (!await f.exists() || await f.length() > 65536) {
        throw StateError('Missing or oversized sanitized job receipt');
      }
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid JobRecord evidence');
      }
      return JobRecord.fromJson(raw);
    }

    final first = await readSanitized(before);
    final last = await readSanitized(after);
    expect(last.jobId, first.jobId);
    expect(last.ownerId, first.ownerId);
    expect(last.updatedAt.isBefore(first.updatedAt), isFalse);
    expect(
      last.state,
      isNot(JobState.running),
      reason: 'Without validated idempotent replay, no automatic running claim',
    );
    expect(
      last.state,
      isNot(JobState.queued),
      reason: 'Device operator must reconcile interruption before rerun',
    );
    // Device logs, actual lifecycle trigger, output integrity and delay must
    // be reviewed separately; receipts alone do not prove Android survival.
  }, skip: !_deviceTest ? 'NOT TESTED: Android device evidence absent' : false);
}
