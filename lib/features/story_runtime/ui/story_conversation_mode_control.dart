import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/interactive_drawer.dart';
import '../../../theme/app_font_weights.dart';
import '../orchestration/story_mode_transition_service.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';

/// Lightweight revision signal for Story UI surfaces that are siblings of the
/// AppBar title. Story mode remains persisted by [StoryRuntimeStore]; this only
/// asks visible UI to refresh after an in-place mode switch.
final ValueNotifier<int> storyConversationModeRevision = ValueNotifier<int>(0);

const storyWorkspaceSelectedKey = 'story_workspace_selected_v1';

bool isStoryWorkspaceSelected(
  BusinessPreferences preferences, {
  bool fallback = false,
}) => preferences.getBool(storyWorkspaceSelectedKey) ?? fallback;

/// Persistent Chat / Story mode switch for the active conversation.
class StoryConversationModeTitle extends StatefulWidget {
  const StoryConversationModeTitle({super.key, required this.fallback});

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

  Future<void> _selectMode(
    String conversationId,
    StoryRuntimeSessionState session,
    bool story,
  ) async {
    final preferences = context.read<BusinessPreferences>();
    final workspaceSelected = isStoryWorkspaceSelected(
      preferences,
      fallback: session.enabled,
    );
    if (_busy || (workspaceSelected == story && (!story || session.enabled))) {
      return;
    }
    setState(() => _busy = true);
    try {
      final chatService = context.read<ChatService>();
      var next = session;
      if (story && !session.enabled) {
        final transition = StoryModeTransitionService(
          preferences: preferences,
          chatService: chatService,
        );
        next = await transition.setMode(
          conversationId: conversationId,
          storyEnabled: true,
        );
      }
      await preferences.setBool(storyWorkspaceSelectedKey, story);
      if (!mounted) return;
      setState(() {
        _loadedConversationId = conversationId;
        _sessionFuture = Future<StoryRuntimeSessionState>.value(next);
      });
      storyConversationModeRevision.value++;
      Haptics.light();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('模式转换失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatService>();
    final conversationId = chatService.currentConversationId;
    if (conversationId == null ||
        chatService.getConversation(conversationId) == null) {
      return widget.fallback;
    }

    return FutureBuilder<StoryRuntimeSessionState>(
      future: _futureFor(context, conversationId),
      builder: (context, snapshot) {
        final session =
            snapshot.data ??
            StoryRuntimeSessionState(conversationId: conversationId);
        final storySelected = isStoryWorkspaceSelected(
          context.read<BusinessPreferences>(),
          fallback: session.enabled,
        );
        final controlWidth = _modeSelectorWidth(context);
        return StoryConversationModeCenteredSlot(
          controlWidth: controlWidth,
          child: _ModeSelector(
            storySelected: storySelected,
            busy: _busy || snapshot.connectionState == ConnectionState.waiting,
            onSelectChat: () => _selectMode(conversationId, session, false),
            onSelectStory: () => _selectMode(conversationId, session, true),
          ),
        );
      },
    );
  }
}

/// Compatibility shim for Home layouts that previously exposed a separate
/// conversion action. The persistent centered switch now owns mode conversion.
class StoryConversationModeAction extends StatelessWidget {
  const StoryConversationModeAction({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Kept for focused layout tests and callers that already use this public
/// helper. It centers [child] against the physical screen while keeping the
/// child inside the title slot's real layout bounds, so paint and hit testing
/// share the same coordinates even when AppBar leading/actions are asymmetric.
class StoryConversationModeCenteredSlot extends StatefulWidget {
  const StoryConversationModeCenteredSlot({
    super.key,
    required this.controlWidth,
    required this.child,
  });

  final double controlWidth;
  final Widget child;

  @override
  State<StoryConversationModeCenteredSlot> createState() =>
      _StoryConversationModeCenteredSlotState();
}

class _StoryConversationModeCenteredSlotState
    extends State<StoryConversationModeCenteredSlot> {
  final GlobalKey _slotKey = GlobalKey();
  double? _left;
  bool _measureScheduled = false;

  void _scheduleMeasurement() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final renderObject = _slotKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;

      final slotWidth = renderObject.size.width;
      final globalLeft = renderObject.localToGlobal(Offset.zero).dx;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final maxLeft = (slotWidth - widget.controlWidth)
          .clamp(0.0, double.infinity)
          .toDouble();
      final nextLeft = (screenWidth / 2 - globalLeft - widget.controlWidth / 2)
          .clamp(0.0, maxLeft)
          .toDouble();
      final currentLeft = _left;
      if (currentLeft == null || (currentLeft - nextLeft).abs() >= 0.5) {
        setState(() => _left = nextLeft);
      }
    });
  }

  @override
  void didUpdateWidget(covariant StoryConversationModeCenteredSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controlWidth != widget.controlWidth) {
      _left = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawerController = InteractiveDrawer.maybeControllerOf(context);
    if (drawerController != null) {
      return AnimatedBuilder(
        animation: drawerController,
        builder: (context, _) {
          final drawerOpen = drawerController.value > 0.01;
          return IgnorePointer(
            ignoring: drawerOpen,
            child: Opacity(
              opacity: drawerOpen ? 0 : 1,
              child: _buildSlot(context),
            ),
          );
        },
      );
    }
    return _buildSlot(context);
  }

  Widget _buildSlot(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : widget.controlWidth;
        final fallbackLeft = ((slotWidth - widget.controlWidth) / 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        _scheduleMeasurement();
        return SizedBox(
          key: _slotKey,
          width: double.infinity,
          height: 36,
          child: Stack(
            children: [
              Positioned(
                left: _left ?? fallbackLeft,
                top: 0,
                width: widget.controlWidth,
                height: 36,
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}

double _modeSelectorWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 360 ? 112.0 : 124.0;

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
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
    final width = _modeSelectorWidth(context);
    const height = 36.0;

    return Semantics(
      container: true,
      label: zh ? '应用模式' : 'App mode',
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: cs.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.54 : 0.72,
          ),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    alignment: storySelected
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      heightFactor: 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.14),
                            width: 0.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withValues(alpha: 0.06),
                              blurRadius: 5,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _ModeTapTarget(
                      label: zh ? '聊天' : 'Chat',
                      selected: !storySelected,
                      enabled: !busy,
                      onTap: onSelectChat,
                    ),
                  ),
                  Expanded(
                    child: _ModeTapTarget(
                      label: zh ? '故事' : 'Story',
                      selected: storySelected,
                      enabled: !busy,
                      onTap: onSelectStory,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTapTarget extends StatelessWidget {
  const _ModeTapTarget({
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
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: 13,
              height: 1.05,
              fontWeight: selected
                  ? AppFontWeights.semibold
                  : AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: selected ? 0.94 : 0.58),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
