import '../../../core/models/memory_entry.dart';
import '../world_tree/story_world_tree_models.dart';

enum StoryMemoryInheritanceStrategy { inherited, local, isolated }

enum StoryMemoryVisibilityScope { global, ancestry, worldline }

final class StoryWorldlineMemoryLink {
  const StoryWorldlineMemoryLink({
    required this.memoryId,
    required this.sourceWorldlineId,
    required this.updatedAt,
    this.inheritedFromWorldlineId,
    this.visibilityScope = StoryMemoryVisibilityScope.ancestry,
    this.strategy = StoryMemoryInheritanceStrategy.inherited,
    this.entityKey,
  });

  final String memoryId;
  final String sourceWorldlineId;
  final String? inheritedFromWorldlineId;
  final StoryMemoryVisibilityScope visibilityScope;
  final StoryMemoryInheritanceStrategy strategy;
  final String? entityKey;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'memoryId': memoryId,
    'sourceWorldlineId': sourceWorldlineId,
    if (inheritedFromWorldlineId != null)
      'inheritedFromWorldlineId': inheritedFromWorldlineId,
    'visibilityScope': visibilityScope.name,
    'strategy': strategy.name,
    if (entityKey != null) 'entityKey': entityKey,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory StoryWorldlineMemoryLink.fromJson(Map<String, dynamic> json) =>
      StoryWorldlineMemoryLink(
        memoryId: json['memoryId'] as String,
        sourceWorldlineId: json['sourceWorldlineId'] as String,
        inheritedFromWorldlineId: json['inheritedFromWorldlineId'] as String?,
        visibilityScope: StoryMemoryVisibilityScope.values.firstWhere(
          (value) => value.name == json['visibilityScope'],
          orElse: () => StoryMemoryVisibilityScope.ancestry,
        ),
        strategy: StoryMemoryInheritanceStrategy.values.firstWhere(
          (value) => value.name == json['strategy'],
          orElse: () => StoryMemoryInheritanceStrategy.inherited,
        ),
        entityKey: json['entityKey'] as String?,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

final class StoryResolvedMemory {
  const StoryResolvedMemory({
    required this.entry,
    required this.sourceWorldlineId,
    required this.visibilityScope,
    required this.strategy,
    required this.distance,
    this.inheritedFromWorldlineId,
    this.entityKey,
  });

  final MemoryEntry entry;
  final String? sourceWorldlineId;
  final String? inheritedFromWorldlineId;
  final StoryMemoryVisibilityScope visibilityScope;
  final StoryMemoryInheritanceStrategy strategy;
  final String? entityKey;
  final int distance;

  bool get inherited => distance > 0;
}

/// Resolves Story memory without replacing Kelivo's existing MemoryEntry store.
///
/// Existing active global/assistant memories remain visible exactly as before.
/// Story-specific metadata only controls memories explicitly linked to a
/// worldline. Child worldlines inherit ancestor links unless a link is local or
/// isolated. Conflicts sharing the same entityKey use the nearest worldline,
/// then the most recently updated link.
final class StoryWorldlineMemoryResolver {
  const StoryWorldlineMemoryResolver();

  List<StoryResolvedMemory> resolve({
    required StoryWorldTreeState tree,
    required String currentWorldlineId,
    required List<MemoryEntry> baseMemories,
    required List<StoryWorldlineMemoryLink> links,
  }) {
    final ancestry = _ancestry(tree, currentWorldlineId);
    final distanceByWorldline = <String, int>{
      for (var index = 0; index < ancestry.length; index++)
        ancestry[index]: index,
    };
    final entryById = <String, MemoryEntry>{
      for (final entry in baseMemories)
        if (entry.status == MemoryStatus.active) entry.id: entry,
    };
    final linkedIds = links.map((link) => link.memoryId).toSet();
    final resolved = <StoryResolvedMemory>[
      for (final entry in entryById.values)
        if (!linkedIds.contains(entry.id))
          StoryResolvedMemory(
            entry: entry,
            sourceWorldlineId: null,
            visibilityScope: StoryMemoryVisibilityScope.global,
            strategy: StoryMemoryInheritanceStrategy.inherited,
            distance: 1 << 20,
          ),
    ];

    for (final link in links) {
      final entry = entryById[link.memoryId];
      if (entry == null) continue;
      final distance = distanceByWorldline[link.sourceWorldlineId];
      if (distance == null) {
        if (link.visibilityScope != StoryMemoryVisibilityScope.global) continue;
        resolved.add(
          StoryResolvedMemory(
            entry: entry,
            sourceWorldlineId: link.sourceWorldlineId,
            inheritedFromWorldlineId: link.inheritedFromWorldlineId,
            visibilityScope: link.visibilityScope,
            strategy: link.strategy,
            entityKey: link.entityKey,
            distance: 1 << 19,
          ),
        );
        continue;
      }
      if (distance > 0 &&
          (link.strategy == StoryMemoryInheritanceStrategy.local ||
              link.strategy == StoryMemoryInheritanceStrategy.isolated ||
              link.visibilityScope == StoryMemoryVisibilityScope.worldline)) {
        continue;
      }
      resolved.add(
        StoryResolvedMemory(
          entry: entry,
          sourceWorldlineId: link.sourceWorldlineId,
          inheritedFromWorldlineId: distance > 0
              ? link.sourceWorldlineId
              : link.inheritedFromWorldlineId,
          visibilityScope: link.visibilityScope,
          strategy: link.strategy,
          entityKey: link.entityKey,
          distance: distance,
        ),
      );
    }

    final winners = <String, StoryResolvedMemory>{};
    final unkeyed = <StoryResolvedMemory>[];
    for (final item in resolved) {
      final key = item.entityKey?.trim();
      if (key == null || key.isEmpty) {
        unkeyed.add(item);
        continue;
      }
      final previous = winners[key];
      if (previous == null || _prefer(item, previous, links)) {
        winners[key] = item;
      }
    }
    final result = <StoryResolvedMemory>[...unkeyed, ...winners.values];
    result.sort((a, b) {
      final distance = a.distance.compareTo(b.distance);
      if (distance != 0) return distance;
      return a.entry.id.compareTo(b.entry.id);
    });
    return List.unmodifiable(result);
  }

  bool _prefer(
    StoryResolvedMemory candidate,
    StoryResolvedMemory previous,
    List<StoryWorldlineMemoryLink> links,
  ) {
    if (candidate.distance != previous.distance) {
      return candidate.distance < previous.distance;
    }
    DateTime updated(StoryResolvedMemory item) {
      for (final link in links) {
        if (link.memoryId == item.entry.id &&
            link.sourceWorldlineId == item.sourceWorldlineId) {
          return link.updatedAt;
        }
      }
      return item.entry.updatedAt;
    }

    return updated(candidate).isAfter(updated(previous));
  }

  List<String> _ancestry(StoryWorldTreeState tree, String currentWorldlineId) {
    final result = <String>[];
    final seen = <String>{};
    String? cursor = currentWorldlineId;
    while (cursor != null) {
      if (!seen.add(cursor)) {
        throw StateError('Worldline ancestry contains a cycle at $cursor.');
      }
      final worldline = tree.worldlineById(cursor);
      if (worldline == null) {
        throw StateError('Unknown worldline in ancestry: $cursor');
      }
      result.add(cursor);
      cursor = worldline.parentWorldlineId;
    }
    return result;
  }
}
