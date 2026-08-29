import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/story_runtime/ui/story_narrative_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Story renders prose and writing direction without chat bubbles',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryNarrativeView(
              title: '雨夜',
              topPadding: 0,
              bottomPadding: 0,
              messages: [
                ChatMessage(
                  role: 'user',
                  content: '让雨更密一些。',
                  conversationId: 'story-1',
                ),
                ChatMessage(
                  role: 'assistant',
                  content: '雨声贴着窗沿落下。',
                  conversationId: 'story-1',
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('story-narrative-view')),
        findsOneWidget,
      );
      expect(find.text('雨夜'), findsOneWidget);
      expect(find.text('让雨更密一些。'), findsOneWidget);
      expect(find.text('雨声贴着窗沿落下。'), findsOneWidget);
    },
  );
}
