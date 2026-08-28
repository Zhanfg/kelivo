import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';

/// Lightweight revision signal for Story UI surfaces that are siblings of the
/// AppBar title. Story mode remains persisted by [StoryRuntimeStore]; this only
/// asks visible UI to refresh after an in-place mode switch.
final ValueNotifier<int> storyConversationModeRevision = ValueNotifier<int>(0);

/// Persistent Chat / Story mode switch for the active conversation.
///
/// The control stays visible after a conversation starts. The active selector
/// expands its title slot to the full width the AppBar actually gives it, then
/// places the selector at the physical screen center inside those real layout
/// bounds. This keeps painting and hit testing in the same coordinate space.
class StoryConversationModeTitle extends StatefulWidget {
  const StoryConversationModeTitle({super.key, required this.fallback});

  /// Kept for Home layout compatibility and used while no conversation exists.
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
    if (_busy || (session.modeSelectionCommitted && session.enabled == story)) {
      return;
    }
    setState(() => _busy = true);
    try {
      final store = StoryRuntimeStore(context.read<BusinessPreferences>());
      await store.setEnabled(conversationId, story);
      if (!mounted) return;
      setState(() {
        _loadedConversationId = conversationId;
        _sessionFuture = store.readOrDefault(conversationId);
      });
      storyConversationModeRevision.value++;
      Haptics.light();
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
        final controlWidth = _modeSelectorWidth(context);
        return StoryConversationModeCenteredSlot(
          controlWidth: controlWidth,
          child: _ModeSelector(
            storySelected: session.enabled,
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

/// Gives the centered Story mode control real layout space instead of moving a
/// narrow title with a paint-only transform.
///
/// Keeping the control inside this widget's actual bounds is important because
/// ancestors reject pointer events outside a RenderBox before transformed
/// descendants get a chance to hit-test. This widget is public so the AppBar
/// hit-test regression can be covered by a focused widget test.
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
  double? _localLeft;
  bool _measureScheduled = false;

  @override
  void didUpdateWidget(covariant StoryConversationModeCenteredSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controlWidth != widget.controlWidth) {
      _localLeft = null;
    }
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final renderObject = _slotKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;

      final screenWidth = MediaQuery.sizeOf(context).width;
      final slotLeft = renderObject.localToGlobal(Offset.zero).dx;
      final desiredGlobalLeft = (screenWidth - widget.controlWidth) / 2;
      final maxLeft = (renderObject.size.width - widget.controlWidth)
          .clamp(0.0, double.infinity)
          .toDouble();
      final nextLeft = (desiredGlobalLeft - slotLeft)
          .clamp(0.0, maxLeft)
          .toDouble();
      final currentLeft = _localLeft;
      if (currentLeft != null && (nextLeft - currentLeft).abs() < 0.5) {
        return;
      }
      setState(() => _localLeft = nextLeft);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return SizedBox(
            width: widget.controlWidth,
            height: 36,
            child: widget.child,
          );
        }

        final maxLeft = (constraints.maxWidth - widget.controlWidth)
            .clamp(0.0, double.infinity)
            .toDouble();
        final fallbackLeft = ((constraints.maxWidth - widget.controlWidth) / 2)
            .clamp(0.0, maxLeft)
            .toDouble();
        final left = (_localLeft ?? fallbackLeft)
            .clamp(0.0, maxLeft)
            .toDouble();
        _scheduleMeasure();

        return SizedBox(
          key: _slotKey,
          width: double.infinity,
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: left,
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
