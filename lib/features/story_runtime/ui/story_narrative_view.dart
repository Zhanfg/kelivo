import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../theme/app_font_weights.dart';
import '../parsing/story_readable_projection.dart';

/// Story mode renders the existing conversation as a reading surface instead
/// of reimplementing message persistence or generation.
class StoryNarrativeView extends StatelessWidget {
  const StoryNarrativeView({
    super.key,
    required this.messages,
    required this.topPadding,
    required this.bottomPadding,
    this.title,
  });

  final List<ChatMessage> messages;
  final double topPadding;
  final double bottomPadding;
  final String? title;

  @override
  Widget build(BuildContext context) {
    // Story is a continuous work, not a Chat transcript. User turns remain
    // authoritative input in Conversation history/runtime, but they are not
    // inserted into the reader-facing prose stream.
    final entries = messages
        .where((message) => message.role == 'assistant')
        .map(
          (message) => projectStoryReadableOrOriginal(
            message.content,
            turnId: message.id,
          ),
        )
        .where((content) => content.trim().isNotEmpty)
        .toList(growable: false);
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final heading = title?.trim();

    return ListView.separated(
      key: const ValueKey<String>('story-narrative-view'),
      padding: EdgeInsets.fromLTRB(24, topPadding + 28, 24, bottomPadding + 28),
      itemCount: entries.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 28 : 20),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _StoryHeading(
            title: heading?.isNotEmpty == true
                ? heading!
                : (zh ? '未命名故事' : 'Untitled story'),
            empty: entries.isEmpty,
          );
        }
        final content = entries[index - 1];
        return Text(
          content,
          style: TextStyle(
            height: 1.78,
            fontSize: 17,
            color: cs.onSurface.withValues(alpha: 0.94),
            fontWeight: AppFontWeights.regular,
          ),
        );
      },
    );
  }
}

class _StoryHeading extends StatelessWidget {
  const _StoryHeading({required this.title, required this.empty});

  final String title;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 28,
            height: 1.18,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface,
          ),
        ),
        if (empty) ...[
          const SizedBox(height: 12),
          Text(
            zh ? '从第一句开始写下这个故事。' : 'Begin this story with its first line.',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.60)),
          ),
        ],
      ],
    );
  }
}
