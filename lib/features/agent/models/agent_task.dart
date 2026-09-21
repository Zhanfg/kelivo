enum AgentTaskPhase {
  queued,
  preparing,
  running,
  waitingApproval,
  verifying,
  paused,
  completed,
  failed,
  cancelled,
  interrupted,
  recovering,
}

extension AgentTaskPhaseState on AgentTaskPhase {
  bool get isTerminal => switch (this) {
    AgentTaskPhase.completed ||
    AgentTaskPhase.failed ||
    AgentTaskPhase.cancelled => true,
    _ => false,
  };

  bool get canResume => switch (this) {
    AgentTaskPhase.paused ||
    AgentTaskPhase.interrupted ||
    AgentTaskPhase.failed => true,
    _ => false,
  };
}

class AgentTask {
  const AgentTask({
    required this.id,
    required this.title,
    required this.goal,
    required this.workspaceId,
    required this.environmentId,
    required this.phase,
    required this.createdAt,
    required this.updatedAt,
    this.conversationId,
    this.assistantId,
    this.worktreeId,
    this.modelProviderKey,
    this.modelId,
    this.currentStep,
    this.completedSteps = 0,
    this.totalSteps,
    this.lastError,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String title;
  final String goal;

  /// Persistent KELIVO workspace containing the task's user-owned files.
  final String workspaceId;

  /// Persistent execution environment. This is deliberately independent from
  /// the runtime process so Android may kill/restart the executor safely.
  final String environmentId;

  /// Optional links back to the ordinary KELIVO chat/assistant surfaces.
  final String? conversationId;
  final String? assistantId;

  /// Optional isolated Git worktree used by this task.
  final String? worktreeId;

  /// Model snapshot captured when the task was created. This makes resumed
  /// tasks reproducible even if the mode-level model changes later.
  final String? modelProviderKey;
  final String? modelId;

  final AgentTaskPhase phase;
  final String? currentStep;
  final int completedSteps;
  final int? totalSteps;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get canResume => phase.canResume;

  AgentTask copyWith({
    String? title,
    String? goal,
    String? workspaceId,
    String? environmentId,
    String? conversationId,
    String? assistantId,
    String? worktreeId,
    String? modelProviderKey,
    String? modelId,
    AgentTaskPhase? phase,
    String? currentStep,
    int? completedSteps,
    int? totalSteps,
    String? lastError,
    DateTime? updatedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool clearConversationId = false,
    bool clearAssistantId = false,
    bool clearWorktreeId = false,
    bool clearModel = false,
    bool clearCurrentStep = false,
    bool clearTotalSteps = false,
    bool clearLastError = false,
    bool clearStartedAt = false,
    bool clearFinishedAt = false,
  }) {
    return AgentTask(
      id: id,
      title: title ?? this.title,
      goal: goal ?? this.goal,
      workspaceId: workspaceId ?? this.workspaceId,
      environmentId: environmentId ?? this.environmentId,
      conversationId: clearConversationId
          ? null
          : (conversationId ?? this.conversationId),
      assistantId: clearAssistantId ? null : (assistantId ?? this.assistantId),
      worktreeId: clearWorktreeId ? null : (worktreeId ?? this.worktreeId),
      modelProviderKey: clearModel
          ? null
          : (modelProviderKey ?? this.modelProviderKey),
      modelId: clearModel ? null : (modelId ?? this.modelId),
      phase: phase ?? this.phase,
      currentStep: clearCurrentStep ? null : (currentStep ?? this.currentStep),
      completedSteps: completedSteps ?? this.completedSteps,
      totalSteps: clearTotalSteps ? null : (totalSteps ?? this.totalSteps),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      finishedAt: clearFinishedAt ? null : (finishedAt ?? this.finishedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'goal': goal,
    'workspaceId': workspaceId,
    'environmentId': environmentId,
    'conversationId': conversationId,
    'assistantId': assistantId,
    'worktreeId': worktreeId,
    'modelProviderKey': modelProviderKey,
    'modelId': modelId,
    'phase': phase.name,
    'currentStep': currentStep,
    'completedSteps': completedSteps,
    'totalSteps': totalSteps,
    'lastError': lastError,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'startedAt': startedAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
  };

  factory AgentTask.fromJson(Map<String, dynamic> json) {
    return AgentTask(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      goal: json['goal'] as String? ?? '',
      workspaceId: json['workspaceId'] as String,
      environmentId: json['environmentId'] as String? ?? 'default',
      conversationId: json['conversationId'] as String?,
      assistantId: json['assistantId'] as String?,
      worktreeId: json['worktreeId'] as String?,
      modelProviderKey: json['modelProviderKey'] as String?,
      modelId: json['modelId'] as String?,
      phase: _phaseFromString(json['phase'] as String?),
      currentStep: json['currentStep'] as String?,
      completedSteps: (json['completedSteps'] as num?)?.toInt() ?? 0,
      totalSteps: (json['totalSteps'] as num?)?.toInt(),
      lastError: json['lastError'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
    );
  }

  static AgentTaskPhase _phaseFromString(String? value) {
    return AgentTaskPhase.values.firstWhere(
      (phase) => phase.name == value,
      orElse: () => AgentTaskPhase.queued,
    );
  }
}
