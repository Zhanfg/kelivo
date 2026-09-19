import 'package:Kelivo/features/chat/utils/prompt_injection_selection.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/providers/asr_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../features/workspace/widgets/environment/environment_status_chip.dart';
import '../../../features/workspace/workspace_navigation.dart';
import '../../../theme/design_tokens.dart';
import 'chat_input_bar.dart';
import 'model_icon.dart';

/// Callback for checking if a model supports tool calling.
typedef IsToolModelCallback = bool Function(String providerKey, String modelId);

/// Callback for checking if a model supports reasoning.
typedef IsReasoningModelCallback =
    bool Function(String providerKey, String modelId);

/// Callback for checking if reasoning is enabled.
typedef IsReasoningEnabledCallback = bool Function(int? budget);

/// Widget that wraps ChatInputBar with all the necessary logic and callbacks.
///
/// This widget extracts the _buildChatInputBar logic from HomePageState
/// to reduce coupling and improve maintainability.
class ChatInputSection extends StatelessWidget {
  const ChatInputSection({
    super.key,
    required this.inputBarKey,
    this.chatModelProviderKey,
    this.chatModelId,
    this.chatModelIsConversationOverride = false,
    required this.inputFocus,
    required this.inputController,
    required this.mediaController,
    required this.isTablet,
    required this.isLoading,
    this.isGenerationPaused = false,
    this.onToggleGenerationPaused,
    required this.isToolModel,
    required this.isReasoningModel,
    required this.isReasoningEnabled,
    this.onMore,
    this.onSelectModel,
    this.onLongPressSelectModel,
    this.onOpenTools,
    this.onLongPressTools,
    this.onOpenWorkspace,
    this.onOpenSkills,
    this.onOpenSearch,
    this.onConfigureReasoning,
    this.onReasoningBudgetChanged,
    this.onComposerModelChanged,
    this.onSend,
    this.onGuide,
    this.onStop,
    this.hasQueuedInput = false,
    this.queuedPreviewText,
    this.queuedInputs = const <QueuedChatInput>[],
    this.onCancelQueuedInput,
    this.onRemoveQueuedInput,
    this.onClearQueuedInputs,
    this.onReorderQueuedInput,
    this.onQuickPhrase,
    this.onLongPressQuickPhrase,
    this.onToggleOcr,
    this.onOpenMiniMap,
    this.onPickCamera,
    this.onPickPhotos,
    this.onUploadFiles,
    this.onToggleLearningMode,
    this.onOpenWorldBook,
    this.onLongPressLearning,
    this.onClearContext,
    this.onCompressContext,
    this.conversationId,
    this.sendButtonTooltip,
    this.backgroundImageActive = false,
    this.storyMode = false,
  });

  final GlobalKey inputBarKey;
  final FocusNode inputFocus;
  final TextEditingController inputController;
  final ChatInputBarController mediaController;
  final bool isTablet;
  final bool isLoading;
  final bool isGenerationPaused;
  final VoidCallback? onToggleGenerationPaused;

  final IsToolModelCallback isToolModel;
  final IsReasoningModelCallback isReasoningModel;
  final IsReasoningEnabledCallback isReasoningEnabled;

  final VoidCallback? onMore;
  final VoidCallback? onSelectModel;
  final VoidCallback? onLongPressSelectModel;
  final VoidCallback? onOpenTools;
  final VoidCallback? onLongPressTools;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onOpenSkills;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onConfigureReasoning;
  final Future<void> Function(int budget)? onReasoningBudgetChanged;
  final Future<void> Function(String providerKey, String modelId)?
  onComposerModelChanged;
  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;
  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onGuide;
  final VoidCallback? onStop;
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final List<QueuedChatInput> queuedInputs;
  final VoidCallback? onCancelQueuedInput;
  final ValueChanged<int>? onRemoveQueuedInput;
  final VoidCallback? onClearQueuedInputs;
  final void Function(int oldIndex, int newIndex)? onReorderQueuedInput;
  final VoidCallback? onQuickPhrase;
  final VoidCallback? onLongPressQuickPhrase;
  final VoidCallback? onToggleOcr;
  final VoidCallback? onOpenMiniMap;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickPhotos;
  final VoidCallback? onUploadFiles;
  final VoidCallback? onToggleLearningMode;
  final VoidCallback? onOpenWorldBook;
  final VoidCallback? onLongPressLearning;
  final VoidCallback? onClearContext;
  final VoidCallback? onCompressContext;
  final String? conversationId;

  /// The model this conversation sends with, already resolved through
  /// conversation override -> assistant -> global default. Resolved by the
  /// caller because only it holds the Conversation; watching ChatService here
  /// would rebuild the composer on every streaming notification.
  final String? chatModelProviderKey;
  final String? chatModelId;

  /// Whether the resolved model above comes from this conversation's own
  /// override rather than from the assistant.
  ///
  /// Gates the capability enforcement below, which writes to the ASSISTANT: a
  /// model picked for one conversation must not wipe the MCP selection or the
  /// thinking budget shared by every other conversation under that assistant.
  final bool chatModelIsConversationOverride;
  final String? sendButtonTooltip;
  final bool backgroundImageActive;
  final bool storyMode;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final asr = context.watch<AsrProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.currentAssistant;

    final modelIds = getActiveModelIds(settings, assistant: a);
    final pk = modelIds.providerKey;
    final mid = modelIds.modelId;

    _enforceModelCapabilities(context, settings, ap, a, pk, mid);

    final isDesktop = _isDesktopPlatform(context);
    final hasWorldBooks =
        isTablet && context.watch<WorldBookProvider>().books.isNotEmpty;
    final showWorkspaceButton = isDesktop && onOpenWorkspace != null;
    final showEnvChip = !isDesktop && (Platform.isAndroid || Platform.isIOS);
    var workspaceBound = false;
    if (showWorkspaceButton || showEnvChip) {
      workspaceBound = _isWorkspaceBound(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatInputBar(
          key: inputBarKey,
          onMore: onMore,
          onSelectModel: onSelectModel,
          onLongPressSelectModel: onLongPressSelectModel,
          conversationId: conversationId,
          onOpenMcp: onOpenMcp,
          onLongPressMcp: onLongPressMcp,
          onStop: onStop,
          modelIcon: (pk != null && mid != null)
              ? CurrentModelIcon(
                  providerKey: pk,
                  modelId: mid,
                  size: 40,
                  withBackground: true,
                  backgroundColor: Colors.transparent,
                )
              : null,
          focusNode: inputFocus,
          controller: inputController,
          mediaController: mediaController,
          asrProvider: asr,
          onConfigureReasoning: onConfigureReasoning,
          onReasoningBudgetChanged: onReasoningBudgetChanged,
          onComposerModelChanged: onComposerModelChanged,
          currentModelProvider: pk,
          currentModelId: mid,
          supportsXhighReasoning: pk != null && mid != null
              ? settings.supportsXhighReasoning(pk, mid)
              : false,
          supportsMaxReasoning: pk != null && mid != null
              ? settings.supportsMaxReasoning(pk, mid)
              : false,
          reasoningActive: isReasoningEnabled(
            (context
                    .watch<AssistantProvider>()
                    .currentAssistant
                    ?.thinkingBudget) ??
                settings.thinkingBudget,
          ),
          reasoningBudget:
              (context
                  .watch<AssistantProvider>()
                  .currentAssistant
                  ?.thinkingBudget) ??
              settings.thinkingBudget,
          supportsReasoning: (pk != null && mid != null)
              ? isReasoningModel(pk, mid)
              : false,
          onOpenSearch: onOpenSearch,
          onSend: onSend,
          onGuide: onGuide,
          loading: isLoading,
          generationPaused: isGenerationPaused,
          onToggleGenerationPaused: onToggleGenerationPaused,
          sendButtonTooltip: sendButtonTooltip,
          hasQueuedInput: hasQueuedInput,
          queuedPreviewText: queuedPreviewText,
          queuedInputs: queuedInputs,
          onCancelQueuedInput: onCancelQueuedInput,
          onRemoveQueuedInput: onRemoveQueuedInput,
          onClearQueuedInputs: onClearQueuedInputs,
          onReorderQueuedInput: onReorderQueuedInput,
          showMcpButton: _shouldShowMcpButton(context, settings, a, pk, mid),
          mcpActive: _isMcpActive(context, a),
          showQuickPhraseButton: _hasQuickPhrases(context, a),
          onQuickPhrase: onQuickPhrase,
          onLongPressQuickPhrase: onLongPressQuickPhrase,
          showOcrButton: isTablet
              ? (settings.ocrModelProvider != null &&
                    settings.ocrModelId != null)
              : (isDesktop &&
                    settings.ocrModelProvider != null &&
                    settings.ocrModelId != null),
          ocrActive: settings.ocrEnabled,
          onToggleOcr: onToggleOcr,
          showMiniMapButton: isTablet,
          onOpenMiniMap: isTablet ? onOpenMiniMap : null,
          onPickCamera: isTablet ? (isDesktop ? null : onPickCamera) : null,
          onPickPhotos: isTablet ? (isDesktop ? null : onPickPhotos) : null,
          onUploadFiles: isTablet ? onUploadFiles : null,
          onToggleLearningMode: isTablet ? onToggleLearningMode : null,
          onOpenWorldBook: hasWorldBooks ? onOpenWorldBook : null,
          onLongPressLearning: isTablet ? onLongPressLearning : null,
          learningModeActive: isTablet
              ? context
                    .watch<InstructionInjectionProvider>()
                    .activeIdsFor(assistantId)
                    .isNotEmpty
              : false,
          worldBookActive: isTablet
              ? context
                    .watch<WorldBookProvider>()
                    .activeBookIdsFor(assistantId)
                    .isNotEmpty
              : false,
          showMoreButton: !isTablet,
          onClearContext: isTablet ? onClearContext : null,
          onCompressContext: isTablet ? onCompressContext : null,
          backgroundImageActive: backgroundImageActive,
          inputBackgroundOpacityLight: settings.chatInputBackgroundOpacityLight,
          inputBackgroundOpacityDark: settings.chatInputBackgroundOpacityDark,
          storyMode: storyMode,
        ),
      ],
    );

    if (!showEnvChip || !workspaceBound) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showEnvChip && workspaceBound)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xxs,
              AppSpacing.sm,
              0,
            ),
            child: EnvironmentStatusChip(
              onTap: () => WorkspaceNavigation.openEnvironmentPage(context),
            ),
          ),
        bar,
      ],
    );
  }

  bool _isPromptSelectionActive(
    BuildContext context,
    Assistant? assistant,
    PromptSelectionKind kind,
  ) {
    final scoped = assistant?.allowConversationPromptInjection == true;
    if (scoped && conversationId == null) return false;
    final ids = promptSelectionIds(
      context,
      kind: kind,
      assistantId: assistant?.id,
      conversationId: scoped ? conversationId : null,
    ).toSet();
    return kind == PromptSelectionKind.worldBook
        ? context.watch<WorldBookProvider>().books.any(
            (book) => book.enabled && ids.contains(book.id),
          )
        : context.watch<InstructionInjectionProvider>().items.any(
            (item) => ids.contains(item.id),
          );
  }

  bool _isSkillsActive(BuildContext context, Assistant? assistant) {
    final skillIds = context.select<ChatService?, List<String>?>((chat) {
      final extras = chat?.getConversation(conversationId ?? '')?.extras;
      return SkillsBinding.fromExtras(extras ?? const {}).skillIds;
    });
    return context.select<SkillsService?, bool>(
      (skills) =>
          skills
              ?.resolveForAssistant(assistant, conversationOverride: skillIds)
              .isNotEmpty ??
          false,
    );
  }

  bool _isWorkspaceBound(BuildContext context) {
    try {
      return context.select<ChatService, bool>((chat) {
        final id = conversationId;
        if (id == null) return false;
        final conversation = chat.getConversation(id);
        if (conversation == null) return false;
        return WorkspaceBinding.fromExtras(conversation.extras).isBound;
      });
    } catch (_) {
      return false;
    }
  }

  bool _isDesktopPlatform(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  void _enforceModelCapabilities(
    BuildContext context,
    SettingsProvider settings,
    AssistantProvider ap,
    Assistant? a,
    String? pk,
    String? mid,
  ) {
    if (pk == null || mid == null) return;

    final supportsTools = isToolModel(pk, mid);
    if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final aa = ap.currentAssistant;
        if (aa != null && aa.mcpServerIds.isNotEmpty) {
          ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
        }
      });
    }

    final supportsReasoning = isReasoningModel(pk, mid);
    if (!supportsReasoning && a != null) {
      final enabledNow = isReasoningEnabled(
        a.thinkingBudget ?? settings.thinkingBudget,
      );
      if (enabledNow) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final aa = ap.currentAssistant;
          if (aa != null) {
            await ap.updateAssistant(aa.copyWith(thinkingBudget: 0));
          }
        });
      }
    }
  }

  /// The button hosts local tools and the workspace as well as MCP, so it
  /// shows for every tool-capable model rather than only when MCP is set up.
  bool _shouldShowToolsButton(String? pk, String? mid) {
    if (pk == null || mid == null) return false;
    return isToolModel(pk, mid);
  }

  bool _isToolsActive(BuildContext context, Assistant? a, bool workspaceBound) {
    if (workspaceBound) return true;
    if ((a?.localToolIds ?? const <String>[]).isNotEmpty) return true;
    final connected = context.watch<McpProvider>().connectedServers;
    final selected = a?.mcpServerIds ?? const <String>[];
    if (selected.isEmpty || connected.isEmpty) return false;
    return connected.any((s) => selected.contains(s.id));
  }

  bool _hasQuickPhrases(BuildContext context, Assistant? a) {
    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final globalCount = quickPhraseProvider.globalPhrases.length;
    final assistantCount = a != null
        ? quickPhraseProvider.getForAssistant(a.id).length
        : 0;
    return (globalCount + assistantCount) > 0;
  }
}
