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

/// Stable restore point inside one worldline.
///
/// A checkpoint references Kelivo-native message/node identity rather than
/// copying message content. Rewind therefore creates a new worldline that
/// points back to this checkpoint while the original timeline remains intact.
final class StoryWorldCheckpoint {
  const StoryWorldCheckpoint({
    required this.id,
    required this.worldlineId,
    required this.messageId,
    required this.createdAt,
    this.nodeId,
    this.snapshotId,
    this.label,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String worldlineId;
  final String messageId;
  final String? nodeId;
  final String? snapshotId;
  final String? label;
  final DateTime createdAt;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'worldlineId': worldlineId,
    'messageId': messageId,
    if (nodeId != null) 'nodeId': nodeId,
    if (snapshotId != null) 'snapshotId': snapshotId,
    if (label != null) 'label': label,
    'createdAt': createdAt.toIso8601String(),
    'metadata': metadata,
  };

  factory StoryWorldCheckpoint.fromJson(Map<String, dynamic> json) =>
      StoryWorldCheckpoint(
        id: json['id'] as String,
        worldlineId: json['worldlineId'] as String,
        messageId: json['messageId'] as String,
        nodeId: json['nodeId'] as String?,
        snapshotId: json['snapshotId'] as String?,
        label: json['label'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
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

/// Structural comparison between two worldlines.
final class StoryWorldlineComparison {
  const StoryWorldlineComparison({
    required this.leftWorldlineId,
    required this.rightWorldlineId,
    required this.leftAncestry,
    required this.rightAncestry,
    this.commonAncestorWorldlineId,
  });

  final String leftWorldlineId;
  final String rightWorldlineId;
  final String? commonAncestorWorldlineId;
  final List<String> leftAncestry;
  final List<String> rightAncestry;

  bool get areSame => leftWorldlineId == rightWorldlineId;
}

final class StoryWorldTreeState {
  const StoryWorldTreeState({
    required this.worldTreeId,
    required this.name,
    required this.rootContentHash,
    required this.headWorldlineId,
    required this.worldlines,
    this.mainlineWorldlineId,
    this.currentNodeId,
    this.currentMessageId,
    this.memoryVersion = 0,
    this.runtimeStateVersion = 0,
    this.checkpoints = const <StoryWorldCheckpoint>[],
    this.merges = const <StoryWorldMergeRecord>[],
    this.metadata = const <String, Object?>{},
  });

  final String worldTreeId;
  final String name;
  final String rootContentHash;
  final String headWorldlineId;
  final String? mainlineWorldlineId;
  final String? currentNodeId;
  final String? currentMessageId;
  final int memoryVersion;
  final int runtimeStateVersion;
  final List<StoryWorldline> worldlines;
  final List<StoryWorldCheckpoint> checkpoints;
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

  StoryWorldCheckpoint? checkpointById(String id) {
    for (final checkpoint in checkpoints) {
      if (checkpoint.id == id) return checkpoint;
    }
    return null;
  }

  List<String> ancestryOf(String worldlineId) {
    final result = <String>[];
    final seen = <String>{};
    String? cursor = worldlineId;
    while (cursor != null) {
      if (!seen.add(cursor)) {
        throw StateError('Worldline ancestry contains a cycle at $cursor.');
      }
      final line = worldlineById(cursor);
      if (line == null) throw StateError('Unknown worldline: $cursor');
      result.add(cursor);
      cursor = line.parentWorldlineId;
    }
    return List.unmodifiable(result);
  }

  StoryWorldlineComparison compare(String leftWorldlineId, String rightWorldlineId) {
    final left = ancestryOf(leftWorldlineId);
    final right = ancestryOf(rightWorldlineId);
    final rightSet = right.toSet();
    String? common;
    for (final id in left) {
      if (rightSet.contains(id)) {
        common = id;
        break;
      }
    }
    return StoryWorldlineComparison(
      leftWorldlineId: leftWorldlineId,
      rightWorldlineId: rightWorldlineId,
      commonAncestorWorldlineId: common,
      leftAncestry: left,
      rightAncestry: right,
    );
  }

  StoryWorldTreeState copyWith({
    String? name,
    String? rootContentHash,
    String? headWorldlineId,
    String? mainlineWorldlineId,
    String? currentNodeId,
    String? currentMessageId,
    int? memoryVersion,
    int? runtimeStateVersion,
    List<StoryWorldline>? worldlines,
    List<StoryWorldCheckpoint>? checkpoints,
    List<StoryWorldMergeRecord>? merges,
    Map<String, Object?>? metadata,
    bool clearMainlineWorldlineId = false,
    bool clearCurrentNodeId = false,
    bool clearCurrentMessageId = false,
  }) => StoryWorldTreeState(
    worldTreeId: worldTreeId,
    name: name ?? this.name,
    rootContentHash: rootContentHash ?? this.rootContentHash,
    headWorldlineId: headWorldlineId ?? this.headWorldlineId,
    mainlineWorldlineId: clearMainlineWorldlineId
        ? null
        : (mainlineWorldlineId ?? this.mainlineWorldlineId),
    currentNodeId: clearCurrentNodeId
        ? null
        : (currentNodeId ?? this.currentNodeId),
    currentMessageId: clearCurrentMessageId
        ? null
        : (currentMessageId ?? this.currentMessageId),
    memoryVersion: memoryVersion ?? this.memoryVersion,
    runtimeStateVersion: runtimeStateVersion ?? this.runtimeStateVersion,
    worldlines: worldlines ?? this.worldlines,
    checkpoints: checkpoints ?? this.checkpoints,
    merges: merges ?? this.merges,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'worldTreeId': worldTreeId,
    'name': name,
    'rootContentHash': rootContentHash,
    'headWorldlineId': headWorldlineId,
    if (mainlineWorldlineId != null) 'mainlineWorldlineId': mainlineWorldlineId,
    if (currentNodeId != null) 'currentNodeId': currentNodeId,
    if (currentMessageId != null) 'currentMessageId': currentMessageId,
    'memoryVersion': memoryVersion,
    'runtimeStateVersion': runtimeStateVersion,
    'worldlines': worldlines.map((item) => item.toJson()).toList(),
    'checkpoints': checkpoints.map((item) => item.toJson()).toList(),
    'merges': merges.map((item) => item.toJson()).toList(),
    'metadata': metadata,
  };

  factory StoryWorldTreeState.fromJson(Map<String, dynamic> json) =>
      StoryWorldTreeState(
        worldTreeId: json['worldTreeId'] as String,
        name: json['name'] as String? ?? 'Story',
        rootContentHash: json['rootContentHash'] as String? ?? '',
        headWorldlineId: json['headWorldlineId'] as String,
        mainlineWorldlineId: json['mainlineWorldlineId'] as String?,
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
        checkpoints: ((json['checkpoints'] as List?) ?? const <Object?>[])
            .map(
              (item) => StoryWorldCheckpoint.fromJson(
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
