import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../shared/widgets/thinking_sheen.dart';
import '../../../theme/app_font_weights.dart';
import '../../home/controllers/streaming_content_notifier.dart';
import '../parsing/story_readable_projection.dart';

class StoryNarrativeView extends StatelessWidget {
  const StoryNarrativeView({
    super.key,
    required this.messages,
    required this.topPadding,
    required this.bottomPadding,
    required this.streamingContentNotifier,
    required this.isGenerating,
    required this.hasLoadingTools,
    this.title,
  });

  final List<ChatMessage> messages;
  final double topPadding;
  final double bottomPadding;
  final String? title;
  final StreamingContentNotifier streamingContentNotifier;
  final bool isGenerating;
  final bool Function(String messageId) hasLoadingTools;

  @override
  Widget build(BuildContext context) {
    ChatMessage? streaming;
    for (final message in messages.reversed) {
      if (message.role == 'assistant' && message.isStreaming) {
        streaming = message;
        break;
      }
    }

    if (streaming == null) {
      return _buildSurface(context, null, null);
    }

    final notifier = streamingContentNotifier.getNotifier(streaming.id);
    return ValueListenableBuilder<StreamingContentData>(
      valueListenable: notifier,
      builder: (context, data, _) => _buildSurface(context, streaming, data),
    );
  }

  Widget _buildSurface(
    BuildContext context,
    ChatMessage? streaming,
    StreamingContentData? streamingData,
  ) {
    final entries = <String>[];
    for (final message in messages) {
      if (message.role != 'assistant') continue;
      final raw = message.id == streaming?.id
          ? (streamingData?.content ?? message.content)
          : message.content;
      final projected = projectStoryReadableOrOriginal(
        raw,
        turnId: message.id,
        streaming: message.id == streaming?.id,
      );
      if (projected.trim().isNotEmpty) entries.add(projected);
    }

    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final heading = title?.trim();
    final showStatus = streaming != null || isGenerating;
    final count = entries.length + 1 + (showStatus ? 1 : 0);

    return ListView.separated(
      key: const ValueKey<String>('story-narrative-view'),
      padding: EdgeInsets.fromLTRB(24, topPadding + 28, 24, bottomPadding + 28),
      itemCount: count,
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

        if (index <= entries.length) {
          return Text(
            entries[index - 1],
            style: TextStyle(
              height: 1.78,
              fontSize: 17,
              color: cs.onSurface.withValues(alpha: 0.94),
              fontWeight: AppFontWeights.regular,
            ),
          );
        }

        return _StoryGenerationStatus(
          message: streaming,
          data: streamingData,
          isGenerating: isGenerating,
          hasLoadingTools:
              streaming == null ? false : hasLoadingTools(streaming.id),
        );
      },
    );
  }
}

class _StoryGenerationStatus extends StatefulWidget {
  const _StoryGenerationStatus({
    required this.message,
    required this.data,
    required this.isGenerating,
    required this.hasLoadingTools,
  });

  final ChatMessage? message;
  final StreamingContentData? data;
  final bool isGenerating;
  final bool hasLoadingTools;

  @override
  State<_StoryGenerationStatus> createState() => _StoryGenerationStatusState();
}

class _StoryGenerationStatusState extends State<_StoryGenerationStatus> {
  Timer? _timer;
  DateTime _lastActivityAt = DateTime.now();
  int _fingerprint = 0;
  bool _reasoningExpanded = false;

  @override
  void initState() {
    super.initState();
    _fingerprint = _fingerprintFor(widget.data);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _StoryGenerationStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _fingerprintFor(widget.data);
    if (next != _fingerprint) {
      _fingerprint = next;
      _lastActivityAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final data = widget.data;
    final retry = data?.retryStatus;
    final reasoningActive =
        data?.reasoningStartAt != null && data?.reasoningFinishedAt == null;
    final hasContent = data?.content.trim().isNotEmpty ?? false;
    final hasReasoning = data?.reasoningText?.trim().isNotEmpty ?? false;

    final String label;
    if (retry != null) {
      label = zh ? '正在重试' : 'Retrying';
    } else if (widget.hasLoadingTools) {
      label = zh ? '正在使用工具' : 'Using tools';
    } else if (reasoningActive || (hasReasoning && !hasContent)) {
      label = zh ? '思考中' : 'Thinking';
    } else if (hasContent) {
      label = zh ? '正在写作' : 'Writing';
    } else if (widget.message != null) {
      label = zh ? '等待模型响应' : 'Waiting for model';
    } else {
      label = zh ? '正在准备上下文' : 'Preparing context';
    }

    final startedAt =
        data?.reasoningStartAt ?? widget.message?.timestamp ?? DateTime.now();
    final elapsed = DateTime.now().difference(startedAt);
    final idle = DateTime.now().difference(_lastActivityAt);
    final stalled =
        widget.message != null && idle >= const Duration(seconds: 12);

    String seconds(Duration value) =>
        (value.inMilliseconds / 1000).toStringAsFixed(0) + 's';

    final secondary = stalled
        ? (zh
              ? '${seconds(idle)} 无新流片段，连接仍在等待'
              : 'No new stream chunk for ${seconds(idle)}; still waiting')
        : (zh
              ? '已进行 ${seconds(elapsed)}'
              : 'Elapsed ${seconds(elapsed)}');

    final reasoning = data?.reasoningText?.trim() ?? '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 9),
                ThinkingSheen(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  secondary,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (reasoning.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    setState(() => _reasoningExpanded = !_reasoningExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _reasoningExpanded
                        ? (zh ? '收起模型返回的思考' : 'Hide model reasoning')
                        : (zh ? '查看模型返回的思考' : 'Show model reasoning'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.primary,
                      fontWeight: AppFontWeights.emphasis,
                    ),
                  ),
                ),
              ),
              if (_reasoningExpanded)
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      reasoning,
                      style: TextStyle(
                        height: 1.45,
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ] else if (reasoningActive) ...[
              const SizedBox(height: 7),
              Text(
                zh
                    ? '模型正在推理，但当前提供商没有返回可展示的思考文本。'
                    : 'The model is reasoning, but this provider has not returned displayable reasoning text.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

int _fingerprintFor(StreamingContentData? data) {
  if (data == null) return 0;
  return Object.hash(
    data.content.length,
    data.reasoningText?.length ?? 0,
    data.totalTokens,
    data.toolPartsVersion,
    data.retryStatus,
    data.reasoningFinishedAt,
  );
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
