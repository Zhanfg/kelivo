import '../../../core/services/json_blob_store.dart';

enum StoryRuntimePhase {
  idle,
  assembling,
  awaitingModel,
  parsing,
  applying,
  awaitingUser,
  failed,
}

final class StoryRuntimeExecutionState {
  const StoryRuntimeExecutionState({
    required this.conversationId,
    this.phase = StoryRuntimePhase.idle,
    this.runtimeStateVersion = 0,
    this.memoryVersion = 0,
    this.worldTreeId,
    this.worldlineId,
    this.currentTurnId,
    this.recentFailure,
  }) : assert(conversationId != ''),
       assert(runtimeStateVersion >= 0),
       assert(memoryVersion >= 0);

  final String conversationId;
  final StoryRuntimePhase phase;
  final int runtimeStateVersion;
  final int memoryVersion;
  final String? worldTreeId;
  final String? worldlineId;
  final String? currentTurnId;
  final String? recentFailure;

  StoryRuntimeExecutionState copyWith({
    StoryRuntimePhase? phase,
    int? runtimeStateVersion,
    int? memoryVersion,
    String? worldTreeId,
    String? worldlineId,
    String? currentTurnId,
    String? recentFailure,
    bool clearTurnId = false,
    bool clearFailure = false,
  }) => StoryRuntimeExecutionState(
    conversationId: conversationId,
    phase: phase ?? this.phase,
    runtimeStateVersion: runtimeStateVersion ?? this.runtimeStateVersion,
    memoryVersion: memoryVersion ?? this.memoryVersion,
    worldTreeId: worldTreeId ?? this.worldTreeId,
    worldlineId: worldlineId ?? this.worldlineId,
    currentTurnId: clearTurnId ? null : (currentTurnId ?? this.currentTurnId),
    recentFailure: clearFailure ? null : (recentFailure ?? this.recentFailure),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'conversationId': conversationId,
    'phase': phase.name,
    'runtimeStateVersion': runtimeStateVersion,
    'memoryVersion': memoryVersion,
    if (worldTreeId != null) 'worldTreeId': worldTreeId,
    if (worldlineId != null) 'worldlineId': worldlineId,
    if (currentTurnId != null) 'currentTurnId': currentTurnId,
    if (recentFailure != null) 'recentFailure': recentFailure,
  };

  factory StoryRuntimeExecutionState.fromJson(Map<String, dynamic> json) =>
      StoryRuntimeExecutionState(
        conversationId: json['conversationId'] as String,
        phase: StoryRuntimePhase.values.firstWhere(
          (value) => value.name == json['phase'],
          orElse: () => StoryRuntimePhase.idle,
        ),
        runtimeStateVersion:
            (json['runtimeStateVersion'] as num?)?.toInt() ?? 0,
        memoryVersion: (json['memoryVersion'] as num?)?.toInt() ?? 0,
        worldTreeId: json['worldTreeId'] as String?,
        worldlineId: json['worldlineId'] as String?,
        currentTurnId: json['currentTurnId'] as String?,
        recentFailure: json['recentFailure'] as String?,
      );
}

abstract interface class StoryRuntimeExecutionRepository {
  Future<StoryRuntimeExecutionState> readOrDefault(String conversationId);
  Future<void> upsert(StoryRuntimeExecutionState state);
}

final class StoryRuntimeExecutionStore
    extends JsonBlobStore<StoryRuntimeExecutionState>
    implements StoryRuntimeExecutionRepository {
  StoryRuntimeExecutionStore(super.preferences);

  static const String key = 'story_runtime_execution_v1';

  @override
  String get storageKey => key;

  @override
  StoryRuntimeExecutionState decodeItem(Map<String, dynamic> json) =>
      StoryRuntimeExecutionState.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryRuntimeExecutionState item) =>
      item.toJson();

  @override
  Future<StoryRuntimeExecutionState> readOrDefault(
    String conversationId,
  ) async {
    final id = _required(conversationId);
    for (final item in await readAll()) {
      if (item.conversationId == id) return item;
    }
    return StoryRuntimeExecutionState(conversationId: id);
  }

  @override
  Future<void> upsert(StoryRuntimeExecutionState state) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryRuntimeExecutionState>[];
      var replaced = false;
      for (final item in items) {
        if (item.conversationId != state.conversationId) {
          next.add(item);
        } else if (!replaced) {
          next.add(state);
          replaced = true;
        }
      }
      if (!replaced) next.add(state);
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }
}

final class StoryRuntimeStateMachine {
  const StoryRuntimeStateMachine(this.repository);

  final StoryRuntimeExecutionRepository repository;

  Future<StoryRuntimeExecutionState> transition({
    required String conversationId,
    required StoryRuntimePhase to,
    String? worldTreeId,
    String? worldlineId,
    String? currentTurnId,
    int? memoryVersion,
    String? failure,
  }) async {
    final current = await repository.readOrDefault(conversationId);
    if (!_allowed(current.phase, to)) {
      throw StateError(
        'invalid_story_runtime_transition:${current.phase.name}->${to.name}',
      );
    }
    final next = current.copyWith(
      phase: to,
      runtimeStateVersion: current.runtimeStateVersion + 1,
      memoryVersion: memoryVersion,
      worldTreeId: worldTreeId,
      worldlineId: worldlineId,
      currentTurnId: currentTurnId,
      recentFailure: failure,
      clearTurnId: to == StoryRuntimePhase.idle,
      clearFailure: to != StoryRuntimePhase.failed && failure == null,
    );
    await repository.upsert(next);
    return next;
  }

  Future<StoryRuntimeExecutionState> fail({
    required String conversationId,
    required Object error,
  }) async {
    final current = await repository.readOrDefault(conversationId);
    final next = current.copyWith(
      phase: StoryRuntimePhase.failed,
      runtimeStateVersion: current.runtimeStateVersion + 1,
      recentFailure: error.toString(),
    );
    await repository.upsert(next);
    return next;
  }
}

bool _allowed(StoryRuntimePhase from, StoryRuntimePhase to) {
  if (to == StoryRuntimePhase.failed) return true;
  return switch (from) {
    StoryRuntimePhase.idle => to == StoryRuntimePhase.assembling,
    StoryRuntimePhase.assembling => to == StoryRuntimePhase.awaitingModel,
    StoryRuntimePhase.awaitingModel => to == StoryRuntimePhase.parsing,
    StoryRuntimePhase.parsing => to == StoryRuntimePhase.applying,
    StoryRuntimePhase.applying => to == StoryRuntimePhase.awaitingUser,
    StoryRuntimePhase.awaitingUser =>
      to == StoryRuntimePhase.assembling || to == StoryRuntimePhase.idle,
    StoryRuntimePhase.failed =>
      to == StoryRuntimePhase.idle || to == StoryRuntimePhase.assembling,
  };
}

String _required(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, 'conversationId');
  return normalized;
}
