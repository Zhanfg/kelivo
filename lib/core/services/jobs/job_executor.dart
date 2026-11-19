// In-memory fake job executor: no persistence, shell, or network side effects.
// A production scheduler must implement durable state and authorization.
import 'dart:async';
import 'job_record.dart';

abstract interface class JobExecutor {
  Future<JobRecord> submit(JobRecord record);
  JobRecord? status(String jobId);
  List<JobRecord> list({String? ownerId});
  Future<JobRecord> cancel(String jobId);
}

/// Deterministic scheduler for API tests and integration prototypes.
/// [runNext] is explicit, so the fake never starts work in the background.
final class FakeJobExecutor implements JobExecutor {
  FakeJobExecutor({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final Map<String, JobRecord> _jobs = {};
  final List<String> _queue = [];

  @override
  Future<JobRecord> submit(JobRecord record) async {
    if (record.state != JobState.queued) {
      throw StateError('Only queued jobs can be submitted');
    }
    if (_jobs.containsKey(record.jobId)) {
      throw StateError('Duplicate job id');
    }
    _jobs[record.jobId] = record;
    _queue.add(record.jobId);
    return record;
  }

  @override
  JobRecord? status(String jobId) => _jobs[jobId];

  @override
  List<JobRecord> list({String? ownerId}) => List.unmodifiable(
    _jobs.values.where((job) => ownerId == null || job.ownerId == ownerId),
  );

  @override
  Future<JobRecord> cancel(String jobId) async {
    final current = _jobs[jobId];
    if (current == null) throw StateError('Unknown job');
    if (current.isTerminal) return current;
    if (current.state == JobState.outcomeUnknown) {
      throw StateError('Cannot cancel unknown side effect without review');
    }
    final next = current.transition(JobState.cancelled, at: _at(current));
    _jobs[jobId] = next;
    _queue.remove(jobId);
    return next;
  }

  /// Starts one queued job, or returns null when no queued job remains.
  JobRecord? runNext() {
    while (_queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      final job = _jobs[id]!;
      if (job.state != JobState.queued) continue;
      final updated = job.transition(JobState.running, at: _at(job));
      _jobs[id] = updated;
      return updated;
    }
    return null;
  }

  /// Explicitly records an outcome. A cancelled task cannot be completed.
  JobRecord finish(String jobId, {required bool succeeded}) {
    final job = _jobs[jobId];
    if (job == null || job.state != JobState.running) {
      throw StateError('Job must be running');
    }
    final updated = job.transition(
      succeeded ? JobState.completed : JobState.failed,
      at: _at(job),
    );
    _jobs[jobId] = updated;
    return updated;
  }

  DateTime _at(JobRecord job) {
    final now = _clock().toUtc();
    return now.isBefore(job.updatedAt) ? job.updatedAt : now;
  }
}
