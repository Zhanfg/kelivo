/// Serializable, isolated sub-Agent session contract.
///
/// Carries only opaque handles. No transcript, prompt, token or host capability
/// is stored in this record. Persistence and authorization are external.
enum SubagentSessionState {
  queued,
  running,
  suspended,
  interrupted,
  outcomeUnknown,
  completed,
  failed,
  cancelled;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

final class SubagentSession {
  SubagentSession({
    required this.sessionId,
    required this.ownerId,
    required this.taskId,
    required this.contextRef,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.parentSessionId,
    this.state = SubagentSessionState.queued,
    this.resultRef,
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    for (final entry in [
      sessionId,
      ownerId,
      taskId,
      contextRef,
      if (parentSessionId != null) parentSessionId!,
      if (resultRef != null) resultRef!,
    ]) {
      if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(entry)) {
        throw ArgumentError('Unsafe session reference');
      }
    }
    if (sessionId == parentSessionId) {
      throw ArgumentError('A session cannot parent itself');
    }
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw ArgumentError('Session time moved backwards');
    }
  }

  static const schemaVersion = 1;

  final String sessionId;
  final String ownerId;
  final String taskId;
  final String contextRef;
  final String? parentSessionId;
  final SubagentSessionState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? resultRef;

  bool get isTerminal => state.isTerminal;

  static const allowed = <SubagentSessionState, Set<SubagentSessionState>>{
    SubagentSessionState.queued: {
      SubagentSessionState.running,
      SubagentSessionState.cancelled,
    },
    SubagentSessionState.running: {
      SubagentSessionState.suspended,
      SubagentSessionState.interrupted,
      SubagentSessionState.outcomeUnknown,
      SubagentSessionState.completed,
      SubagentSessionState.failed,
      SubagentSessionState.cancelled,
    },
    SubagentSessionState.suspended: {
      SubagentSessionState.queued,
      SubagentSessionState.cancelled,
    },
    SubagentSessionState.interrupted: {
      SubagentSessionState.queued,
      SubagentSessionState.outcomeUnknown,
      SubagentSessionState.failed,
      SubagentSessionState.cancelled,
    },
    SubagentSessionState.outcomeUnknown: {
      SubagentSessionState.completed,
      SubagentSessionState.failed,
      SubagentSessionState.cancelled,
    },
    SubagentSessionState.completed: {},
    SubagentSessionState.failed: {},
    SubagentSessionState.cancelled: {},
  };

  SubagentSession transition(
    SubagentSessionState next, {
    required DateTime at,
    bool reviewedUnknownOutcome = false,
    String? newResultRef,
  }) {
    if (!(allowed[state]?.contains(next) ?? false)) {
      throw StateError('Invalid sub-Agent transition');
    }
    if (state == SubagentSessionState.outcomeUnknown &&
        !reviewedUnknownOutcome) {
      throw StateError('Unknown side effect must be reviewed');
    }
    final timestamp = at.toUtc();
    if (timestamp.isBefore(updatedAt)) {
      throw ArgumentError('Nonmonotonic state transition');
    }
    return SubagentSession(
      sessionId: sessionId,
      ownerId: ownerId,
      taskId: taskId,
      contextRef: contextRef,
      parentSessionId: parentSessionId,
      state: next,
      createdAt: createdAt,
      updatedAt: timestamp,
      resultRef: newResultRef ?? resultRef,
    );
  }

  /// Reconcile an in-flight session after restart without running it again.
  SubagentSession interruptedAfterRestart(DateTime at) {
    return state == SubagentSessionState.running
        ? transition(SubagentSessionState.interrupted, at: at)
        : this;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'sessionId': sessionId,
    'ownerId': ownerId,
    'taskId': taskId,
    'contextRef': contextRef,
    'parentSessionId': parentSessionId,
    'state': state.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'resultRef': resultRef,
  };

  factory SubagentSession.fromJson(Map<String, Object?> json) {
    const keys = {
      'schemaVersion',
      'sessionId',
      'ownerId',
      'taskId',
      'contextRef',
      'parentSessionId',
      'state',
      'createdAt',
      'updatedAt',
      'resultRef',
    };
    if (json.keys.any((key) => !keys.contains(key)) ||
        json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported session schema');
    }
    String requiredString(String name) {
      final value = json[name];
      if (value is! String) throw FormatException('Invalid $name');
      return value;
    }

    String? optionalString(String name) {
      final value = json[name];
      if (value != null && value is! String) {
        throw FormatException('Invalid $name');
      }
      return value as String?;
    }

    DateTime requiredTime(String name) {
      final raw = requiredString(name);
      final value = DateTime.tryParse(raw);
      if (value == null || !value.isUtc || !raw.endsWith('Z')) {
        throw FormatException('Invalid UTC time $name');
      }
      return value;
    }

    final stateName = requiredString('state');
    final matched = SubagentSessionState.values.where(
      (state) => state.name == stateName,
    );
    if (matched.length != 1) {
      throw const FormatException('Unknown session state');
    }
    try {
      return SubagentSession(
        sessionId: requiredString('sessionId'),
        ownerId: requiredString('ownerId'),
        taskId: requiredString('taskId'),
        contextRef: requiredString('contextRef'),
        parentSessionId: optionalString('parentSessionId'),
        state: matched.single,
        createdAt: requiredTime('createdAt'),
        updatedAt: requiredTime('updatedAt'),
        resultRef: optionalString('resultRef'),
      );
    } on ArgumentError {
      throw const FormatException('Invalid session model');
    }
  }
}

/// In-memory catalog for contract tests; not a durable session store.
final class SubagentSessionCatalog {
  final Map<String, SubagentSession> _sessions = {};

  void register(SubagentSession session) {
    if (_sessions.containsKey(session.sessionId)) {
      throw StateError('Duplicate session ID');
    }
    if (session.parentSessionId != null) {
      final parent = _sessions[session.parentSessionId];
      if (parent == null || parent.ownerId != session.ownerId) {
        throw StateError('Unregistered or cross-owner parent');
      }
    }
    _sessions[session.sessionId] = session;
  }

  SubagentSession? get(String sessionId) => _sessions[sessionId];

  List<SubagentSession> childrenOf(String parentId) => List.unmodifiable(
    _sessions.values.where((s) => s.parentSessionId == parentId),
  );
}
