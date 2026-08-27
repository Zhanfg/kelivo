import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('World Tree state round-trips branch ancestry and merge metadata', () {
    final state = StoryWorldTreeState(
      worldTreeId: 'tree',
      name: 'Novel',
      rootContentHash: 'root-hash',
      headWorldlineId: 'child',
      currentNodeId: 'g@1',
      currentMessageId: 'message-2',
      memoryVersion: 3,
      runtimeStateVersion: 7,
      worldlines: <StoryWorldline>[
        StoryWorldline(
          id: 'root',
          conversationId: 'c-root',
          createdAt: DateTime.utc(2026, 8, 27),
        ),
        StoryWorldline(
          id: 'child',
          conversationId: 'c-child',
          createdAt: DateTime.utc(2026, 8, 27, 1),
          parentWorldlineId: 'root',
          branchPointMessageId: 'message-1',
          baseSnapshotId: 'snapshot-1',
        ),
      ],
      merges: <StoryWorldMergeRecord>[
        StoryWorldMergeRecord(
          id: 'merge',
          sourceWorldlineId: 'old',
          targetWorldlineId: 'child',
          createdAt: DateTime.utc(2026, 8, 27, 2),
        ),
      ],
    );

    final decoded = StoryWorldTreeState.fromJson(state.toJson());
    expect(decoded.worldTreeId, 'tree');
    expect(decoded.headWorldlineId, 'child');
    expect(decoded.currentNodeId, 'g@1');
    expect(decoded.worldlineById('child')?.parentWorldlineId, 'root');
    expect(decoded.worldlineById('child')?.branchPointMessageId, 'message-1');
    expect(decoded.merges.single.targetWorldlineId, 'child');
  });
}
