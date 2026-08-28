import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import '../orchestration/story_mode_transition_service.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';

/// Lightweight revision signal for Story UI surfaces that are siblings of the
/// AppBar title. Story mode remains persisted by [StoryRuntimeStore]; this only
/// asks visible UI to refresh after an in-place mode switch.
final ValueNotifier<int> storyConversationModeRevision = ValueNotifier<int>(0);

/// Persistent Chat / Story mode switch for the active conversation.
///
/// The selector is rendered through an [OverlayPortal]. Its X coordinate is
/// therefore resolved against the route Overlay (the physical screen), not the
/// AppBar title slot whose width changes with leading/actions/navigation state.
/// The portal is still owned by the Home route, so a pushed Settings route paints
/// above it and the selector never leaks onto the next page.
class StoryConversationModeTitle extends StatefulWidget {
  const StoryConversationModeTitle({super.key, required this.fallback});

  final Widget fallback;

  @override
  State<StoryConversationModeTitle> createState() =>
      _StoryConversationModeTitleState();
}

class _StoryConversationModeTitleState
    extends State<StoryConversationModeTitle> {
  final OverlayPortalController _portalController = OverlayPortalController(
    debugLabel: 'story-conversation-mode',
  );
  final GlobalKey _anchorKey = GlobalKey();

  String? _loadedConversationId;
  Future<StoryRuntimeSessionState>? _sessionFuture;
  bool _busy = false;
  bool _postFrameScheduled = false;
  bool _portalWanted = false;
  double? _toolbarCenterY;

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

  void _schedulePortalState(bool visible) {
    _portalWanted = visible;
    if (_postFrameScheduled) return;
    _postFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameScheduled = false;
      if (!mounted) return;

      if (_portalWanted) {
        final renderObject = _anchorKey.currentContext?.findRenderObject();
        if (renderObject is RenderBox && renderObject.hasSize) {
          final nextY = renderObject.localToGlobal(
            Offset(renderObject.size.width / 2, renderObject.size.height / 2),
          ).dy;
          final currentY = _toolbarCenterY;
          if (currentY == null || (currentY - nextY).abs() >= 0.5) {
            setState(() => _toolbarCenterY = nextY);
          }
        }
        if (!_portalController.isShowing) _portalController.show();
      } else if (_portalController.isShowing) {
        _portalController.hide();
      }
    });
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
      final preferences = context.read<BusinessPreferences>();
      final chatService = context.read<ChatService>();
      final transition = StoryModeTransitionService(
        preferences: preferences,
        chatService: chatService,
      );
      final next = await transition.setMode(
        conversationId: conversationId,
        storyEnabled: story,
      );
      if (!mounted) return;
      setState(() {
        _loadedConversationId = conversationId;
        _sessionFuture = Future<StoryRuntimeSessionState>.value(next);
      });
      storyConversationModeRevision.value++;
      Haptics.light();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模式转换失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    if (_portalController.isShowing) _portalController.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatService>();
    final conversationId = chatService.currentConversationId;
    if (conversationId == null ||
        chatService.getConversation(conversationId) == null) {
      _schedulePortalState(false);
      return widget.fallback;
    }

    return FutureBuilder<StoryRuntimeSessionState>(
      future: _futureFor(context, conversationId),
      builder: (context, snapshot) {
        final session =
            snapshot.data ??
            StoryRuntimeSessionState(conversationId: conversationId);
        _schedulePortalState(true);
        final controlWidth = _modeSelectorWidth(context);
        final media = MediaQuery.of(context);
        final defaultCenterY = media.padding.top + (kToolbarHeight / 2);
        final centerY = _toolbarCenterY ?? defaultCenterY;
        final left = ((media.size.width - controlWidth) / 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        final top = (centerY - 18).clamp(0.0, double.infinity).toDouble();

        return OverlayPortal(
          controller: _portalController,
          overlayChildBuilder: (overlayContext) => Positioned(
            left: left,
            top: top,
            width: controlWidth,
            height: 36,
            child: _ModeSelector(
              storySelected: session.enabled,
              busy: _busy ||
                  snapshot.connectionState == ConnectionState.waiting,
              onSelectChat: () =>
                  _selectMode(conversationId, session, false),
              onSelectStory: () =>
                  _selectMode(conversationId, session, true),
            ),
          ),
          child: SizedBox(
            key: _anchorKey,
            width: 1,
            height: 36,
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
/// helper. The product AppBar no longer depends on this title-slot centering;
/// [StoryConversationModeTitle] uses an OverlayPortal instead.
class StoryConversationModeCenteredSlot extends StatelessWidget {
  const StoryConversationModeCenteredSlot({
    super.key,
    required this.controlWidth,
    required this.child,
  });

  final double controlWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: Center(
        child: SizedBox(width: controlWidth, height: 36, child: child),
      ),
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
