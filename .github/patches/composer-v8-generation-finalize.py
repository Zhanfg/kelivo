from pathlib import Path
import re


def fail(label, detail):
    raise SystemExit(f"{label}: {detail}")


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        fail(label, f"expected exactly one literal match, found {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def regex_once(path, pattern, repl, label, flags=0):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    new_text, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        fail(label, f"expected exactly one regex match, found {count}")
    p.write_text(new_text, encoding="utf-8")


def patch_chat_controller():
    path = "lib/features/home/controllers/chat_controller.dart"
    replace_once(
        path,
        """  final Set<String> _loadingConversationIds = <String>{};
  Set<String> get loadingConversationIds => _loadingConversationIds;

  /// Active stream subscriptions per conversation.
""",
        """  final Set<String> _loadingConversationIds = <String>{};
  Set<String> get loadingConversationIds => _loadingConversationIds;

  /// Conversations whose local stream delivery is paused.
  ///
  /// This is intentionally a transport-consumer pause. Providers do not expose
  /// a universal upstream inference pause, so this must not be treated as a
  /// token-saving remote pause.
  final Set<String> _pausedConversationIds = <String>{};
  Set<String> get pausedConversationIds => _pausedConversationIds;

  bool isConversationPaused(String conversationId) =>
      _pausedConversationIds.contains(conversationId);

  /// Active stream subscriptions per conversation.
""",
        "chat-controller/add-paused-state",
    )
    replace_once(
        path,
        """    } else {
      _loadingConversationIds.remove(conversationId);
    }
    if (prev != loading) {
""",
        """    } else {
      _loadingConversationIds.remove(conversationId);
      _pausedConversationIds.remove(conversationId);
    }
    if (prev != loading) {
""",
        "chat-controller/clear-pause-on-terminal",
    )
    replace_once(
        path,
        """  /// Set a stream subscription for a conversation.
  void setStreamSubscription(
    String conversationId,
    StreamSubscription<dynamic> subscription,
  ) {
    _conversationStreams[conversationId] = subscription;
  }

  /// Cancel and remove a stream subscription.
  Future<void> cancelStreamSubscription(String conversationId) async {
    final sub = _conversationStreams.remove(conversationId);
    await sub?.cancel();
  }

  /// Cancel all stream subscriptions.
  Future<void> cancelAllStreams() async {
    for (final sub in _conversationStreams.values) {
      await sub.cancel();
    }
    _conversationStreams.clear();
  }
""",
        """  /// Set a stream subscription for a conversation.
  void setStreamSubscription(
    String conversationId,
    StreamSubscription<dynamic> subscription,
  ) {
    _conversationStreams[conversationId] = subscription;
    _pausedConversationIds.remove(conversationId);
  }

  /// Pause local delivery of the active stream.
  ///
  /// The provider request may continue producing data while the Dart
  /// subscription is paused; buffered events are delivered on resume.
  bool pauseStreamSubscription(String conversationId) {
    final sub = _conversationStreams[conversationId];
    if (sub == null || _pausedConversationIds.contains(conversationId)) {
      return false;
    }
    sub.pause();
    _pausedConversationIds.add(conversationId);
    notifyListeners();
    return true;
  }

  bool resumeStreamSubscription(String conversationId) {
    final sub = _conversationStreams[conversationId];
    if (sub == null || !_pausedConversationIds.remove(conversationId)) {
      return false;
    }
    sub.resume();
    notifyListeners();
    return true;
  }

  bool toggleStreamSubscriptionPaused(String conversationId) =>
      isConversationPaused(conversationId)
      ? resumeStreamSubscription(conversationId)
      : pauseStreamSubscription(conversationId);

  /// Cancel and remove a stream subscription.
  Future<void> cancelStreamSubscription(String conversationId) async {
    final sub = _conversationStreams.remove(conversationId);
    _pausedConversationIds.remove(conversationId);
    await sub?.cancel();
  }

  /// Cancel all stream subscriptions.
  Future<void> cancelAllStreams() async {
    for (final sub in _conversationStreams.values) {
      await sub.cancel();
    }
    _conversationStreams.clear();
    _pausedConversationIds.clear();
  }
""",
        "chat-controller/pause-resume-api",
    )


def patch_home_view_model():
    path = "lib/features/home/controllers/home_view_model.dart"
    replace_once(
        path,
        """  bool get isCurrentConversationLoading {
    final cid = currentConversation?.id;
    if (cid == null) return false;
    return _chatController.isConversationLoading(cid) &&
        !_chatActions.isStopping(cid);
  }

  QueuedChatInput? get currentQueuedInput {
""",
        """  bool get isCurrentConversationLoading {
    final cid = currentConversation?.id;
    if (cid == null) return false;
    return _chatController.isConversationLoading(cid) &&
        !_chatActions.isStopping(cid);
  }

  /// Composer-visible generation state. Guide handoff remains visually
  /// generating across cancel -> immediate continuation.
  bool get isCurrentConversationGenerating =>
      isCurrentConversationLoading || _isGuidingInput;

  bool get isCurrentGenerationPaused {
    final cid = currentConversation?.id;
    return cid != null && _chatController.isConversationPaused(cid);
  }

  bool toggleCurrentGenerationPaused() {
    final cid = currentConversation?.id;
    if (cid == null || !_chatController.isConversationLoading(cid)) {
      return false;
    }
    return _chatController.toggleStreamSubscriptionPaused(cid);
  }

  QueuedChatInput? get currentQueuedInput {
""",
        "home-view-model/generation-state",
    )
    replace_once(
        path,
        """    _isGuidingInput = true;
    try {
      await _chatActions.cancelStreaming(conversation);
      final success = await _sendMessageToConversation(input, conversation);
      return success
          ? ChatInputSubmissionResult.sent
          : ChatInputSubmissionResult.rejected;
    } finally {
      _isGuidingInput = false;
      if (!_chatController.isConversationLoading(conversation.id)) {
        unawaited(_drainQueuedInputIfReady(conversation.id));
      }
    }
""",
        """    if (_chatController.isConversationPaused(conversation.id)) {
      _chatController.resumeStreamSubscription(conversation.id);
    }
    _isGuidingInput = true;
    notifyListeners();
    try {
      // No provider-independent mid-request instruction channel exists here.
      // Keep already streamed assistant content, terminate the active request,
      // append the guide as a user turn, and immediately continue generation.
      // The Composer remains in one visual generating state for the handoff.
      await _chatActions.cancelStreaming(conversation);
      final success = await _sendMessageToConversation(input, conversation);
      return success
          ? ChatInputSubmissionResult.sent
          : ChatInputSubmissionResult.rejected;
    } finally {
      _isGuidingInput = false;
      notifyListeners();
      if (!_chatController.isConversationLoading(conversation.id)) {
        unawaited(_drainQueuedInputIfReady(conversation.id));
      }
    }
""",
        "home-view-model/guide-continuous-state",
    )


def patch_home_page_controller():
    path = "lib/features/home/controllers/home_page_controller.dart"
    replace_once(
        path,
        """  bool get isCurrentConversationLoading =>
      _viewModel.isCurrentConversationLoading;

  QueuedChatInput? get currentQueuedInput => _viewModel.currentQueuedInput;
""",
        """  bool get isCurrentConversationLoading =>
      _viewModel.isCurrentConversationLoading;
  bool get isCurrentConversationGenerating =>
      _viewModel.isCurrentConversationGenerating;
  bool get isCurrentGenerationPaused => _viewModel.isCurrentGenerationPaused;

  QueuedChatInput? get currentQueuedInput => _viewModel.currentQueuedInput;
""",
        "home-page-controller/getters",
    )
    replace_once(
        path,
        """  Future<void> cancelStreaming() async {
    await _viewModel.cancelStreaming();
    notifyListeners();
  }
""",
        """  void toggleGenerationPaused() {
    if (_viewModel.toggleCurrentGenerationPaused()) {
      notifyListeners();
    }
  }

  Future<void> cancelStreaming() async {
    await _viewModel.cancelStreaming();
    notifyListeners();
  }
""",
        "home-page-controller/toggle-pause",
    )


def patch_home_page():
    path = "lib/features/home/pages/home_page.dart"
    replace_once(
        path,
        """      isTablet: isTablet,
      isLoading: _controller.isCurrentConversationLoading,
      isToolModel: _controller.isToolModel,
""",
        """      isTablet: isTablet,
      isLoading: _controller.isCurrentConversationGenerating,
      isGenerationPaused: _controller.isCurrentGenerationPaused,
      onToggleGenerationPaused: _controller.toggleGenerationPaused,
      isToolModel: _controller.isToolModel,
""",
        "home-page/pass-generation-state",
    )


def patch_input_section():
    path = "lib/features/home/widgets/chat_input_section.dart"
    replace_once(
        path,
        """    required this.isTablet,
    required this.isLoading,
    required this.isToolModel,
""",
        """    required this.isTablet,
    required this.isLoading,
    this.isGenerationPaused = false,
    this.onToggleGenerationPaused,
    required this.isToolModel,
""",
        "input-section/constructor",
    )
    replace_once(
        path,
        """  final bool isTablet;
  final bool isLoading;

  final IsToolModelCallback isToolModel;
""",
        """  final bool isTablet;
  final bool isLoading;
  final bool isGenerationPaused;
  final VoidCallback? onToggleGenerationPaused;

  final IsToolModelCallback isToolModel;
""",
        "input-section/fields",
    )
    replace_once(
        path,
        """          onGuide: onGuide,
          loading: isLoading,
          sendButtonTooltip: sendButtonTooltip,
""",
        """          onGuide: onGuide,
          loading: isLoading,
          generationPaused: isGenerationPaused,
          onToggleGenerationPaused: onToggleGenerationPaused,
          sendButtonTooltip: sendButtonTooltip,
""",
        "input-section/pass",
    )


def patch_lucide():
    path = "lib/icons/lucide_adapter.dart"
    replace_once(
        path,
        "  static const IconData Play = lucide.LucideIcons.play;\n",
        "  static const IconData Play = lucide.LucideIcons.play;\n"
        "  static const IconData Pause = lucide.LucideIcons.pause;\n",
        "lucide/pause",
    )


def patch_input_bar():
    path = "lib/features/home/widgets/chat_input_bar.dart"
    replace_once(
        path,
        """    this.asrProvider,
    this.loading = false,
    this.onGuide,
""",
        """    this.asrProvider,
    this.loading = false,
    this.generationPaused = false,
    this.onToggleGenerationPaused,
    this.onGuide,
""",
        "input-bar/constructor",
    )
    replace_once(
        path,
        """  final AsrProvider? asrProvider;
  final bool loading;
  final bool hasQueuedInput;
""",
        """  final AsrProvider? asrProvider;
  final bool loading;
  final bool generationPaused;
  final VoidCallback? onToggleGenerationPaused;
  final bool hasQueuedInput;
""",
        "input-bar/fields",
    )

    marker = """                          if (hasDocs || hasImages)
                            _buildInlineAttachmentPreviews(context, isDark),
                          // Input field with expand/collapse button
"""
    insertion = """                          if (showGenerationDraftActions)
                            Padding(
                              key: const ValueKey('composer-generation-actions'),
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.xs,
                                0,
                                AppSpacing.xs,
                                AppSpacing.xs,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _CompactActionPill(
                                    label:
                                        Localizations.localeOf(context)
                                                .languageCode ==
                                            'zh'
                                        ? '加入队列'
                                        : 'Queue',
                                    icon: Lucide.ListOrdered,
                                    onTap: _handleSend,
                                  ),
                                  const SizedBox(width: 6),
                                  _CompactActionPill(
                                    label:
                                        Localizations.localeOf(context)
                                                .languageCode ==
                                            'zh'
                                        ? '立即引导'
                                        : 'Guide',
                                    icon: Lucide.MessageCirclePlus,
                                    onTap: widget.onGuide == null
                                        ? null
                                        : _handleGuide,
                                  ),
                                ],
                              ),
                            ),
                          if (hasDocs || hasImages)
                            _buildInlineAttachmentPreviews(context, isDark),
                          // Input field with expand/collapse button
"""
    replace_once(path, marker, insertion, "input-bar/attach-queue-guide")

    p = Path(path)
    text = p.read_text(encoding="utf-8")
    old = """                                            if (isMobileLayout &&
                                                !showGenerationDraftActions) ...["""
    if old not in text:
        fail("input-bar/reasoning-visible", "condition not found")
    text = text.replace(old, """                                            if (isMobileLayout) ...[""", 1)
    old = """                                            if (showVoiceInput &&
                                                !showGenerationDraftActions) ...["""
    if old not in text:
        fail("input-bar/mic-visible", "condition not found")
    text = text.replace(old, """                                            if (showVoiceInput) ...[""", 1)
    p.write_text(text, encoding="utf-8")

    replace_once(
        path,
        """                                                      child: _CompactIconButton(
                                                        tooltip:
""",
        """                                                      child: _CompactIconButton(
                                                        key: const ValueKey(
                                                          'composer-reasoning-button',
                                                        ),
                                                        tooltip:
""",
        "input-bar/reasoning-key",
    )

    regex_once(
        path,
        r"""(?ms)^\s{44}if \(showGenerationDraftActions\) \.\.\.\[\n.*?^\s{44}\],\n""",
        "",
        "input-bar/remove-bottom-queue-guide",
    )

    replace_once(
        path,
        """                                              loading: widget.loading,
                                              onSend: _handleSend,
                                              onStop: widget.loading
                                                  ? widget.onStop
                                                  : null,
                                              color: theme.colorScheme.primary,
""",
        """                                              loading: widget.loading,
                                              paused: widget.generationPaused,
                                              onSend: _handleSend,
                                              onTogglePaused:
                                                  widget.onToggleGenerationPaused,
                                              color: theme.colorScheme.primary,
""",
        "input-bar/primary-pause-resume",
    )

    regex_once(
        path,
        r"""(?ms)// New compact send button for the integrated input bar\nclass _CompactSendButton extends StatelessWidget \{.*?\n\}\n\n// Scrolling waveform driven by real mic amplitude samples""",
        """// Primary Composer task button: Send while idle, Pause/Resume while
// generation is active. Pause is a local stream-delivery pause; it is not
// represented as a provider-side inference suspension.
class _CompactSendButton extends StatelessWidget {
  const _CompactSendButton({
    super.key,
    required this.enabled,
    required this.onSend,
    required this.color,
    required this.icon,
    this.loading = false,
    this.paused = false,
    this.onTogglePaused,
    this.tooltip,
  });

  final bool enabled;
  final bool loading;
  final bool paused;
  final VoidCallback onSend;
  final VoidCallback? onTogglePaused;
  final Color color;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = enabled || loading;
    final bg = active ? color : cs.onSurface.withValues(alpha: 0.12);
    final fg = active ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.38);

    final button = Material(
      key: const ValueKey('composer-primary-task'),
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: loading ? onTogglePaused : (enabled ? onSend : null),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: loading
                ? Icon(
                    paused ? Lucide.Play : Lucide.Pause,
                    key: ValueKey(paused ? 'resume' : 'pause'),
                    size: 18,
                    color: fg,
                  )
                : Icon(
                    icon,
                    key: const ValueKey('send'),
                    size: 18,
                    color: fg,
                  ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(tooltip: tooltip!, child: button),
    );
  }
}

// Scrolling waveform driven by real mic amplitude samples""",
        "input-bar/replace-primary-class",
    )

    replace_once(
        path,
        """class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
""",
        """class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    super.key,
    required this.icon,
""",
        "input-bar/compact-icon-key",
    )


def patch_queue_test():
    path = "test/features/home/widgets/chat_input_bar_queue_test.dart"
    replace_once(
        path,
        """    bool loading = false,
    bool hasQueuedInput = false,
""",
        """    bool loading = false,
    bool generationPaused = false,
    VoidCallback? onToggleGenerationPaused,
    bool hasQueuedInput = false,
""",
        "queue-test/harness-fields",
    )
    replace_once(
        path,
        """            onGuide: onGuide,
            loading: loading,
            hasQueuedInput: hasQueuedInput,
""",
        """            onGuide: onGuide,
            loading: loading,
            generationPaused: generationPaused,
            onToggleGenerationPaused: onToggleGenerationPaused,
            hasQueuedInput: hasQueuedInput,
""",
        "queue-test/harness-pass",
    )

    insertion_anchor = """  testWidgets('多项队列可打开管理面板并删除', (tester) async {
"""
    new_tests = r"""  testWidgets('生成草稿操作附着在文本上方且底栏保留推理入口', (tester) async {
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

    final generationActions = find.byKey(
      const ValueKey('composer-generation-actions'),
    );
    final textField = find.byType(TextField);
    final reasoning = find.byKey(
      const ValueKey('composer-reasoning-button'),
    );

    expect(generationActions, findsOneWidget);
    expect(reasoning, findsOneWidget);
    expect(
      tester.getTopLeft(generationActions).dy,
      lessThan(tester.getTopLeft(textField).dy),
    );
    expect(find.byKey(const ValueKey('pause')), findsOneWidget);
    expect(find.byKey(const ValueKey('stop')), findsNothing);

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
    await tester.pump();

    expect(find.byKey(const ValueKey('pause')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('composer-primary-task')));
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
    expect(find.byKey(const ValueKey('stop')), findsNothing);

    controller.dispose();
    focusNode.dispose();
  });

"""
    replace_once(path, insertion_anchor, new_tests + insertion_anchor, "queue-test/add-v8-tests")


def add_pause_test():
    path = Path("test/features/home/controllers/chat_controller_pause_test.dart")
    if path.exists():
        fail("pause-test", "file unexpectedly already exists")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        """import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/controllers/chat_controller.dart';

class _FakeChatService extends ChatService {}

void main() {
  test('local pause keeps loading and resumes buffered stream', () async {
    final chat = ChatController(chatService: _FakeChatService());
    const id = 'conversation-a';
    final source = StreamController<int>();
    final received = <int>[];
    final subscription = source.stream.listen(received.add);

    addTearDown(() async {
      await subscription.cancel();
      await source.close();
      chat.dispose();
    });

    chat.setConversationLoading(id, true);
    chat.setStreamSubscription(id, subscription);

    expect(chat.pauseStreamSubscription(id), isTrue);
    expect(chat.isConversationPaused(id), isTrue);
    expect(chat.isConversationLoading(id), isTrue);

    source.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);

    expect(chat.resumeStreamSubscription(id), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(received, <int>[1]);
    expect(chat.isConversationPaused(id), isFalse);

    chat.setConversationLoading(id, false);
    expect(chat.isConversationPaused(id), isFalse);
  });
}
""",
        encoding="utf-8",
    )


def validate():
    bar = Path("lib/features/home/widgets/chat_input_bar.dart").read_text(encoding="utf-8")
    required = [
        "composer-generation-actions",
        "composer-reasoning-button",
        "generationPaused",
        "onToggleGenerationPaused",
        "ValueKey(paused ? 'resume' : 'pause')",
    ]
    for token in required:
        if token not in bar:
            fail("validate/chat-input-bar", f"missing {token}")
    if "key: const ValueKey('stop')" in bar:
        fail("validate/chat-input-bar", "legacy stop primary icon remains")
    section = Path("lib/features/home/widgets/chat_input_section.dart").read_text(encoding="utf-8")
    if "StoryModeChatChip" in section:
        fail("validate/input-section", "permanent StoryModeChatChip returned")
    controller = Path("lib/features/home/controllers/chat_controller.dart").read_text(encoding="utf-8")
    if "pauseStreamSubscription" not in controller or "resumeStreamSubscription" not in controller:
        fail("validate/chat-controller", "pause/resume API missing")


patch_chat_controller()
patch_home_view_model()
patch_home_page_controller()
patch_home_page()
patch_input_section()
patch_lucide()
patch_input_bar()
patch_queue_test()
add_pause_test()
validate()
print("Composer v8 generation finalize patch applied")
