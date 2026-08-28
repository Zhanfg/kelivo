from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def patch_chat_controller() -> None:
    path = Path('lib/features/home/controllers/chat_controller.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        """  final Set<String> _loadingConversationIds = <String>{};\n  Set<String> get loadingConversationIds => _loadingConversationIds;\n\n  /// Active stream subscriptions per conversation.\n""",
        """  final Set<String> _loadingConversationIds = <String>{};\n  Set<String> get loadingConversationIds => _loadingConversationIds;\n\n  /// Conversations whose local stream delivery is paused. This deliberately\n  /// does not claim to pause inference on the remote model provider.\n  final Set<String> _pausedConversationIds = <String>{};\n  Set<String> get pausedConversationIds => _pausedConversationIds;\n\n  bool isConversationPaused(String conversationId) =>\n      _pausedConversationIds.contains(conversationId);\n\n  /// Active stream subscriptions per conversation.\n""",
        'chat-controller/add paused state',
    )
    text = replace_once(
        text,
        """    if (loading) {\n      _loadingConversationIds.add(conversationId);\n    } else {\n      _loadingConversationIds.remove(conversationId);\n    }\n""",
        """    if (loading) {\n      _loadingConversationIds.add(conversationId);\n    } else {\n      _loadingConversationIds.remove(conversationId);\n      _pausedConversationIds.remove(conversationId);\n    }\n""",
        'chat-controller/clear pause with loading',
    )
    text = replace_once(
        text,
        """  void setStreamSubscription(\n    String conversationId,\n    StreamSubscription<dynamic> subscription,\n  ) {\n    _conversationStreams[conversationId] = subscription;\n  }\n\n  /// Cancel and remove a stream subscription.\n  Future<void> cancelStreamSubscription(String conversationId) async {\n    final sub = _conversationStreams.remove(conversationId);\n    await sub?.cancel();\n  }\n\n  /// Cancel all stream subscriptions.\n  Future<void> cancelAllStreams() async {\n    for (final sub in _conversationStreams.values) {\n      await sub.cancel();\n    }\n    _conversationStreams.clear();\n  }\n""",
        """  void setStreamSubscription(\n    String conversationId,\n    StreamSubscription<dynamic> subscription,\n  ) {\n    _conversationStreams[conversationId] = subscription;\n    _pausedConversationIds.remove(conversationId);\n  }\n\n  /// Pause only local delivery of the active stream. The upstream request may\n  /// continue producing data depending on the transport/provider.\n  bool pauseStreamSubscription(String conversationId) {\n    final sub = _conversationStreams[conversationId];\n    if (sub == null || _pausedConversationIds.contains(conversationId)) {\n      return false;\n    }\n    sub.pause();\n    _pausedConversationIds.add(conversationId);\n    notifyListeners();\n    return true;\n  }\n\n  /// Resume local delivery after [pauseStreamSubscription].\n  bool resumeStreamSubscription(String conversationId) {\n    final sub = _conversationStreams[conversationId];\n    if (sub == null || !_pausedConversationIds.remove(conversationId)) {\n      return false;\n    }\n    sub.resume();\n    notifyListeners();\n    return true;\n  }\n\n  bool toggleStreamSubscriptionPaused(String conversationId) =>\n      isConversationPaused(conversationId)\n      ? resumeStreamSubscription(conversationId)\n      : pauseStreamSubscription(conversationId);\n\n  /// Cancel and remove a stream subscription.\n  Future<void> cancelStreamSubscription(String conversationId) async {\n    final sub = _conversationStreams.remove(conversationId);\n    _pausedConversationIds.remove(conversationId);\n    await sub?.cancel();\n  }\n\n  /// Cancel all stream subscriptions.\n  Future<void> cancelAllStreams() async {\n    for (final sub in _conversationStreams.values) {\n      await sub.cancel();\n    }\n    _conversationStreams.clear();\n    _pausedConversationIds.clear();\n  }\n""",
        'chat-controller/pause resume API',
    )
    path.write_text(text, encoding='utf-8')


def patch_home_view_model() -> None:
    path = Path('lib/features/home/controllers/home_view_model.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        """  bool get isCurrentConversationLoading {\n    final cid = currentConversation?.id;\n    if (cid == null) return false;\n    return _chatController.isConversationLoading(cid) &&\n        !_chatActions.isStopping(cid);\n  }\n\n  QueuedChatInput? get currentQueuedInput {\n""",
        """  bool get isCurrentConversationLoading {\n    final cid = currentConversation?.id;\n    if (cid == null) return false;\n    return _chatController.isConversationLoading(cid) &&\n        !_chatActions.isStopping(cid);\n  }\n\n  /// Composer-visible generation state. During Guide handoff we intentionally\n  /// keep this true across cancel -> immediate continuation so the task button\n  /// does not flash through an idle/send state.\n  bool get isCurrentConversationGenerating =>\n      isCurrentConversationLoading || _isGuidingInput;\n\n  bool get isCurrentGenerationPaused {\n    final cid = currentConversation?.id;\n    return cid != null && _chatController.isConversationPaused(cid);\n  }\n\n  bool toggleCurrentGenerationPaused() {\n    final cid = currentConversation?.id;\n    if (cid == null || !_chatController.isConversationLoading(cid)) return false;\n    return _chatController.toggleStreamSubscriptionPaused(cid);\n  }\n\n  QueuedChatInput? get currentQueuedInput {\n""",
        'view-model/expose composer generation state',
    )
    text = replace_once(
        text,
        """    _isGuidingInput = true;\n    try {\n      await _chatActions.cancelStreaming(conversation);\n      final success = await _sendMessageToConversation(input, conversation);\n      return success\n          ? ChatInputSubmissionResult.sent\n          : ChatInputSubmissionResult.rejected;\n    } finally {\n      _isGuidingInput = false;\n      if (!_chatController.isConversationLoading(conversation.id)) {\n        unawaited(_drainQueuedInputIfReady(conversation.id));\n      }\n    }\n""",
        """    if (_chatController.isConversationPaused(conversation.id)) {\n      _chatController.resumeStreamSubscription(conversation.id);\n    }\n    _isGuidingInput = true;\n    notifyListeners();\n    try {\n      // Providers do not expose a universal mid-request instruction channel.\n      // Preserve the partial assistant content, interrupt the current request,\n      // append the guide as a user turn, and immediately continue generation.\n      // The Composer stays in a single visual generating state throughout.\n      await _chatActions.cancelStreaming(conversation);\n      final success = await _sendMessageToConversation(input, conversation);\n      return success\n          ? ChatInputSubmissionResult.sent\n          : ChatInputSubmissionResult.rejected;\n    } finally {\n      _isGuidingInput = false;\n      notifyListeners();\n      if (!_chatController.isConversationLoading(conversation.id)) {\n        unawaited(_drainQueuedInputIfReady(conversation.id));\n      }\n    }\n""",
        'view-model/atomic guide visual state',
    )
    path.write_text(text, encoding='utf-8')


def patch_home_page_controller() -> None:
    path = Path('lib/features/home/controllers/home_page_controller.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        """  bool get isCurrentConversationLoading =>\n      _viewModel.isCurrentConversationLoading;\n\n  QueuedChatInput? get currentQueuedInput => _viewModel.currentQueuedInput;\n""",
        """  bool get isCurrentConversationLoading =>\n      _viewModel.isCurrentConversationLoading;\n  bool get isCurrentConversationGenerating =>\n      _viewModel.isCurrentConversationGenerating;\n  bool get isCurrentGenerationPaused => _viewModel.isCurrentGenerationPaused;\n\n  QueuedChatInput? get currentQueuedInput => _viewModel.currentQueuedInput;\n""",
        'page-controller/expose generation state',
    )
    text = replace_once(
        text,
        """  Future<void> cancelStreaming() async {\n    await _viewModel.cancelStreaming();\n    notifyListeners();\n  }\n""",
        """  void toggleGenerationPaused() {\n    if (_viewModel.toggleCurrentGenerationPaused()) notifyListeners();\n  }\n\n  Future<void> cancelStreaming() async {\n    await _viewModel.cancelStreaming();\n    notifyListeners();\n  }\n""",
        'page-controller/toggle generation pause',
    )
    path.write_text(text, encoding='utf-8')


def patch_chat_input_section() -> None:
    path = Path('lib/features/home/widgets/chat_input_section.dart')
    text = path.read_text(encoding='utf-8')
    text = text.replace("import '../../story_runtime/ui/story_mode_chat_chip.dart';\n", '')
    text = replace_once(
        text,
        """    required this.isLoading,\n    required this.isToolModel,\n""",
        """    required this.isLoading,\n    this.isGenerationPaused = false,\n    this.onToggleGenerationPaused,\n    required this.isToolModel,\n""",
        'input-section/constructor pause',
    )
    text = replace_once(
        text,
        """  final bool isLoading;\n\n  final IsToolModelCallback isToolModel;\n""",
        """  final bool isLoading;\n  final bool isGenerationPaused;\n  final VoidCallback? onToggleGenerationPaused;\n\n  final IsToolModelCallback isToolModel;\n""",
        'input-section/fields pause',
    )
    text = replace_once(
        text,
        """    return Column(\n      mainAxisSize: MainAxisSize.min,\n      children: [\n        StoryModeChatChip(conversationId: conversationId),\n        ChatInputBar(\n""",
        """    return ChatInputBar(\n""",
        'input-section/remove permanent story chip',
    )
    text = replace_once(
        text,
        """          onGuide: onGuide,\n          loading: isLoading,\n          sendButtonTooltip: sendButtonTooltip,\n""",
        """          onGuide: onGuide,\n          loading: isLoading,\n          generationPaused: isGenerationPaused,\n          onToggleGenerationPaused: onToggleGenerationPaused,\n          sendButtonTooltip: sendButtonTooltip,\n""",
        'input-section/pass pause state',
    )
    text = replace_once(
        text,
        """          inputBackgroundOpacityLight: settings.chatInputBackgroundOpacityLight,\n          inputBackgroundOpacityDark: settings.chatInputBackgroundOpacityDark,\n        ),\n      ],\n    );\n""",
        """      inputBackgroundOpacityLight: settings.chatInputBackgroundOpacityLight,\n      inputBackgroundOpacityDark: settings.chatInputBackgroundOpacityDark,\n    );\n""",
        'input-section/close direct composer',
    )
    if 'StoryModeChatChip' in text:
        raise SystemExit('input-section: StoryModeChatChip still present')
    path.write_text(text, encoding='utf-8')


def patch_home_page() -> None:
    path = Path('lib/features/home/pages/home_page.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        """      isTablet: isTablet,\n      isLoading: _controller.isCurrentConversationLoading,\n      isToolModel: _controller.isToolModel,\n""",
        """      isTablet: isTablet,\n      isLoading: _controller.isCurrentConversationGenerating,\n      isGenerationPaused: _controller.isCurrentGenerationPaused,\n      onToggleGenerationPaused: _controller.toggleGenerationPaused,\n      isToolModel: _controller.isToolModel,\n""",
        'home-page/pass visual generation state',
    )
    path.write_text(text, encoding='utf-8')


def patch_lucide() -> None:
    path = Path('lib/icons/lucide_adapter.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        """  static const IconData Play = lucide.LucideIcons.play;\n""",
        """  static const IconData Play = lucide.LucideIcons.play;\n  static const IconData Pause = lucide.LucideIcons.pause;\n""",
        'lucide/pause alias',
    )
    path.write_text(text, encoding='utf-8')


def patch_chat_input_bar() -> None:
    path = Path('lib/features/home/widgets/chat_input_bar.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        """    this.loading = false,\n    this.onGuide,\n""",
        """    this.loading = false,\n    this.generationPaused = false,\n    this.onToggleGenerationPaused,\n    this.onGuide,\n""",
        'input-bar/constructor pause',
    )
    text = replace_once(
        text,
        """  final bool loading;\n  final bool hasQueuedInput;\n""",
        """  final bool loading;\n  final bool generationPaused;\n  final VoidCallback? onToggleGenerationPaused;\n  final bool hasQueuedInput;\n""",
        'input-bar/fields pause',
    )
    # Move queue status inside the frosted Composer shell.
    old_outer = """            if (widget.hasQueuedInput) ...[\n              _QueuedInputBanner(\n                label: widget.queuedInputs.length > 1\n                    ? '${AppLocalizations.of(context)!.chatInputBarQueuedPending} · ${widget.queuedInputs.length}'\n                    : AppLocalizations.of(context)!.chatInputBarQueuedPending,\n                previewText: widget.queuedPreviewText,\n                cancelLabel: AppLocalizations.of(\n                  context,\n                )!.chatInputBarQueuedCancel,\n                onCancel: widget.onCancelQueuedInput,\n                onManage: widget.queuedInputs.isEmpty\n                    ? null\n                    : () => unawaited(_showQueueManager()),\n              ),\n              const SizedBox(height: AppSpacing.xs),\n            ],\n            Stack(\n"""
    text = replace_once(text, old_outer, """            Stack(\n""", 'input-bar/remove external queue banner')
    text = replace_once(
        text,
        """                      child: Column(\n                        children: [\n                          if (hasDocs || hasImages)\n                            _buildInlineAttachmentPreviews(context, isDark),\n""",
        """                      child: Column(\n                        children: [\n                          if (widget.hasQueuedInput)\n                            Padding(\n                              padding: const EdgeInsets.fromLTRB(\n                                AppSpacing.xs,\n                                AppSpacing.xs,\n                                AppSpacing.xs,\n                                2,\n                              ),\n                              child: Align(\n                                alignment: Alignment.centerLeft,\n                                child: _ComposerQueueChip(\n                                  label: widget.queuedInputs.length > 1\n                                      ? '${AppLocalizations.of(context)!.chatInputBarQueuedPending} · ${widget.queuedInputs.length}'\n                                      : AppLocalizations.of(context)!.chatInputBarQueuedPending,\n                                  onTap: widget.queuedInputs.isEmpty\n                                      ? null\n                                      : () => unawaited(_showQueueManager()),\n                                  onCancel: widget.onCancelQueuedInput,\n                                ),\n                              ),\n                            ),\n                          if (showGenerationDraftActions)\n                            Padding(\n                              key: const ValueKey('composer-generation-actions'),\n                              padding: const EdgeInsets.fromLTRB(\n                                AppSpacing.xs,\n                                2,\n                                AppSpacing.xs,\n                                4,\n                              ),\n                              child: Row(\n                                mainAxisAlignment: MainAxisAlignment.end,\n                                children: [\n                                  _CompactActionPill(\n                                    label: Localizations.localeOf(context).languageCode == 'zh'\n                                        ? '加入队列'\n                                        : 'Queue',\n                                    icon: Lucide.ListOrdered,\n                                    onTap: _handleSend,\n                                  ),\n                                  const SizedBox(width: 4),\n                                  _CompactActionPill(\n                                    label: Localizations.localeOf(context).languageCode == 'zh'\n                                        ? '立即引导'\n                                        : 'Guide',\n                                    icon: Lucide.MessageCirclePlus,\n                                    onTap: widget.onGuide == null ? null : _handleGuide,\n                                  ),\n                                ],\n                              ),\n                            ),\n                          if (hasDocs || hasImages)\n                            _buildInlineAttachmentPreviews(context, isDark),\n""",
        'input-bar/insert attached generation actions',
    )
    text = text.replace("if (isMobileLayout &&\n                                                !showGenerationDraftActions) ...[", "if (isMobileLayout) ...[")
    text = text.replace("if (showVoiceInput &&\n                                                !showGenerationDraftActions) ...[", "if (showVoiceInput) ...[")
    old_bottom = """                                            if (showGenerationDraftActions) ...[\n                                              _CompactActionPill(\n                                                label:\n                                                    Localizations.localeOf(\n                                                          context,\n                                                        ).languageCode ==\n                                                        'zh'\n                                                    ? '加入队列'\n                                                    : 'Queue',\n                                                icon: Lucide.ListOrdered,\n                                                onTap: _handleSend,\n                                              ),\n                                              const SizedBox(width: 6),\n                                              _CompactActionPill(\n                                                label:\n                                                    Localizations.localeOf(\n                                                          context,\n                                                        ).languageCode ==\n                                                        'zh'\n                                                    ? '立即引导'\n                                                    : 'Guide',\n                                                icon: Lucide.MessageCirclePlus,\n                                                onTap: widget.onGuide == null\n                                                    ? null\n                                                    : _handleGuide,\n                                              ),\n                                              const SizedBox(width: 6),\n                                            ],\n"""
    text = replace_once(text, old_bottom, '', 'input-bar/remove bottom queue guide')
    text = replace_once(
        text,
        """                                              loading: widget.loading,\n                                              onSend: _handleSend,\n                                              onStop: widget.loading\n                                                  ? widget.onStop\n                                                  : null,\n                                              color: theme.colorScheme.primary,\n""",
        """                                              loading: widget.loading,\n                                              paused: widget.generationPaused,\n                                              onSend: _handleSend,\n                                              onToggleGeneration:\n                                                  widget.onToggleGenerationPaused,\n                                              color: theme.colorScheme.primary,\n""",
        'input-bar/task uses pause resume',
    )
    # Replace old external banner widget with compact in-shell queue chip.
    start = text.index('class _QueuedInputBanner extends StatelessWidget {')
    end = text.index('\nclass _QueueManagerSheet', start)
    replacement = r'''class _ComposerQueueChip extends StatelessWidget {
  const _ComposerQueueChip({
    required this.label,
    this.onTap,
    this.onCancel,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('composer-queue-chip'),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: const EdgeInsets.only(left: 9, right: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Lucide.ListOrdered, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onCancel != null) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    key: const ValueKey('composer-queue-cancel'),
                    tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                    onPressed: onCancel,
                    icon: Icon(Lucide.X, size: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
'''
    text = text[:start] + replacement + text[end:]
    text = replace_once(
        text,
        """    this.loading = false,\n    this.onStop,\n    this.tooltip,\n  });\n\n  final bool enabled;\n  final bool loading;\n  final VoidCallback onSend;\n  final VoidCallback? onStop;\n""",
        """    this.loading = false,\n    this.paused = false,\n    this.onToggleGeneration,\n    this.tooltip,\n  });\n\n  final bool enabled;\n  final bool loading;\n  final bool paused;\n  final VoidCallback onSend;\n  final VoidCallback? onToggleGeneration;\n""",
        'compact-task/fields',
    )
    text = replace_once(
        text,
        """        onTap: loading ? onStop : (enabled ? onSend : null),\n""",
        """        onTap: loading ? onToggleGeneration : (enabled ? onSend : null),\n""",
        'compact-task/tap',
    )
    old_icon = """            child: loading\n                ? SvgPicture.asset(\n                    key: const ValueKey('stop'),\n                    'assets/icons/stop.svg',\n                    width: 18,\n                    height: 18,\n                    colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),\n                  )\n                : Icon(icon, key: const ValueKey('send'), size: 18, color: fg),\n"""
    new_icon = """            child: loading\n                ? Icon(\n                    paused ? Lucide.Play : Lucide.Pause,\n                    key: ValueKey(paused ? 'resume' : 'pause'),\n                    size: 18,\n                    color: fg,\n                  )\n                : Icon(icon, key: const ValueKey('send'), size: 18, color: fg),\n"""
    text = replace_once(text, old_icon, new_icon, 'compact-task/pause resume icon')
    path.write_text(text, encoding='utf-8')


def patch_queue_tests() -> None:
    path = Path('test/features/home/widgets/chat_input_bar_queue_test.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        """    bool loading = false,\n    bool hasQueuedInput = false,\n""",
        """    bool loading = false,\n    bool generationPaused = false,\n    VoidCallback? onToggleGenerationPaused,\n    bool hasQueuedInput = false,\n""",
        'queue-test/harness args',
    )
    text = replace_once(
        text,
        """            loading: loading,\n            hasQueuedInput: hasQueuedInput,\n""",
        """            loading: loading,\n            generationPaused: generationPaused,\n            onToggleGenerationPaused: onToggleGenerationPaused,\n            hasQueuedInput: hasQueuedInput,\n""",
        'queue-test/harness pass',
    )
    marker = """  testWidgets('多项队列可打开管理面板并删除', (tester) async {\n"""
    new_tests = r'''  testWidgets('生成草稿操作附着在文本上方且底栏保留推理入口', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController(text: 'change direction');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        loading: true,
        onToggleGenerationPaused: () {},
        onSend: (_) async => ChatInputSubmissionResult.queued,
        onGuide: (_) async => ChatInputSubmissionResult.sent,
      ),
    );
    await tester.pump();

    final attached = find.byKey(const ValueKey('composer-generation-actions'));
    expect(attached, findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Guide'), findsOneWidget);
    expect(find.byTooltip('Reasoning strength'), findsOneWidget);
    expect(
      tester.getTopLeft(attached).dy,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );

    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('生成主按钮切换 Pause 和 Resume 而不是 Stop', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var toggles = 0;

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        loading: true,
        onToggleGenerationPaused: () => toggles++,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );
    expect(find.byKey(const ValueKey('pause')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pause')));
    await tester.pump();
    expect(toggles, 1);

    await tester.pumpWidget(
      buildHarness(
        controller: controller,
        focusNode: focusNode,
        loading: true,
        generationPaused: true,
        onToggleGenerationPaused: () => toggles++,
        onSend: (_) async => ChatInputSubmissionResult.rejected,
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('resume')), findsOneWidget);

    controller.dispose();
    focusNode.dispose();
  });

'''
    if marker not in text:
        raise SystemExit('queue-test insertion marker missing')
    text = text.replace(marker, new_tests + marker, 1)
    # Old banner-specific expectations are obsolete: queue status is now a compact in-shell chip.
    text = text.replace("    expect(find.text('Cancel Queue'), findsOneWidget);\n    expect(find.text(preview), findsOneWidget);\n\n    final previewText = tester.widget<Text>(find.text(preview));\n    expect(previewText.maxLines, 3);\n    expect(previewText.overflow, TextOverflow.ellipsis);\n\n    await tester.tap(find.text('Cancel Queue'));\n", "    expect(find.byKey(const ValueKey('composer-queue-chip')), findsOneWidget);\n    expect(find.text(preview), findsNothing);\n\n    await tester.tap(find.byKey(const ValueKey('composer-queue-cancel')));\n")
    path.write_text(text, encoding='utf-8')


def create_pause_test() -> None:
    path = Path('test/features/home/controllers/chat_controller_pause_test.dart')
    if path.exists():
        raise SystemExit('pause test already exists')
    path.write_text(r'''import 'dart:async';

import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeChatService extends ChatService {}

void main() {
  test('local pause keeps conversation loading and resumes buffered stream', () async {
    final chat = ChatController(chatService: _FakeChatService());
    const id = 'conversation-a';
    final source = StreamController<int>();
    final received = <int>[];
    final subscription = source.stream.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      await source.close();
    });

    chat.setConversationLoading(id, true);
    chat.setStreamSubscription(id, subscription);
    expect(chat.pauseStreamSubscription(id), isTrue);
    expect(chat.isConversationPaused(id), isTrue);
    expect(chat.loadingConversationIds, contains(id));

    source.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);
    expect(chat.resumeStreamSubscription(id), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(received, <int>[1]);
    expect(chat.isConversationPaused(id), isFalse);
    expect(chat.loadingConversationIds, contains(id));

    chat.setConversationLoading(id, false);
    expect(chat.isConversationPaused(id), isFalse);
  });
}
''', encoding='utf-8')


patch_chat_controller()
patch_home_view_model()
patch_home_page_controller()
patch_chat_input_section()
patch_home_page()
patch_lucide()
patch_chat_input_bar()
patch_queue_tests()
create_pause_test()
print('Composer v8 phase 1 generation geometry applied successfully')
