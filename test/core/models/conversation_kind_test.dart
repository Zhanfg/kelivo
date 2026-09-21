import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/conversation_kind.dart';

void main() {
  test('legacy conversation defaults to Chat ownership', () {
    final conversation = Conversation(title: 'legacy');
    expect(conversationKindOf(conversation), ConversationKind.chat);
  });

  test('conversation kind survives extras projection', () {
    final conversation = Conversation(
      title: 'story',
      extras: conversationExtrasWithKind(
        const <String, dynamic>{'keep': 1},
        ConversationKind.story,
      ),
    );

    expect(conversationKindOf(conversation), ConversationKind.story);
    expect(conversation.extras['keep'], 1);
  });
}
