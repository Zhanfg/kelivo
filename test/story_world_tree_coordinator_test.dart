import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_coordinator.dart';
import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_models.dart';
import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_store.dart';

final class _MemoryWorldTreeRepository implements StoryWorldTreeRepository {
  StoryWorldTreeState? state;

  @override
  Future<StoryWorldTreeState?> read(String worldTreeId) async =>
      state?.worldTreeId == worldTreeId ? state : null;

  @override
  Future<StoryWorldTreeState?> readForConversation(String conversationId) async =>
      state?.worldlineForConversation(conversationId) != null ? state : null;

  @override
  Future<void> upsert(StoryWorldTreeState value) async {
    state = value;
  }

  @override
  Future<void> remove(String worldTreeId) async {
    if (state?.worldTreeId == worldTreeId) state = null;
  }
}

void main() {
  late _MemoryWorldTreeRepository repository;
  late StoryWorldTreeCoordinator coordinator;

  setUp(() {
    repository = _MemoryWorldTreeRepository();
    coordinator = StoryWorldTreeCoordinator(
      repository: repository,
      now: () => DateTime.utc(2026, 9, 20, 2, 30),
    );
  });

  test('bootstrap is idempotent for an existing Story conversation', () async {
    final first = await coordinator.bootstrap(
      conversationId: 'conversation-root',
      name: 'Story',
      rootContentHash: 'root-hash',
    );
    final second = await coordinator.bootstrap(
      conversationId: 'conversation-root',
      name: 'Changed name must not replace the existing tree',
      rootContentHash: 'other-hash',
    );

    expect(second.worldTreeId, first.worldTreeId);
    expect(second.headWorldlineId, first.headWorldlineId);
    expect(second.mainlineWorldlineId, first.mainlineWorldlineId);
    expect(second.worldlines, hasLength(1));
  });

  test('checkpoint rewind creates a child without mutating the source', () async {
    final root = await coordinator.bootstrap(
      conversationId: 'conversation-root',
      name: 'Story',
      rootContentHash: 'root-hash',
    );
    final checkpointed = await coordinator.createCheckpoint(
      worldTreeId: root.worldTreeId,
      worldlineId: root.headWorldlineId,
      messageId: 'message-10',
      nodeId: 'group-10@0',
      snapshotId: 'snapshot-10',
      label: 'Before the choice',
    );
    final checkpoint = checkpointed.checkpoints.single;

    final rewound = await coordinator.rewindFromCheckpoint(
      worldTreeId: root.worldTreeId,
      checkpointId: checkpoint.id,
      childConversationId: 'conversation-rewind',
    );
    final source = rewound.worldlineById(root.headWorldlineId)!;
    final child = rewound.worldlineForConversation('conversation-rewind')!;

    expect(source.parentWorldlineId, isNull);
    expect(source.status, StoryWorldlineStatus.active);
    expect(child.parentWorldlineId, source.id);
    expect(child.branchPointMessageId, 'message-10');
    expect(child.baseSnapshotId, 'snapshot-10');
    expect(child.metadata['operation'], 'rewind');
    expect(child.metadata['checkpointId'], checkpoint.id);
    expect(rewound.headWorldlineId, child.id);
    expect(rewound.worldlines, hasLength(2));
  });

  test('merge marks only the source merged and moves the head to target', () async {
    final root = await coordinator.bootstrap(
      conversationId: 'conversation-root',
      name: 'Story',
      rootContentHash: 'root-hash',
    );
    final forked = await coordinator.fork(
      worldTreeId: root.worldTreeId,
      sourceWorldlineId: root.headWorldlineId,
      childConversationId: 'conversation-child',
      branchPointMessageId: 'message-5',
      baseSnapshotId: 'snapshot-5',
    );
    final child = forked.worldlineForConversation('conversation-child')!;

    final merged = await coordinator.merge(
      worldTreeId: root.worldTreeId,
      sourceWorldlineId: root.headWorldlineId,
      targetWorldlineId: child.id,
      strategy: 'manual',
    );

    expect(
      merged.worldlineById(root.headWorldlineId)!.status,
      StoryWorldlineStatus.merged,
    );
    expect(
      merged.worldlineById(child.id)!.status,
      StoryWorldlineStatus.active,
    );
    expect(merged.headWorldlineId, child.id);
    expect(merged.merges, hasLength(1));
    expect(merged.merges.single.sourceWorldlineId, root.headWorldlineId);
    expect(merged.merges.single.targetWorldlineId, child.id);
  });

  test('active head must be switched before it can be archived', () async {
    final root = await coordinator.bootstrap(
      conversationId: 'conversation-root',
      name: 'Story',
      rootContentHash: 'root-hash',
    );
    final forked = await coordinator.fork(
      worldTreeId: root.worldTreeId,
      sourceWorldlineId: root.headWorldlineId,
      childConversationId: 'conversation-child',
      branchPointMessageId: 'message-5',
      baseSnapshotId: 'snapshot-5',
    );
    final child = forked.worldlineForConversation('conversation-child')!;

    await expectLater(
      coordinator.archiveWorldline(
        worldTreeId: root.worldTreeId,
        worldlineId: child.id,
      ),
      throwsA(isA<StateError>()),
    );

    final switched = await coordinator.switchHead(
      worldTreeId: root.worldTreeId,
      worldlineId: root.headWorldlineId,
    );
    expect(switched.headWorldlineId, root.headWorldlineId);

    final archived = await coordinator.archiveWorldline(
      worldTreeId: root.worldTreeId,
      worldlineId: child.id,
    );
    expect(
      archived.worldlineById(child.id)!.status,
      StoryWorldlineStatus.archived,
    );
  });
}
