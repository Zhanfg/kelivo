enum StoryWorldlineStatus { active, merged, archived }

final class StoryWorldline {
  const StoryWorldline({
    required this.id,
    required this.conversationId,
    required this.createdAt,
    this.parentWorldlineId,
    this.branchPointMessageId,
    this.baseSnapshotId,
    this.status = StoryWorldlineStatus.active,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String conversationId;
  final DateTime createdAt;
  final String? parentWorldlineId;
  final String? branchPointMessageId;
  final String? baseSnapshotId;
  final StoryWorldlineStatus status;
  final Map<String, Object?> metadata;

  StoryWorldline copyWith({
    StoryWorldlineStatus? status,
    Map<String, Object?>? metadata,
  }) => StoryWorldline(
    id: id,
    conversationId: conversationId,
    createdAt: createdAt,
    parentWorldlineId: parentWorldlineId,
    branchPointMessageId: branchPointMessageId,
    baseSnapshotId: baseSnapshotId,
    status: status ?? this.status,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'conversationId': conversationId,
    'createdAt': createdAt.toIso8601String(),
    if (parentWorldlineId != null) 'parentWorldlineId': parentWorldlineId,
    if (branchPointMessageId != null)
      'branchPointMessageId': branchPointMessageId,
    if (baseSnapshotId != null) 'baseSnapshotId': baseSnapshotId,
    'status': status.name,
    'metadata': metadata,
  };

  factory StoryWorldline.fromJson(Map<String, dynamic> json) => StoryWorldline(
    id: json['id'] as String,
    conversationId: json['conversationId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    parentWorldlineId: json['parentWorldlineId'] as String?,
    branchPointMessageId: json['branchPointMessageId'] as String?,
    baseSnapshotId: json['baseSnapshotId'] as String?,
    status: StoryWorldlineStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => StoryWorldlineStatus.active,
    ),
    metadata: Map<String, Object?>.from(
      (json['metadata'] as Map?) ?? const <String, Object?>{},
    ),
  );
}

final class StoryWorldMergeRecord {
  const StoryWorldMergeRecord({
    required this.id,
    required this.sourceWorldlineId,
    required this.targetWorldlineId,
    required this.createdAt,
    this.strategy = 'manual',
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String sourceWorldlineId;
  final String targetWorldlineId;
  final DateTime createdAt;
  final String strategy;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'sourceWorldlineId': sourceWorldlineId,
    'targetWorldlineId': targetWorldlineId,
    'createdAt': createdAt.toIso8601String(),
    'strategy': strategy,
    'metadata': metadata,
  };

  factory StoryWorldMergeRecord.fromJson(Map<String, dynamic> json) =>
      StoryWorldMergeRecord(
        id: json['id'] as String,
        sourceWorldlineId: json['sourceWorldlineId'] as String,
        targetWorldlineId: json['targetWorldlineId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        strategy: json['strategy'] as String? ?? 'manual',
        metadata: Map<String, Object?>.from(
          (json['metadata'] as Map?) ?? const <String, Object?>{},
        ),
      );
}

final class StoryWorldTreeState {
  const StoryWorldTreeState({
    required this.worldTreeId,
    required this.name,
    required this.rootContentHash,
    required this.headWorldlineId,
    required this.worldlines,
    this.currentNodeId,
    this.currentMessageId,
    this.memoryVersion = 0,
    this.runtimeStateVersion = 0,
    this.merges = const <StoryWorldMergeRecord>[],
    this.metadata = const <String, Object?>{},
  });

  final String worldTreeId;
  final String name;
  final String rootContentHash;
  final String headWorldlineId;
  final String? currentNodeId;
  final String? currentMessageId;
  final int memoryVersion;
  final int runtimeStateVersion;
  final List<StoryWorldline> worldlines;
  final List<StoryWorldMergeRecord> merges;
  final Map<String, Object?> metadata;

  StoryWorldline? worldlineById(String id) {
    for (final worldline in worldlines) {
      if (worldline.id == id) return worldline;
    }
    return null;
  }

  StoryWorldline? worldlineForConversation(String conversationId) {
    for (final worldline in worldlines) {
      if (worldline.conversationId == conversationId) return worldline;
    }
    return null;
  }

  StoryWorldTreeState copyWith({
    String? name,
    String? rootContentHash,
    String? headWorldlineId,
    String? currentNodeId,
    String? currentMessageId,
    int? memoryVersion,
    int? runtimeStateVersion,
    List<StoryWorldline>? worldlines,
    List<StoryWorldMergeRecord>? merges,
    Map<String, Object?>? metadata,
    bool clearCurrentNodeId = false,
    bool clearCurrentMessageId = false,
  }) => StoryWorldTreeState(
    worldTreeId: worldTreeId,
    name: name ?? this.name,
    rootContentHash: rootContentHash ?? this.rootContentHash,
    headWorldlineId: headWorldlineId ?? this.headWorldlineId,
    currentNodeId: clearCurrentNodeId
        ? null
        : (currentNodeId ?? this.currentNodeId),
    currentMessageId: clearCurrentMessageId
        ? null
        : (currentMessageId ?? this.currentMessageId),
    memoryVersion: memoryVersion ?? this.memoryVersion,
    runtimeStateVersion: runtimeStateVersion ?? this.runtimeStateVersion,
    worldlines: worldlines ?? this.worldlines,
    merges: merges ?? this.merges,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'worldTreeId': worldTreeId,
    'name': name,
    'rootContentHash': rootContentHash,
    'headWorldlineId': headWorldlineId,
    if (currentNodeId != null) 'currentNodeId': currentNodeId,
    if (currentMessageId != null) 'currentMessageId': currentMessageId,
    'memoryVersion': memoryVersion,
    'runtimeStateVersion': runtimeStateVersion,
    'worldlines': worldlines.map((item) => item.toJson()).toList(),
    'merges': merges.map((item) => item.toJson()).toList(),
    'metadata': metadata,
  };

  factory StoryWorldTreeState.fromJson(Map<String, dynamic> json) =>
      StoryWorldTreeState(
        worldTreeId: json['worldTreeId'] as String,
        name: json['name'] as String? ?? 'Story',
        rootContentHash: json['rootContentHash'] as String? ?? '',
        headWorldlineId: json['headWorldlineId'] as String,
        currentNodeId: json['currentNodeId'] as String?,
        currentMessageId: json['currentMessageId'] as String?,
        memoryVersion: (json['memoryVersion'] as num?)?.toInt() ?? 0,
        runtimeStateVersion:
            (json['runtimeStateVersion'] as num?)?.toInt() ?? 0,
        worldlines: ((json['worldlines'] as List?) ?? const <Object?>[])
            .map(
              (item) => StoryWorldline.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
        merges: ((json['merges'] as List?) ?? const <Object?>[])
            .map(
              (item) => StoryWorldMergeRecord.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
        metadata: Map<String, Object?>.from(
          (json['metadata'] as Map?) ?? const <String, Object?>{},
        ),
      );
}
