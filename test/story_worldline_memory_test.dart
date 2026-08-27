import 'package:Kelivo/core/models/memory_entry.dart';
import 'package:Kelivo/features/story_runtime/memory/story_worldline_memory.dart';
import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_models.dart';
import 'package:flutter_test/flutter_test.dart';

MemoryEntry memory(String id, String content, {int minute = 0}) => MemoryEntry(
  id: id,
  scope: MemoryScope.assistant,
  assistantId: 'assistant',
  type: MemoryType.identity,
  content: content,
  createdAt: DateTime.utc(2026, 8, 27, 0, minute),
  updatedAt: DateTime.utc(2026, 8, 27, 0, minute),
);

StoryWorldTreeState tree() => StoryWorldTreeState(
  worldTreeId: 'tree',
  name: 'Story',
  rootContentHash: 'root',
  headWorldlineId: 'child',
  worldlines: <StoryWorldline>[
    StoryWorldline(
      id: 'root',
      conversationId: 'c-root',
      createdAt: DateTime.utc(2026, 8, 27),
    ),
    StoryWorldline(
      id: 'child',
      conversationId: 'c-child',
      parentWorldlineId: 'root',
      branchPointMessageId: 'm1',
      baseSnapshotId: 's1',
      createdAt: DateTime.utc(2026, 8, 27, 1),
    ),
    StoryWorldline(
      id: 'sibling',
      conversationId: 'c-sibling',
      parentWorldlineId: 'root',
      branchPointMessageId: 'm1',
      baseSnapshotId: 's1',
      createdAt: DateTime.utc(2026, 8, 27, 2),
    ),
  ],
);

void main() {
  const resolver = StoryWorldlineMemoryResolver();

  test(
    'child sees base memory, inherited ancestor, and child local memory',
    () {
      final memories = <MemoryEntry>[
        memory('global', 'global'),
        memory('ancestor', 'ancestor'),
        memory('child', 'child'),
      ];
      final resolved = resolver.resolve(
        tree: tree(),
        currentWorldlineId: 'child',
        baseMemories: memories,
        links: <StoryWorldlineMemoryLink>[
          StoryWorldlineMemoryLink(
            memoryId: 'ancestor',
            sourceWorldlineId: 'root',
            updatedAt: DateTime.utc(2026, 8, 27),
          ),
          StoryWorldlineMemoryLink(
            memoryId: 'child',
            sourceWorldlineId: 'child',
            strategy: StoryMemoryInheritanceStrategy.local,
            visibilityScope: StoryMemoryVisibilityScope.worldline,
            updatedAt: DateTime.utc(2026, 8, 27, 1),
          ),
        ],
      );

      expect(resolved.map((item) => item.entry.id).toSet(), {
        'global',
        'ancestor',
        'child',
      });
      expect(
        resolved.firstWhere((item) => item.entry.id == 'ancestor').inherited,
        isTrue,
      );
    },
  );

  test('local and isolated ancestor memories do not leak into child', () {
    final resolved = resolver.resolve(
      tree: tree(),
      currentWorldlineId: 'child',
      baseMemories: <MemoryEntry>[
        memory('local', 'x'),
        memory('isolated', 'y'),
      ],
      links: <StoryWorldlineMemoryLink>[
        StoryWorldlineMemoryLink(
          memoryId: 'local',
          sourceWorldlineId: 'root',
          strategy: StoryMemoryInheritanceStrategy.local,
          updatedAt: DateTime.utc(2026, 8, 27),
        ),
        StoryWorldlineMemoryLink(
          memoryId: 'isolated',
          sourceWorldlineId: 'root',
          strategy: StoryMemoryInheritanceStrategy.isolated,
          updatedAt: DateTime.utc(2026, 8, 27),
        ),
      ],
    );
    expect(resolved, isEmpty);
  });

  test('sibling worldline facts never leak into current ancestry', () {
    final resolved = resolver.resolve(
      tree: tree(),
      currentWorldlineId: 'child',
      baseMemories: <MemoryEntry>[memory('sibling-fact', 'secret sibling fact')],
      links: <StoryWorldlineMemoryLink>[
        StoryWorldlineMemoryLink(
          memoryId: 'sibling-fact',
          sourceWorldlineId: 'sibling',
          updatedAt: DateTime.utc(2026, 8, 27),
        ),
      ],
    );
    expect(resolved, isEmpty);
  });

  test('nearest worldline wins an entity conflict', () {
    final resolved = resolver.resolve(
      tree: tree(),
      currentWorldlineId: 'child',
      baseMemories: <MemoryEntry>[
        memory('root-name', 'Name is Alice', minute: 1),
        memory('child-name', 'Name is Eve', minute: 2),
      ],
      links: <StoryWorldlineMemoryLink>[
        StoryWorldlineMemoryLink(
          memoryId: 'root-name',
          sourceWorldlineId: 'root',
          entityKey: 'character:hero:name',
          updatedAt: DateTime.utc(2026, 8, 27, 0, 1),
        ),
        StoryWorldlineMemoryLink(
          memoryId: 'child-name',
          sourceWorldlineId: 'child',
          entityKey: 'character:hero:name',
          updatedAt: DateTime.utc(2026, 8, 27, 0, 2),
        ),
      ],
    );
    expect(resolved, hasLength(1));
    expect(resolved.single.entry.id, 'child-name');
  });

  test('provenance round-trips and survives resolution', () {
    final link = StoryWorldlineMemoryLink(
      memoryId: 'fact',
      sourceWorldlineId: 'child',
      validFromMessageId: 'm-7',
      validFromNodeId: 'g@2',
      sourceKind: StoryMemorySourceKind.checkpoint,
      sourceEventId: 'event-7',
      sourceCheckpointId: 'cp-2',
      updatedAt: DateTime.utc(2026, 8, 27, 3),
    );
    final decoded = StoryWorldlineMemoryLink.fromJson(link.toJson());
    expect(decoded.validFromMessageId, 'm-7');
    expect(decoded.sourceCheckpointId, 'cp-2');

    final resolved = resolver.resolve(
      tree: tree(),
      currentWorldlineId: 'child',
      baseMemories: <MemoryEntry>[memory('fact', 'remember me')],
      links: <StoryWorldlineMemoryLink>[decoded],
    );
    expect(resolved.single.sourceKind, StoryMemorySourceKind.checkpoint);
    expect(resolved.single.sourceEventId, 'event-7');
    expect(resolved.single.validFromNodeId, 'g@2');
  });
}
