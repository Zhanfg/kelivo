import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../models/workspace_mode.dart';
import '../providers/workspace_mode_provider.dart';
import '../../story_runtime/orchestration/story_mode_transition_service.dart';
import '../../story_runtime/ui/story_conversation_mode_control.dart';

/// Stable app-bar mode switcher.
///
/// The previous segmented slider measured global coordinates after layout and
/// animated its thumb between three positions. App-bar width changes, keyboard
/// insets and title/action rebuilds could therefore make the selector appear to
/// "drift". This version has no measured position or moving thumb: the current
/// mode is a fixed-width button and the alternatives live in an anchored menu.
class WorkspaceModeTitle extends StatelessWidget {
  const WorkspaceModeTitle({
    super.key,
    this.availableModes = const <WorkspaceMode>[
      WorkspaceMode.chat,
      WorkspaceMode.story,
      WorkspaceMode.agent,
    ],
    this.compact = false,
  });

  final List<WorkspaceMode> availableModes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkspaceModeProvider>();
    final selected = availableModes.contains(provider.mode)
        ? provider.mode
        : WorkspaceMode.chat;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<WorkspaceMode>(
      tooltip: zh ? '切换模式' : 'Switch mode',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      enabled: !provider.busy,
      initialValue: selected,
      onSelected: (mode) => _switchWorkspaceMode(context, mode),
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 170),
      itemBuilder: (context) => [
        for (final mode in availableModes)
          PopupMenuItem<WorkspaceMode>(
            value: mode,
            child: Row(
              children: [
                Icon(_modeIcon(mode), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _modeLabel(mode, zh),
                    style: TextStyle(
                      fontWeight: mode == selected
                          ? AppFontWeights.semibold
                          : AppFontWeights.medium,
                    ),
                  ),
                ),
                if (mode == selected)
                  Icon(Lucide.Check, size: 17, color: cs.primary),
              ],
            ),
          ),
      ],
      child: _HeaderButton(
        width: 88,
        icon: _modeIcon(selected),
        label: _modeLabel(selected, zh),
        trailing: Lucide.ChevronDown,
        emphasized: true,
      ),
    );
  }
}

/// App-bar header used by Home. Mode and model are two independent fixed
/// anchors, so changing either cannot push the other around.
class WorkspaceModeHeader extends StatelessWidget {
  const WorkspaceModeHeader({
    super.key,
    this.modelDisplay,
    this.providerName,
    this.onSelectModel,
    this.availableModes = const <WorkspaceMode>[
      WorkspaceMode.chat,
      WorkspaceMode.story,
      WorkspaceMode.agent,
    ],
  });

  final String? modelDisplay;
  final String? providerName;
  final VoidCallback? onSelectModel;
  final List<WorkspaceMode> availableModes;

  @override
  Widget build(BuildContext context) {
    final model = modelDisplay?.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkspaceModeTitle(availableModes: availableModes),
        if (model != null && model.isNotEmpty && onSelectModel != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: providerName == null || providerName!.trim().isEmpty
                ? model
                : '$model · $providerName',
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: onSelectModel,
              child: _HeaderButton(
                width: compact ? 112 : 132,
                icon: Lucide.Bot,
                label: model,
                trailing: Lucide.ChevronDown,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.width,
    required this.icon,
    required this.label,
    required this.trailing,
    this.emphasized = false,
  });

  final double width;
  final IconData icon;
  final String label;
  final IconData trailing;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: emphasized
            ? cs.surfaceContainerHighest.withValues(alpha: 0.38)
            : cs.surfaceContainerHigh.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.14),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: cs.onSurface.withValues(alpha: 0.78)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1,
                fontWeight: emphasized
                    ? AppFontWeights.semibold
                    : AppFontWeights.medium,
                color: cs.onSurface.withValues(alpha: 0.90),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Icon(
            trailing,
            size: 14,
            color: cs.onSurface.withValues(alpha: 0.48),
          ),
        ],
      ),
    );
  }
}

Future<void> _switchWorkspaceMode(
  BuildContext context,
  WorkspaceMode mode,
) async {
  final provider = context.read<WorkspaceModeProvider>();
  if (provider.busy || provider.mode == mode) return;

  final preferences = context.read<BusinessPreferences>();
  final chat = context.read<ChatService>();
  final conversationId = chat.currentConversationId;
  if (mode == WorkspaceMode.story && conversationId != null) {
    await StoryModeTransitionService(
      preferences: preferences,
      chatService: chat,
    ).setMode(
      conversationId: conversationId,
      storyEnabled: true,
    );
  }
  await preferences.setBool(
    storyWorkspaceSelectedKey,
    mode == WorkspaceMode.story,
  );
  await provider.setMode(mode);
  storyConversationModeRevision.value++;
  Haptics.light();
}

String _modeLabel(WorkspaceMode mode, bool zh) => switch (mode) {
  WorkspaceMode.chat => zh ? '聊天' : 'Chat',
  WorkspaceMode.story => zh ? '故事' : 'Story',
  WorkspaceMode.agent => zh ? '代理' : 'Agent',
};

IconData _modeIcon(WorkspaceMode mode) => switch (mode) {
  WorkspaceMode.chat => Lucide.MessageCircle,
  WorkspaceMode.story => Lucide.BookOpen,
  WorkspaceMode.agent => Lucide.Bot,
};
