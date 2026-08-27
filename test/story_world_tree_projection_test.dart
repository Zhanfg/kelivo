import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects Kelivo message revisions without creating a parallel tree', () {
    final conversation = Conversation(
      id: 'c1',
      title: 'Story',
      messageIds: const ['m1', 'm2a', 'm2b', 'm3'],
      versionSelections: const <String, int>{'g2': 0},
    );
    final messages = <ChatMessage>[
      ChatMessage(
        id: 'm1',
        role: 'user',
        content: 'one',
        conversationId: 'c1',
        groupId: 'g1',
        version: 0,
      ),
      ChatMessage(
        id: 'm2a',
        role: 'assistant',
        content: 'two-a',
        conversationId: 'c1',
        groupId: 'g2',
        version: 0,
      ),
      ChatMessage(
        id: 'm2b',
        role: 'assistant',
        content: 'two-b',
        conversationId: 'c1',
        groupId: 'g2',
        version: 1,
      ),
      ChatMessage(
        id: 'm3',
        role: 'user',
        content: 'three',
        conversationId: 'c1',
        groupId: 'g3',
        version: 0,
      ),
    ];

    final projection = StoryWorldTreeProjection.fromKelivoTimeline(
      conversation: conversation,
      messages: messages,
    );

    expect(projection.nodes, hasLength(4));
    expect(projection.selectedPath.map((node) => node.messageId), [
      'm1',
      'm2a',
      'm3',
    ]);
    expect(projection.currentNode?.messageId, 'm3');
    expect(
      projection.nodes.firstWhere((node) => node.messageId == 'm2b').parentNodeId,
      'g1@0',
    );
  });

  test('defaults to highest revision exactly like ChatService timeline', () {
    final conversation = Conversation(id: 'c1', title: 'Story');
    final projection = StoryWorldTreeProjection.fromKelivoTimeline(
      conversation: conversation,
      messages: <ChatMessage>[
        ChatMessage(
          id: 'old',
          role: 'assistant',
          content: 'old',
          conversationId: 'c1',
          groupId: 'g',
          version: 0,
        ),
        ChatMessage(
          id: 'new',
          role: 'assistant',
          content: 'new',
          conversationId: 'c1',
          groupId: 'g',
          version: 2,
        ),
      ],
    );
    expect(projection.currentNode?.messageId, 'new');
  });
}
