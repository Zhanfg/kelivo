import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'World Tree state round-trips branch ancestry and checkpoint metadata',
    () {
      final state = StoryWorldTreeState(
        worldTreeId: 'tree',
        name: 'Novel',
        rootContentHash: 'root-hash',
        headWorldlineId: 'child',
        mainlineWorldlineId: 'root',
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
        checkpoints: <StoryWorldCheckpoint>[
          StoryWorldCheckpoint(
            id: 'cp-1',
            worldlineId: 'root',
            messageId: 'message-1',
            nodeId: 'g@0',
            snapshotId: 'snapshot-1',
            label: 'Before choice',
            createdAt: DateTime.utc(2026, 8, 27, 0, 30),
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
      expect(decoded.mainlineWorldlineId, 'root');
      expect(decoded.currentNodeId, 'g@1');
      expect(decoded.worldlineById('child')?.parentWorldlineId, 'root');
      expect(decoded.worldlineById('child')?.branchPointMessageId, 'message-1');
      expect(decoded.checkpointById('cp-1')?.label, 'Before choice');
      expect(decoded.merges.single.targetWorldlineId, 'child');
    },
  );

  test('comparison finds the nearest common ancestor', () {
    final state = StoryWorldTreeState(
      worldTreeId: 'tree',
      name: 'Novel',
      rootContentHash: 'root',
      headWorldlineId: 'left',
      worldlines: <StoryWorldline>[
        StoryWorldline(
          id: 'root',
          conversationId: 'root-c',
          createdAt: DateTime.utc(2026, 8, 27),
        ),
        StoryWorldline(
          id: 'left',
          conversationId: 'left-c',
          parentWorldlineId: 'root',
          createdAt: DateTime.utc(2026, 8, 27, 1),
        ),
        StoryWorldline(
          id: 'right',
          conversationId: 'right-c',
          parentWorldlineId: 'root',
          createdAt: DateTime.utc(2026, 8, 27, 2),
        ),
      ],
    );

    final comparison = state.compare('left', 'right');
    expect(comparison.commonAncestorWorldlineId, 'root');
    expect(comparison.leftAncestry, ['left', 'root']);
    expect(comparison.rightAncestry, ['right', 'root']);
  });

  test('legacy JSON without mainline or checkpoints remains readable', () {
    final decoded = StoryWorldTreeState.fromJson(<String, dynamic>{
      'worldTreeId': 'tree',
      'name': 'Legacy',
      'rootContentHash': 'root',
      'headWorldlineId': 'root-line',
      'worldlines': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'root-line',
          'conversationId': 'c',
          'createdAt': DateTime.utc(2026, 8, 27).toIso8601String(),
          'status': 'active',
          'metadata': <String, dynamic>{},
        },
      ],
    });

    expect(decoded.mainlineWorldlineId, isNull);
    expect(decoded.checkpoints, isEmpty);
  });
}
