import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../shared/widgets/thinking_sheen.dart';
import '../../../theme/app_font_weights.dart';
import '../../home/controllers/streaming_content_notifier.dart';
import '../interaction/story_action_receipt.dart';
import '../parsing/story_readable_projection.dart';
import 'story_interaction_panel.dart';

class StoryNarrativeView extends StatelessWidget {
  const StoryNarrativeView({
    super.key,
    required this.messages,
    required this.conversationId,
    required this.topPadding,
    required this.bottomPadding,
    required this.streamingContentNotifier,
    required this.isGenerating,
    required this.hasLoadingTools,
    required this.onSubmitIntent,
    required this.onFreeAction,
    this.title,
  });

  final List<ChatMessage> messages;
  final String? conversationId;
  final double topPadding;
  final double bottomPadding;
  final String? title;
  final StreamingContentNotifier streamingContentNotifier;
  final bool isGenerating;
  final bool Function(String messageId) hasLoadingTools;
  final Future<void> Function(
    String text,
    StoryActionSource source,
    String label,
  ) onSubmitIntent;
  final VoidCallback onFreeAction;

  @override
  Widget build(BuildContext context) {
    ChatMessage? streaming;
    ChatMessage? latestAssistant;
    ChatMessage? latestCompletedAssistant;
    ChatMessage? latestUser;

    for (final message in messages.reversed) {
      latestUser ??= message.role == 'user' ? message : null;
      if (message.role != 'assistant') continue;
      latestAssistant ??= message;
      if (!message.isStreaming) latestCompletedAssistant ??= message;
      if (message.isStreaming && streaming == null) streaming = message;
      if (latestUser != null &&
          latestCompletedAssistant != null &&
          streaming != null) {
        break;
      }
    }

    final healthMessage = streaming ?? latestAssistant;
    final healthNotifier = healthMessage != null &&
            streamingContentNotifier.hasHealthNotifier(healthMessage.id)
        ? streamingContentNotifier.getHealthNotifier(healthMessage.id)
        : null;

    Widget buildWithHealth(
      StreamingContentData? streamingData,
      GenerationHealthData? health,
    ) {
      return _buildSurface(
        context,
        streaming: streaming,
        streamingData: streamingData,
        health: health,
        latestCompletedAssistant: latestCompletedAssistant,
        latestUser: latestUser,
      );
    }

    if (streaming == null) {
      if (healthNotifier == null) return buildWithHealth(null, null);
      return ValueListenableBuilder<GenerationHealthData>(
        valueListenable: healthNotifier,
        builder: (context, health, _) => buildWithHealth(null, health),
      );
    }

    final contentNotifier = streamingContentNotifier.getNotifier(streaming.id);
    return ValueListenableBuilder<StreamingContentData>(
      valueListenable: contentNotifier,
      builder: (context, data, _) {
        final liveHealth = streamingContentNotifier.getHealthNotifier(
          streaming!.id,
        );
        return ValueListenableBuilder<GenerationHealthData>(
          valueListenable: liveHealth,
          builder: (context, health, _) => buildWithHealth(data, health),
        );
      },
    );
  }

  Widget _buildSurface(
    BuildContext context, {
    required ChatMessage? streaming,
    required StreamingContentData? streamingData,
    required GenerationHealthData? health,
    required ChatMessage? latestCompletedAssistant,
    required ChatMessage? latestUser,
  }) {
    final entries = <String>[];
    for (final message in messages) {
      if (message.role != 'assistant') continue;
      final raw = message.id == streaming?.id
          ? (streamingData?.content ?? message.content)
          : message.content;
      if (health?.phase == GenerationTransportPhase.failed &&
          message.id == latestCompletedAssistant?.id &&
          health?.errorText?.trim().isNotEmpty == true &&
          raw.trim() == health!.errorText!.trim()) {
        continue;
      }
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
    final failed = health?.phase == GenerationTransportPhase.failed;
    final showStatus = streaming != null || isGenerating || failed;
    final effectiveConversationId =
        conversationId ?? (messages.isEmpty ? null : messages.last.conversationId);
    final pendingUserAction =
        streaming != null &&
            latestUser != null &&
            latestUser.timestamp.isAfter(
              latestCompletedAssistant?.timestamp ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            )
        ? latestUser.content
        : null;
    final showInteraction = effectiveConversationId != null;
    final count =
        entries.length + 1 + (showStatus ? 1 : 0) + (showInteraction ? 1 : 0);

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

        final proseEnd = entries.length;
        if (index <= proseEnd) {
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

        var cursor = proseEnd + 1;
        if (showStatus) {
          if (index == cursor) {
            return _StoryGenerationStatus(
              message: streaming,
              data: streamingData,
              health: health ?? const GenerationHealthData(),
              hasLoadingTools:
                  streaming == null ? false : hasLoadingTools(streaming.id),
            );
          }
          cursor++;
        }

        if (showInteraction && index == cursor) {
          return StoryInteractionPanel(
            conversationId: effectiveConversationId,
            latestAssistantMessageId: latestCompletedAssistant?.id,
            onSubmitIntent: onSubmitIntent,
            onFreeAction: onFreeAction,
            disabled: isGenerating || streaming != null,
            pendingUserAction: pendingUserAction,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _StoryGenerationStatus extends StatefulWidget {
  const _StoryGenerationStatus({
    required this.message,
    required this.data,
    required this.health,
    required this.hasLoadingTools,
  });

  final ChatMessage? message;
  final StreamingContentData? data;
  final GenerationHealthData health;
  final bool hasLoadingTools;

  @override
  State<_StoryGenerationStatus> createState() => _StoryGenerationStatusState();
}

class _StoryGenerationStatusState extends State<_StoryGenerationStatus> {
  Timer? _timer;
  bool _reasoningExpanded = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
    final health = widget.health;
    final now = DateTime.now();
    final healthClass = widget.hasLoadingTools
        ? GenerationHealthClass.working
        : health.classify(now);
    final reasoningActive =
        data?.reasoningStartAt != null && data?.reasoningFinishedAt == null;
    final hasContent = data?.content.trim().isNotEmpty ?? false;
    final reasoning = data?.reasoningText?.trim() ?? '';

    final String headline;
    final Color headlineColor;
    switch (healthClass) {
      case GenerationHealthClass.failed:
        headline = zh ? '请求已失败' : 'Request failed';
        headlineColor = cs.error;
      case GenerationHealthClass.suspectedStall:
        headline = zh ? '连接疑似失活' : 'Connection may be stalled';
        headlineColor = cs.error;
      case GenerationHealthClass.working:
        headline = zh ? '模型仍在工作' : 'Model is still working';
        headlineColor = cs.primary;
      case GenerationHealthClass.terminal:
        headline = zh ? '生成已结束' : 'Generation finished';
        headlineColor = cs.onSurfaceVariant;
    }

    final phase = widget.hasLoadingTools
        ? (health.activeToolName?.trim().isNotEmpty == true
              ? (zh
                    ? '正在调用工具 · ${health.activeToolName}'
                    : 'Using tool · ${health.activeToolName}')
              : (zh ? '正在调用工具' : 'Using tool'))
        : switch (health.phase) {
      GenerationTransportPhase.preparing =>
        zh ? '正在准备上下文' : 'Preparing context',
      GenerationTransportPhase.httpRequest =>
        zh ? 'HTTP 请求中' : 'HTTP request in progress',
      GenerationTransportPhase.sseStreaming =>
        reasoningActive && !hasContent
            ? (zh ? 'SSE 已连接 · 思考中' : 'SSE connected · Thinking')
            : hasContent
            ? (zh ? 'SSE 已连接 · 正在写作' : 'SSE connected · Writing')
            : (zh ? 'SSE 已连接' : 'SSE connected'),
      GenerationTransportPhase.tool =>
        health.activeToolName?.trim().isNotEmpty == true
            ? (zh
                  ? '正在调用工具 · ${health.activeToolName}'
                  : 'Using tool · ${health.activeToolName}')
            : (zh ? '正在调用工具' : 'Using tool'),
      GenerationTransportPhase.retrying =>
        health.retryStatus == null
            ? (zh ? '正在重试' : 'Retrying')
            : (zh
                  ? '重试 ${health.retryStatus!.attempt}/${health.retryStatus!.maxRetries}'
                  : 'Retry ${health.retryStatus!.attempt}/${health.retryStatus!.maxRetries}'),
      GenerationTransportPhase.completed =>
        zh ? '已完成' : 'Completed',
      GenerationTransportPhase.failed =>
        zh ? '生成失败' : 'Failed',
      GenerationTransportPhase.cancelled =>
        zh ? '已取消' : 'Cancelled',
    };

    final startedAt =
        health.requestStartedAt ??
        data?.reasoningStartAt ??
        widget.message?.timestamp ??
        now;
    final elapsed = now.difference(startedAt);

    String seconds(Duration value) =>
        '${(value.inMilliseconds / 1000).clamp(0, 999999).toStringAsFixed(0)}s';

    final networkIdle = health.lastNetworkEventAt == null
        ? null
        : now.difference(health.lastNetworkEventAt!);
    final detail = healthClass == GenerationHealthClass.suspectedStall
        ? _stallDetail(health, now, zh)
        : (zh ? '已进行 ${seconds(elapsed)}' : 'Elapsed ${seconds(elapsed)}');

    final icon = switch (healthClass) {
      GenerationHealthClass.failed => Icons.error_outline_rounded,
      GenerationHealthClass.suspectedStall => Icons.warning_amber_rounded,
      GenerationHealthClass.working => Icons.auto_awesome_rounded,
      GenerationHealthClass.terminal => Icons.check_circle_outline_rounded,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: healthClass == GenerationHealthClass.failed ||
                  healthClass == GenerationHealthClass.suspectedStall
              ? cs.error.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: headlineColor),
                const SizedBox(width: 8),
                ThinkingSheen(
                  enabled: healthClass == GenerationHealthClass.working,
                  color: headlineColor,
                  child: Text(
                    headline,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppFontWeights.semibold,
                      color: headlineColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    phase,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                _TransportDot(
                  label: 'HTTP',
                  active: health.httpOpen,
                ),
                const SizedBox(width: 7),
                _TransportDot(
                  label: 'SSE',
                  active: health.sseOpen,
                ),
              ],
            ),
            if (networkIdle != null &&
                healthClass == GenerationHealthClass.working) ...[
              const SizedBox(height: 5),
              Text(
                zh
                    ? '最近网络事件：${seconds(networkIdle)} 前'
                    : 'Last network event: ${seconds(networkIdle)} ago',
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.82),
                ),
              ),
            ],
            if (healthClass == GenerationHealthClass.failed &&
                health.errorText?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                health.errorText!.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  height: 1.35,
                  fontSize: 12,
                  color: cs.error,
                ),
              ),
            ],
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

String _stallDetail(GenerationHealthData health, DateTime now, bool zh) {
  if (!health.httpOpen) {
    return zh ? 'HTTP 通道已关闭' : 'HTTP channel closed';
  }
  if (health.phase == GenerationTransportPhase.httpRequest) {
    final start = health.requestStartedAt;
    final idle = start == null ? null : now.difference(start);
    if (idle != null) {
      final seconds = idle.inSeconds;
      return zh ? 'HTTP ${seconds}s 无首个响应' : 'No first HTTP response for ${seconds}s';
    }
  }
  final last = health.lastNetworkEventAt;
  if (last != null) {
    final seconds = now.difference(last).inSeconds;
    return zh ? 'SSE ${seconds}s 无新事件' : 'No SSE event for ${seconds}s';
  }
  return zh ? '连接状态异常' : 'Transport state is inconsistent';
}

class _TransportDot extends StatelessWidget {
  const _TransportDot({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: active ? 0.95 : 0.32),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: color.withValues(alpha: active ? 0.9 : 0.7),
          ),
        ),
      ],
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
            zh ? '故事从这里开始。你可以自由行动，也可以在关键节点选择。'
                : 'The story starts here. Act freely or choose at key moments.',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.60)),
          ),
        ],
      ],
    );
  }
}
