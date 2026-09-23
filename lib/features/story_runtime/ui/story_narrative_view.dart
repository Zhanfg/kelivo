import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../parsing/story_readable_projection.dart';

const storyNarrativeViewKey = ValueKey<String>('story-narrative-view');
const storyJumpToLatestKey = ValueKey<String>('story-jump-to-latest');

/// Story mode renders the existing conversation as a reading surface instead
/// of reimplementing message persistence or generation.
///
/// It deliberately shares the home page scroll controller so Story keeps the
/// same auto-follow, conversation-switch positioning, and explicit
/// scroll-to-bottom behavior as Chat while still presenting a reading-first UI.
class StoryNarrativeView extends StatefulWidget {
  const StoryNarrativeView({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.topPadding,
    required this.bottomPadding,
    required this.onJumpToLatest,
    this.onUserScrollIntent,
    this.title,
  });

  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final double topPadding;
  final double bottomPadding;
  final VoidCallback onJumpToLatest;
  final VoidCallback? onUserScrollIntent;
  final String? title;

  @override
  State<StoryNarrativeView> createState() => _StoryNarrativeViewState();
}

class _StoryNarrativeViewState extends State<StoryNarrativeView> {
  static const double _latestButtonTolerance = 24;
  bool _showJumpToLatest = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_syncJumpToLatestVisibility);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncJumpToLatestVisibility(),
    );
  }

  @override
  void didUpdateWidget(covariant StoryNarrativeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scrollController, widget.scrollController)) {
      oldWidget.scrollController.removeListener(_syncJumpToLatestVisibility);
      widget.scrollController.addListener(_syncJumpToLatestVisibility);
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncJumpToLatestVisibility(),
    );
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_syncJumpToLatestVisibility);
    super.dispose();
  }

  void _syncJumpToLatestVisibility() {
    if (!mounted) return;
    final controller = widget.scrollController;
    final next = controller.hasClients
        ? controller.position.maxScrollExtent - controller.position.pixels >
              _latestButtonTolerance
        : false;
    if (next == _showJumpToLatest) return;
    setState(() => _showJumpToLatest = next);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      widget.onUserScrollIntent?.call();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.messages
        .map(
          (message) => (
            message: message,
            content: message.role == 'user'
                ? message.content
                : projectStoryReadableOrOriginal(
                    message.content,
                    turnId: message.id,
                  ),
          ),
        )
        .where((entry) => entry.content.trim().isNotEmpty)
        .toList(growable: false);
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final heading = widget.title?.trim();

    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              widget.onUserScrollIntent?.call();
            }
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: ListView.separated(
              key: storyNarrativeViewKey,
              controller: widget.scrollController,
              padding: EdgeInsets.fromLTRB(
                24,
                widget.topPadding + 28,
                24,
                widget.bottomPadding + 28,
              ),
              itemCount: entries.length + 1,
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 28 : 20),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _StoryHeading(
                    title: heading?.isNotEmpty == true
                        ? heading!
                        : (zh ? '未命名故事' : 'Untitled story'),
                    empty: entries.isEmpty,
                  );
                }
                final entry = entries[index - 1];
                final message = entry.message;
                final content = entry.content;
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
                          content,
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
                  content,
                  style: TextStyle(
                    height: 1.78,
                    fontSize: 17,
                    color: cs.onSurface.withValues(alpha: 0.94),
                    fontWeight: AppFontWeights.regular,
                  ),
                );
              },
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(
                right: 16,
                bottom: widget.bottomPadding + 12,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _showJumpToLatest
                    ? _StoryJumpToLatestButton(
                        key: storyJumpToLatestKey,
                        onTap: widget.onJumpToLatest,
                        semanticLabel: zh ? '回到最新位置' : 'Jump to latest',
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('story-jump-to-latest-hidden'),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryJumpToLatestButton extends StatelessWidget {
  const _StoryJumpToLatestButton({
    super.key,
    required this.onTap,
    required this.semanticLabel,
  });

  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: cs.surface.withValues(alpha: dark ? 0.88 : 0.96),
        elevation: 2,
        shape: CircleBorder(
          side: BorderSide(
            color: cs.outlineVariant.withValues(alpha: dark ? 0.30 : 0.42),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              Lucide.ChevronsDown,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.90),
            ),
          ),
        ),
      ),
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
