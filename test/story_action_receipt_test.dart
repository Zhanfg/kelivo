import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/interaction/story_action_receipt.dart';

void main() {
  test('Story action receipt round-trips source and result state', () {
    final createdAt = DateTime.utc(2026, 9, 22, 1, 2, 3);
    final receipt = StoryActionReceipt(
      id: 'action-1',
      conversationId: 'story-1',
      source: StoryActionSource.formalChoice,
      label: '推开门',
      submitText: '我推开门。',
      createdAt: createdAt,
      status: StoryActionReceiptStatus.resolved,
      resultSummary: '门后是档案室。',
      assistantMessageId: 'assistant-1',
      resolvedAt: createdAt.add(const Duration(seconds: 4)),
    );

    final decoded = StoryActionReceipt.fromJson(receipt.toJson());

    expect(decoded.id, receipt.id);
    expect(decoded.source, StoryActionSource.formalChoice);
    expect(decoded.status, StoryActionReceiptStatus.resolved);
    expect(decoded.resultSummary, '门后是档案室。');
    expect(decoded.assistantMessageId, 'assistant-1');
  });
}
