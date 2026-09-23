import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/story_runtime/ui/story_narrative_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Story can jump back to the latest position after reading history', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var userScrollIntentCount = 0;

    final messages = List<ChatMessage>.generate(
      24,
      (index) => ChatMessage(
        role: index.isEven ? 'assistant' : 'user',
        conversationId: 'story-1',
        content: List<String>.filled(
          8,
          'Story paragraph $index keeps enough text on screen for scrolling.',
        ).join(' '),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryNarrativeView(
            messages: messages,
            scrollController: controller,
            topPadding: 0,
            bottomPadding: 0,
            onUserScrollIntent: () => userScrollIntentCount++,
            onJumpToLatest: () {
              controller.jumpTo(controller.position.maxScrollExtent);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.hasClients, isTrue);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byKey(storyJumpToLatestKey), findsNothing);

    await tester.drag(
      find.byKey(storyNarrativeViewKey),
      const Offset(0, 360),
    );
    await tester.pumpAndSettle();

    expect(userScrollIntentCount, greaterThan(0));
    expect(
      controller.position.maxScrollExtent - controller.position.pixels,
      greaterThan(24),
    );
    expect(find.byKey(storyJumpToLatestKey), findsOneWidget);

    await tester.tap(find.byKey(storyJumpToLatestKey));
    await tester.pumpAndSettle();

    expect(
      controller.position.maxScrollExtent - controller.position.pixels,
      lessThan(1),
    );
    expect(find.byKey(storyJumpToLatestKey), findsNothing);
  });
}
