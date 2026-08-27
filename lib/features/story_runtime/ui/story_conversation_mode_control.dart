import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';

/// ChatGPT-like initial Chat / Story choice rendered inside Kelivo's native
/// chat header. Once the user commits a choice, or the conversation has real
/// messages, the original Kelivo title is restored.
class StoryConversationModeTitle extends StatefulWidget {
  const StoryConversationModeTitle({
    super.key,
    required this.fallback,
  });

  final Widget fallback;

  @override
  State<StoryConversationModeTitle> createState() =>
      _StoryConversationModeTitleState();
}

class _StoryConversationModeTitleState
    extends State<StoryConversationModeTitle> {
  String? _loadedConversationId;
  Future<StoryRuntimeSessionState>? _sessionFuture;
  bool _busy = false;

  Future<StoryRuntimeSessionState> _futureFor(
    BuildContext context,
    String conversationId,
  ) {
    if (_loadedConversationId != conversationId || _sessionFuture == null) {
      _loadedConversationId = conversationId;
      _sessionFuture = StoryRuntimeStore(
        context.read<BusinessPreferences>(),
      ).readOrDefault(conversationId);
    }
    return _sessionFuture!;
  }

  Future<void> _selectMode(String conversationId, bool story) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = StoryRuntimeStore(context.read<BusinessPreferences>());
      await store.setEnabled(conversationId, story);
      if (!mounted) return;
      setState(() {
        _loadedConversationId = conversationId;
        _sessionFuture = store.readOrDefault(conversationId);
      });
      Haptics.light();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatService>();
    final conversationId = chatService.currentConversationId;
    if (conversationId == null) return widget.fallback;
    final conversation = chatService.getConversation(conversationId);
    if (conversation == null || conversation.messageIds.isNotEmpty) {
      return widget.fallback;
    }

    return FutureBuilder<StoryRuntimeSessionState>(
      future: _futureFor(context, conversationId),
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null || session.modeSelectionCommitted) {
          return widget.fallback;
        }
        return _InitialModeSelector(
          storySelected: session.enabled,
          busy: _busy,
          onSelectChat: () => _selectMode(conversationId, false),
          onSelectStory: () => _selectMode(conversationId, true),
        );
      },
    );
  }
}

/// Compact bidirectional conversion tool shown after the initial selector is
/// gone. It converts the current conversation in-place and never deletes its
/// chat history or Story sidecar state.
class StoryConversationModeAction extends StatefulWidget {
  const StoryConversationModeAction({super.key});

  @override
  State<StoryConversationModeAction> createState() =>
      _StoryConversationModeActionState();
}

class _StoryConversationModeActionState
    extends State<StoryConversationModeAction> {
  String? _loadedConversationId;
  Future<StoryRuntimeSessionState>? _sessionFuture;
  bool _busy = false;

  Future<StoryRuntimeSessionState> _futureFor(
    BuildContext context,
    String conversationId,
  ) {
    if (_loadedConversationId != conversationId || _sessionFuture == null) {
      _loadedConversationId = conversationId;
      _sessionFuture = StoryRuntimeStore(
        context.read<BusinessPreferences>(),
      ).readOrDefault(conversationId);
    }
    return _sessionFuture!;
  }

  Future<void> _convert(
    String conversationId,
    bool story,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = StoryRuntimeStore(context.read<BusinessPreferences>());
      await store.setEnabled(conversationId, story);
      if (!mounted) return;
      setState(() {
        _loadedConversationId = conversationId;
        _sessionFuture = store.readOrDefault(conversationId);
      });
      Haptics.light();
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            story
                ? (zh ? '已转换为故事；原聊天记录已保留。' : 'Converted to Story; chat history was preserved.')
                : (zh ? '已转换为普通聊天；Story 状态已保留，可随时恢复。' : 'Converted to Chat; Story state was preserved for later.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showConversionSheet(
    String conversationId,
    StoryRuntimeSessionState session,
  ) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final targetStory = !session.enabled;
    final actionLabel = targetStory
        ? (zh ? '转换为故事' : 'Convert to Story')
        : (zh ? '转换为普通聊天' : 'Convert to Chat');
    final description = targetStory
        ? (zh
              ? '保留当前聊天历史，并从下一条消息开始启用 Story Runtime、World Tree 与世界线记忆。'
              : 'Keep the current history and enable Story Runtime, World Tree and worldline memory from the next message.')
        : (zh
              ? '停止后续 Story Runtime 注入，但保留 World Tree、世界线记忆和语音绑定；以后转回故事可继续使用。'
              : 'Stop Story Runtime injection while preserving World Tree, worldline memory and voice bindings for later resume.');

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                zh ? '会话模式' : 'Conversation mode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 8),
              IosCardPress(
                borderRadius: BorderRadius.circular(14),
                baseColor: cs.surfaceContainerHighest.withValues(alpha: 0.42),
                padding: EdgeInsets.zero,
                onTap: _busy
                    ? null
                    : () async {
                        Navigator.of(sheetContext).pop();
                        await _convert(conversationId, targetStory);
                      },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    children: [
                      Icon(
                        targetStory ? Lucide.Compass : Lucide.MessageCircle,
                        size: 20,
                        color: cs.onSurface.withValues(alpha: 0.88),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              actionLabel,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: AppFontWeights.medium,
                                color: cs.onSurface.withValues(alpha: 0.92),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: cs.onSurface.withValues(alpha: 0.58),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Lucide.ChevronRight,
                        size: 16,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatService>();
    final conversationId = chatService.currentConversationId;
    if (conversationId == null) return const SizedBox.shrink();
    final conversation = chatService.getConversation(conversationId);
    if (conversation == null) return const SizedBox.shrink();

    return FutureBuilder<StoryRuntimeSessionState>(
      future: _futureFor(context, conversationId),
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null) return const SizedBox.shrink();
        final started = conversation.messageIds.isNotEmpty;
        if (!started && !session.modeSelectionCommitted) {
          return const SizedBox.shrink();
        }
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        final semantic = session.enabled
            ? (zh ? '转换为普通聊天' : 'Convert to Chat')
            : (zh ? '转换为故事' : 'Convert to Story');
        return IosIconButton(
          size: 19,
          minSize: 40,
          padding: const EdgeInsets.all(8),
          icon: Lucide.RefreshCw,
          semanticLabel: semantic,
          onTap: _busy
              ? null
              : () => _showConversionSheet(conversationId, session),
        );
      },
    );
  }
}

class _InitialModeSelector extends StatelessWidget {
  const _InitialModeSelector({
    required this.storySelected,
    required this.busy,
    required this.onSelectChat,
    required this.onSelectStory,
  });

  final bool storySelected;
  final bool busy;
  final VoidCallback onSelectChat;
  final VoidCallback onSelectStory;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.42 : 0.66,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.16),
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeSegment(
              label: zh ? '聊天' : 'Chat',
              selected: !storySelected,
              enabled: !busy,
              onTap: onSelectChat,
            ),
            _ModeSegment(
              label: zh ? '故事' : 'Story',
              selected: storySelected,
              enabled: !busy,
              onTap: onSelectStory,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      borderRadius: BorderRadius.circular(12),
      baseColor: selected ? cs.surface : Colors.transparent,
      padding: EdgeInsets.zero,
      haptics: false,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.06),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            height: 1.05,
            fontWeight: selected
                ? AppFontWeights.semibold
                : AppFontWeights.medium,
            color: cs.onSurface.withValues(alpha: selected ? 0.94 : 0.58),
          ),
        ),
      ),
    );
  }
}
