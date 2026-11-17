import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/jobs/job_record.dart';

void main() {
  final first = DateTime.utc(2026, 11, 17, 12, 0);
  final second = DateTime.utc(2026, 11, 17, 12, 1);

  JobRecord sample({
    JobState state = JobState.queued,
    List<String> artifactIds = const [],
  }) => JobRecord(
    jobId: 'job_abcdefgh',
    kind: 'http_download',
    ownerId: 'conversation:abc',
    state: state,
    createdAt: first,
    updatedAt: first,
    attempt: 0,
    maxAttempts: 3,
    idempotencyKey: 'idem-task-123',
    artifactIds: artifactIds,
  );

  group('JobState wire contract', () {
    test('every state has a unique round-trippable wire name', () {
      final names = JobState.values.map((s) => s.wireName).toList();
      expect(names.toSet().length, names.length);
      for (final state in JobState.values) {
        expect(JobState.parse(state.wireName), state);
      }
      expect(JobState.parse('outcome_unknown'), JobState.outcomeUnknown);
      expect(() => JobState.parse('success'), throwsFormatException);
    });

    test('only known terminal states are terminal', () {
      expect(JobState.completed.isTerminal, isTrue);
      expect(JobState.failed.isTerminal, isTrue);
      expect(JobState.cancelled.isTerminal, isTrue);
      expect(JobState.outcomeUnknown.isTerminal, isFalse);
      expect(JobState.interrupted.isTerminal, isFalse);
    });
  });

  group('JobRecord serialization', () {
    test('roundtrip retains handles, timestamps, attempts and state', () {
      final source = sample(artifactIds: ['artifact:12345678']);
      final decoded = JobRecord.fromJson(source.toJson());
      expect(decoded.jobId, source.jobId);
      expect(decoded.kind, 'http_download');
      expect(decoded.ownerId, source.ownerId);
      expect(decoded.state, JobState.queued);
      expect(decoded.createdAt, first);
      expect(decoded.updatedAt, first);
      expect(decoded.maxAttempts, 3);
      expect(decoded.idempotencyKey, 'idem-task-123');
      expect(decoded.artifactIds, ['artifact:12345678']);
      expect(decoded.toJson(), source.toJson());
      expect(decoded.toJson()['schema_version'], 1);
      expect(decoded.toJson()['created_at'], endsWith('Z'));
    });

    test('does not serialize raw command input or credentials', () {
      final json = sample().toJson();
      expect(json.containsKey('command'), isFalse);
      expect(json.containsKey('api_key'), isFalse);
      expect(json.containsKey('local_path'), isFalse);
      expect(json.containsKey('payload'), isFalse);
    });

    test('list property is detached and immutable', () {
      final mutable = ['artifact:00000001'];
      final record = sample(artifactIds: mutable);
      mutable.add('artifact:00000002');
      expect(record.artifactIds, ['artifact:00000001']);
      expect(
        () => record.artifactIds.add('artifact:00000003'),
        throwsUnsupportedError,
      );
    });

    test('rejects unknown versions, states, timestamp zones and types', () {
      final data = sample().toJson();
      for (final mutation in <Map<String, Object?>>[
        {...data, 'schema_version': 2},
        {...data, 'state': 'unknown'},
        {...data, 'created_at': '2026-11-17T12:00:00+08:00'},
        {
          ...data,
          'artifact_ids': ['good', 42],
        },
        {...data, 'attempt': '1'},
      ]) {
        expect(() => JobRecord.fromJson(mutation), throwsFormatException);
      }
    });

    test('rejects malformed IDs, duplicate artifacts, time order', () {
      expect(
        () => JobRecord(
          jobId: '../outside',
          kind: 'script',
          ownerId: 'conversation:abc',
          state: JobState.queued,
          createdAt: first,
          updatedAt: first,
        ),
        throwsArgumentError,
      );
      expect(
        () => sample(artifactIds: ['artifact:1', 'artifact:1']),
        throwsArgumentError,
      );
      expect(
        () => JobRecord(
          jobId: 'job_abcdefgh',
          kind: 'script',
          ownerId: 'conversation:abc',
          state: JobState.queued,
          createdAt: second,
          updatedAt: first,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid attempt budgets', () {
      expect(
        () => JobRecord(
          jobId: 'job_abcdefgh',
          kind: 'script',
          ownerId: 'conversation:abc',
          state: JobState.queued,
          createdAt: first,
          updatedAt: first,
          attempt: 4,
          maxAttempts: 3,
        ),
        throwsArgumentError,
      );
    });
  });

  group('JobRecord state transitions', () {
    test('queued -> running -> completed keeps identity', () {
      final running = sample().transition(JobState.running, at: second);
      expect(running.state, JobState.running);
      expect(running.jobId, 'job_abcdefgh');
      final completed = running.transition(
        JobState.completed,
        at: second.add(const Duration(seconds: 1)),
        newResultRef: 'result:abc',
      );
      expect(completed.state, JobState.completed);
      expect(completed.isTerminal, isTrue);
      expect(completed.resultRef, 'result:abc');
      expect(
        () => completed.transition(JobState.queued, at: second),
        throwsStateError,
      );
    });

    test('paused and interrupted may be requeued explicitly', () {
      final running = sample().transition(JobState.running, at: second);
      final paused = running.transition(
        JobState.paused,
        at: second.add(const Duration(seconds: 1)),
      );
      expect(
        paused
            .transition(
              JobState.queued,
              at: second.add(const Duration(seconds: 2)),
            )
            .state,
        JobState.queued,
      );
      final interrupted = running.transition(
        JobState.interrupted,
        at: second.add(const Duration(seconds: 1)),
      );
      expect(
        interrupted
            .transition(
              JobState.queued,
              at: second.add(const Duration(seconds: 2)),
            )
            .state,
        JobState.queued,
      );
    });

    test('unknown outcome cannot be requeued or silently resolved', () {
      final running = sample().transition(JobState.running, at: second);
      final unknown = running.transition(
        JobState.outcomeUnknown,
        at: second.add(const Duration(seconds: 1)),
      );
      expect(
        () => unknown.transition(
          JobState.queued,
          at: second.add(const Duration(seconds: 2)),
          outcomeReviewed: true,
        ),
        throwsStateError,
      );
      expect(
        () => unknown.transition(
          JobState.completed,
          at: second.add(const Duration(seconds: 2)),
        ),
        throwsStateError,
      );
      final resolved = unknown.transition(
        JobState.failed,
        at: second.add(const Duration(seconds: 2)),
        outcomeReviewed: true,
        newErrorCode: 'remote:unknown',
      );
      expect(resolved.errorCode, 'remote:unknown');
      expect(resolved.isTerminal, isTrue);
    });

    test('time cannot move backwards', () {
      final running = sample().transition(JobState.running, at: second);
      expect(
        () => running.transition(JobState.completed, at: first),
        throwsArgumentError,
      );
    });
  });
}
