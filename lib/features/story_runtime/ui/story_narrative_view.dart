import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../theme/app_font_weights.dart';

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
    final entries = messages
        .where((message) => message.content.trim().isNotEmpty)
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
        final message = entries[index - 1];
        if (message.role == 'user') {
          return Semantics(
            label: zh ? '创作指令' : 'Writing direction',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Text(
                  message.content,
                  style: TextStyle(
                    height: 1.48,
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ),
          );
        }
        return Text(
          message.content,
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
