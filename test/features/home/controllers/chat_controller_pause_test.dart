import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';

class _FakeChatService extends ChatService {}

void main() {
  test('local pause keeps loading and resumes buffered stream', () async {
    final chat = ChatController(chatService: _FakeChatService());
    const id = 'conversation-a';
    final source = StreamController<int>();
    final received = <int>[];
    final subscription = source.stream.listen(received.add);

    addTearDown(() async {
      await subscription.cancel();
      await source.close();
      chat.dispose();
    });

    chat.setConversationLoading(id, true);
    chat.setStreamSubscription(id, subscription);

    expect(chat.pauseStreamSubscription(id), isTrue);
    expect(chat.isConversationPaused(id), isTrue);
    expect(chat.isConversationLoading(id), isTrue);

    source.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);

    expect(chat.resumeStreamSubscription(id), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(received, <int>[1]);
    expect(chat.isConversationPaused(id), isFalse);

    chat.setConversationLoading(id, false);
    expect(chat.isConversationPaused(id), isFalse);
  });
}
