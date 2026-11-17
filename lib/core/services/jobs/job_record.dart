/// Wire-only contract for durable asynchronous tasks.
///
/// The executor, persistence layer and authorization checks are intentionally
/// out of scope. Store sensitive command inputs outside this receipt.
enum JobState {
  queued('queued'),
  running('running'),
  paused('paused'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled'),
  interrupted('interrupted'),
  outcomeUnknown('outcome_unknown');

  const JobState(this.wireName);

  final String wireName;

  static JobState parse(String value) {
    for (final state in values) {
      if (state.wireName == value) return state;
    }
    throw FormatException('Unknown job state: ' + value);
  }

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

/// Immutable task receipt. A retry of a terminal job is a distinct job.
///
/// No local paths, secrets or raw command arguments belong in the record.
class JobRecord {
  JobRecord({
    required this.jobId,
    required this.kind,
    required this.ownerId,
    required this.state,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.attempt = 0,
    this.maxAttempts = 1,
    this.idempotencyKey,
    this.resultRef,
    this.errorCode,
    List<String> artifactIds = const [],
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       artifactIds = List<String>.unmodifiable(artifactIds) {
    _validate();
  }

  static const schemaVersion = 1;
  static final _jobPattern = RegExp(r'^job_[a-z0-9][a-z0-9_-]{7,127}$');
  static final _kindPattern = RegExp(r'^[a-z][a-z0-9_]{1,63}$');
  static final _handlePattern = RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$');

  final String jobId;
  final String kind;
  final String ownerId;
  final JobState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int attempt;
  final int maxAttempts;
  final String? idempotencyKey;
  final String? resultRef;
  final String? errorCode;
  final List<String> artifactIds;

  bool get isTerminal => state.isTerminal;

  void _validate() {
    if (!_jobPattern.hasMatch(jobId)) {
      throw ArgumentError.value(jobId, 'jobId', 'Invalid job ID');
    }
    if (!_kindPattern.hasMatch(kind)) {
      throw ArgumentError.value(kind, 'kind', 'Invalid task kind');
    }
    if (!_handlePattern.hasMatch(ownerId)) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Invalid owner');
    }
    if (attempt < 0 || maxAttempts < 1 || attempt > maxAttempts) {
      throw ArgumentError('Invalid attempt budget');
    }
    if (updatedAt.isBefore(createdAt)) {
      throw ArgumentError('updatedAt precedes createdAt');
    }
    for (final value in [
      if (idempotencyKey != null) idempotencyKey!,
      if (resultRef != null) resultRef!,
      if (errorCode != null) errorCode!,
      ...artifactIds,
    ]) {
      if (!_handlePattern.hasMatch(value)) {
        throw ArgumentError('Invalid opaque handle');
      }
    }
    if (artifactIds.toSet().length != artifactIds.length) {
      throw ArgumentError('Duplicate artifact handles');
    }
  }

  /// Explicit state graph. In particular, unknown outcomes never auto-retry.
  static const Map<JobState, Set<JobState>> allowedTransitions = {
    JobState.queued: {JobState.running, JobState.cancelled},
    JobState.running: {
      JobState.paused,
      JobState.completed,
      JobState.failed,
      JobState.cancelled,
      JobState.interrupted,
      JobState.outcomeUnknown,
    },
    JobState.paused: {JobState.queued, JobState.cancelled},
    JobState.interrupted: {
      JobState.queued,
      JobState.outcomeUnknown,
      JobState.failed,
      JobState.cancelled,
    },
    JobState.outcomeUnknown: {
      JobState.completed,
      JobState.failed,
      JobState.cancelled,
    },
    JobState.completed: {},
    JobState.failed: {},
    JobState.cancelled: {},
  };

  /// Reconciliation of a previously unknown side effect must be explicit.
  JobRecord transition(
    JobState next, {
    required DateTime at,
    bool outcomeReviewed = false,
    String? newResultRef,
    String? newErrorCode,
  }) {
    if (!(allowedTransitions[state]?.contains(next) ?? false)) {
      throw StateError('Illegal job state transition');
    }
    if (state == JobState.outcomeUnknown && !outcomeReviewed) {
      throw StateError('Unknown outcome requires manual reconciliation');
    }
    final timestamp = at.toUtc();
    if (timestamp.isBefore(updatedAt)) {
      throw ArgumentError('Transition time moved backwards');
    }
    return JobRecord(
      jobId: jobId,
      kind: kind,
      ownerId: ownerId,
      state: next,
      createdAt: createdAt,
      updatedAt: timestamp,
      attempt: attempt,
      maxAttempts: maxAttempts,
      idempotencyKey: idempotencyKey,
      resultRef: newResultRef ?? resultRef,
      errorCode: newErrorCode ?? errorCode,
      artifactIds: artifactIds,
    );
  }

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'job_id': jobId,
    'kind': kind,
    'owner_id': ownerId,
    'state': state.wireName,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'attempt': attempt,
    'max_attempts': maxAttempts,
    if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
    if (resultRef != null) 'result_ref': resultRef,
    if (errorCode != null) 'error_code': errorCode,
    'artifact_ids': List<String>.of(artifactIds),
  };

  /// Decode untrusted data. Explicit migration is required for future versions.
  factory JobRecord.fromJson(Map<String, Object?> json) {
    try {
      if (json['schema_version'] != schemaVersion) {
        throw const FormatException('Unsupported job schema version');
      }
      final ids = json['artifact_ids'];
      if (ids is! List || ids.any((item) => item is! String)) {
        throw const FormatException('artifact_ids must be a string list');
      }
      return JobRecord(
        jobId: _requiredString(json, 'job_id'),
        kind: _requiredString(json, 'kind'),
        ownerId: _requiredString(json, 'owner_id'),
        state: JobState.parse(_requiredString(json, 'state')),
        createdAt: _timestamp(json, 'created_at'),
        updatedAt: _timestamp(json, 'updated_at'),
        attempt: _requiredInt(json, 'attempt'),
        maxAttempts: _requiredInt(json, 'max_attempts'),
        idempotencyKey: _optionalString(json, 'idempotency_key'),
        resultRef: _optionalString(json, 'result_ref'),
        errorCode: _optionalString(json, 'error_code'),
        artifactIds: ids.cast<String>(),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid job record: ' + error.toString());
    } on TypeError catch (_) {
      throw const FormatException('Invalid job record field type');
    }
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) throw FormatException(key + ' must be a string');
    return value;
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    if (json[key] == null) return null;
    return _requiredString(json, key);
  }

  static int _requiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) throw FormatException(key + ' must be an integer');
    return value;
  }

  static DateTime _timestamp(Map<String, Object?> json, String key) {
    final text = _requiredString(json, key);
    if (!text.endsWith('Z')) {
      throw FormatException(key + ' must be UTC ISO-8601');
    }
    final result = DateTime.tryParse(text);
    if (result == null || !result.isUtc) {
      throw FormatException(key + ' must be UTC ISO-8601');
    }
    return result;
  }
}
