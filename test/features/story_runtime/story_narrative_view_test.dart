import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/home/controllers/streaming_content_notifier.dart';
import 'package:Kelivo/features/story_runtime/ui/story_narrative_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Story renders only reader-facing prose in the main surface',
    (tester) async {
      final streaming = StreamingContentNotifier();
      addTearDown(streaming.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryNarrativeView(
              title: '雨夜',
              topPadding: 0,
              bottomPadding: 0,
              streamingContentNotifier: streaming,
              isGenerating: false,
              hasLoadingTools: (_) => false,
              onSubmitIntent: (_) async {},
              onFreeAction: () {},
              onSubmitIntent: (_) async {},
              onFreeAction: () {},
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
      expect(find.text('让雨更密一些。'), findsNothing);
      expect(find.text('雨声贴着窗沿落下。'), findsOneWidget);
    },
  );

  testWidgets('Story exposes live reasoning state outside prose', (tester) async {
    final streaming = StreamingContentNotifier();
    addTearDown(streaming.dispose);
    final message = ChatMessage(
      id: 'assistant-stream',
      role: 'assistant',
      content: '',
      conversationId: 'story-2',
      isStreaming: true,
    );
    streaming.getNotifier(message.id);
    streaming.updateReasoning(
      message.id,
      reasoningText: 'checking continuity',
      reasoningStartAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: Scaffold(
          body: StoryNarrativeView(
            title: '测试',
            topPadding: 0,
            bottomPadding: 0,
            streamingContentNotifier: streaming,
            isGenerating: true,
            hasLoadingTools: (_) => false,
              onSubmitIntent: (_) async {},
              onFreeAction: () {},
              onSubmitIntent: (_) async {},
              onFreeAction: () {},
            messages: [message],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('思考中'), findsOneWidget);
    expect(find.text('查看模型返回的思考'), findsOneWidget);
    expect(find.text('checking continuity'), findsNothing);

    await tester.tap(find.text('查看模型返回的思考'));
    await tester.pump();

    expect(find.text('checking continuity'), findsOneWidget);
  });

  testWidgets('Story streams prose once writing begins', (tester) async {
    final streaming = StreamingContentNotifier();
    addTearDown(streaming.dispose);
    final message = ChatMessage(
      id: 'assistant-stream',
      role: 'assistant',
      content: '',
      conversationId: 'story-3',
      isStreaming: true,
    );
    streaming.getNotifier(message.id);
    streaming.updateContent(message.id, '门在雨声里慢慢打开。', 8);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        home: Scaffold(
          body: StoryNarrativeView(
            title: '测试',
            topPadding: 0,
            bottomPadding: 0,
            streamingContentNotifier: streaming,
            isGenerating: true,
            hasLoadingTools: (_) => false,
              onSubmitIntent: (_) async {},
              onFreeAction: () {},
              onSubmitIntent: (_) async {},
              onFreeAction: () {},
            messages: [message],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('门在雨声里慢慢打开。'), findsOneWidget);
    expect(find.text('正在写作'), findsOneWidget);
  });
}
