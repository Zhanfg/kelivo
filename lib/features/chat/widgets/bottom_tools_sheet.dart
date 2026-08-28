import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../home/widgets/instruction_injection_sheet.dart';
import '../../home/widgets/world_book_sheet.dart';
import '../../instruction_injection/pages/instruction_injection_page.dart';
import '../../model/widgets/ocr_prompt_sheet.dart';
import '../../settings/pages/memory_settings_page.dart';
import '../../story_runtime/orchestration/story_mode_transition_service.dart';
import '../../story_runtime/state/story_runtime_state.dart';
import '../../story_runtime/state/story_runtime_store.dart';
import '../../story_runtime/ui/story_character_manager_page.dart';
import '../../story_runtime/ui/story_conversation_mode_control.dart';
import '../../story_runtime/ui/story_reference_library_page.dart';
import '../../story_runtime/ui/story_skill_manager_page.dart';
import '../../story_runtime/ui/story_voice_manager_page.dart';
import '../../world_book/pages/world_book_page.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';

class BottomToolsSheet extends StatelessWidget {
  const BottomToolsSheet({
    super.key,
    this.onCamera,
    this.onPhotos,
    this.onUpload,
    this.onClear,
    this.clearLabel,
    this.assistantId,
  });

  final VoidCallback? onCamera;
  final VoidCallback? onPhotos;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = Theme.of(context).colorScheme.surface;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    Widget roundedAction({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    }) {
      final cardColor = context.appColors.surfaceFill;
      return Expanded(
        child: SizedBox(
          height: 72,
          child: IosCardPress(
            baseColor: cardColor,
            borderRadius: BorderRadius.circular(14),
            pressedScale: 0.98,
            duration: const Duration(milliseconds: 260),
            onTap: () {
              Haptics.light();
              onTap?.call();
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        roundedAction(
                          icon: Lucide.Camera,
                          label: l10n.bottomToolsSheetCamera,
                          onTap: onCamera,
                        ),
                        const SizedBox(width: 12),
                        roundedAction(
                          icon: Lucide.Image,
                          label: l10n.bottomToolsSheetPhotos,
                          onTap: onPhotos,
                        ),
                        const SizedBox(width: 12),
                        roundedAction(
                          icon: Lucide.Paperclip,
                          label: l10n.bottomToolsSheetUpload,
                          onTap: onUpload,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StoryToolsSection(assistantId: assistantId),
                    const SizedBox(height: 12),
                    _LearningAndClearSection(
                      clearLabel: clearLabel,
                      onClear: onClear,
                      assistantId: assistantId,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryToolsSection extends StatefulWidget {
  const _StoryToolsSection({this.assistantId});

  final String? assistantId;

  @override
  State<_StoryToolsSection> createState() => _StoryToolsSectionState();
}

class _StoryToolsSectionState extends State<_StoryToolsSection> {
  String? _loadedConversationId;
  Future<StoryRuntimeSessionState>? _sessionFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<WorldBookProvider>().initialize();
    });
  }

  Future<StoryRuntimeSessionState> _futureFor(String conversationId) {
    if (_loadedConversationId != conversationId || _sessionFuture == null) {
      _loadedConversationId = conversationId;
      _sessionFuture = StoryRuntimeStore(
        context.read<BusinessPreferences>(),
      ).readOrDefault(conversationId);
    }
    return _sessionFuture!;
  }

  String _bookSummary(WorldBookProvider provider, bool zh) {
    final activeIds = provider.activeBookIdsFor(widget.assistantId);
    final names = activeIds
        .map(provider.getById)
        .whereType<dynamic>()
        .map((book) => (book.name as String).trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) return zh ? '未选择' : 'Not selected';
    if (names.length == 1) return names.first;
    return zh ? '${names.first} 等 ${names.length} 本' : '${names.first} +${names.length - 1}';
  }

  Future<bool> _confirmNoBookSelection(bool zh) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(zh ? '未选择故事书' : 'No story book selected'),
        content: Text(
          zh
              ? '故事模式可以继续运行，但不会绑定任何故事书。仍然进入故事模式吗？'
              : 'Story Mode can continue without a story book. Enter Story Mode anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(zh ? '继续' : 'Continue'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _setStoryMode({
    required String conversationId,
    required bool enabled,
    required bool zh,
  }) async {
    if (_busy) return;

    if (enabled) {
      final worldBooks = context.read<WorldBookProvider>();
      await worldBooks.initialize();
      if (!mounted) return;
      if (worldBooks.books.isNotEmpty &&
          worldBooks.activeBookIdsFor(widget.assistantId).isEmpty) {
        await showWorldBookSheet(context, assistantId: widget.assistantId);
        if (!mounted) return;
        if (worldBooks.activeBookIdsFor(widget.assistantId).isEmpty &&
            !await _confirmNoBookSelection(zh)) {
          return;
        }
      }
    }

    setState(() => _busy = true);
    try {
      final transition = StoryModeTransitionService(
        preferences: context.read<BusinessPreferences>(),
        chatService: context.read<ChatService>(),
      );
      final next = await transition.setMode(
        conversationId: conversationId,
        storyEnabled: enabled,
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
        SnackBar(content: Text(zh ? '模式转换失败：$error' : 'Mode switch failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPage(Widget page) {
    Haptics.light();
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).maybePop();
    Future.microtask(
      () => rootNav.push(MaterialPageRoute(builder: (_) => page)),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    String? value,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool destructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.onSurface;
    return SizedBox(
      height: 50,
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        baseColor: cs.surface,
        duration: const Duration(milliseconds: 260),
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: color,
                ),
              ),
            ),
            if (value != null) ...[
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (onTap != null)
              Icon(
                Lucide.ChevronRight,
                size: 18,
                color: destructive
                    ? cs.error.withValues(alpha: 0.8)
                    : cs.onSurface.withValues(alpha: 0.45),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final chatService = context.read<ChatService>();
    final conversationId = chatService.currentConversationId;
    if (conversationId == null ||
        chatService.getConversation(conversationId) == null) {
      return const SizedBox.shrink();
    }

    final worldBooks = context.watch<WorldBookProvider>();
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<StoryRuntimeSessionState>(
      future: _futureFor(conversationId),
      builder: (context, snapshot) {
        final session =
            snapshot.data ??
            StoryRuntimeSessionState(conversationId: conversationId);
        final enabled = session.enabled;
        final loading =
            _busy || snapshot.connectionState == ConnectionState.waiting;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Row(
                children: [
                  Text(
                    zh ? '故事' : 'Story',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    enabled ? (zh ? '已启用' : 'Enabled') : (zh ? '聊天模式' : 'Chat mode'),
                    style: TextStyle(
                      fontSize: 12,
                      color: enabled
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
            if (!enabled)
              _row(
                icon: Lucide.BookOpenText,
                label: zh ? '进入故事模式' : 'Enter Story Mode',
                value: zh ? '从当前对话继续' : 'Continue this chat',
                onTap: loading
                    ? null
                    : () => _setStoryMode(
                        conversationId: conversationId,
                        enabled: true,
                        zh: zh,
                      ),
              ),
            if (!enabled) const SizedBox(height: 4),
            _row(
              icon: Lucide.BookOpen,
              label: zh ? '故事书' : 'Story book',
              value: _bookSummary(worldBooks, zh),
              onTap: () async {
                Haptics.light();
                await showWorldBookSheet(
                  context,
                  assistantId: widget.assistantId,
                );
              },
              onLongPress: () => _openPage(const WorldBookPage()),
            ),
            if (enabled) ...[
              const SizedBox(height: 4),
              _row(
                icon: Lucide.User,
                label: zh ? '角色' : 'Characters',
                onTap: () => _openPage(
                  StoryCharacterManagerPage(conversationId: conversationId),
                ),
              ),
              const SizedBox(height: 4),
              _row(
                icon: Lucide.Brain,
                label: zh ? '记忆' : 'Memory',
                onTap: () => _openPage(const MemorySettingsPage()),
              ),
              const SizedBox(height: 4),
              _row(
                icon: Lucide.Volume2,
                label: zh ? '声音' : 'Voices',
                onTap: () => _openPage(
                  StoryVoiceManagerPage(conversationId: conversationId),
                ),
              ),
              const SizedBox(height: 4),
              _row(
                icon: Lucide.BookOpenText,
                label: zh ? '参考资料' : 'References',
                onTap: () => _openPage(const StoryReferenceLibraryPage()),
              ),
              const SizedBox(height: 4),
              _row(
                icon: Lucide.Shapes,
                label: zh ? '技能' : 'Skills',
                onTap: () => _openPage(const StorySkillManagerPage()),
              ),
              const SizedBox(height: 4),
              _row(
                icon: Icons.logout_rounded,
                label: zh ? '退出故事模式' : 'Leave Story Mode',
                destructive: true,
                onTap: loading
                    ? null
                    : () => _setStoryMode(
                        conversationId: conversationId,
                        enabled: false,
                        zh: zh,
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LearningAndClearSection extends StatefulWidget {
  const _LearningAndClearSection({
    this.onClear,
    this.clearLabel,
    this.assistantId,
  });
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;

  @override
  State<_LearningAndClearSection> createState() =>
      _LearningAndClearSectionState();
}

class _LearningAndClearSectionState extends State<_LearningAndClearSection> {
  Widget _row({
    required IconData icon,
    required String label,
    bool selected = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    final onColor = selected ? cs.primary : cs.onSurface;
    final radius = BorderRadius.circular(14);
    return SizedBox(
      height: 48,
      child: IosCardPress(
        borderRadius: radius,
        baseColor: Theme.of(context).colorScheme.surface,
        duration: const Duration(milliseconds: 260),
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: onColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: onColor,
                ),
              ),
            ),
            trailing ??
                (selected
                    ? Icon(Lucide.Check, size: 18, color: cs.primary)
                    : const SizedBox(width: 18)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;
    final hasOcrModel =
        settings.ocrModelProvider != null && settings.ocrModelId != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(
          icon: Lucide.Layers,
          label: l10n.instructionInjectionTitle,
          selected: false,
          onTap: () async {
            Haptics.light();
            await showInstructionInjectionSheet(
              context,
              assistantId: widget.assistantId,
            );
          },
          onLongPress: () {
            Haptics.light();
            final rootNav = Navigator.of(context, rootNavigator: true);
            Navigator.of(context).maybePop();
            Future.microtask(() {
              rootNav.push(
                MaterialPageRoute(
                  builder: (_) => const InstructionInjectionPage(),
                ),
              );
            });
          },
          trailing: Icon(
            Lucide.ChevronRight,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
        if (hasOcrModel) ...[
          const SizedBox(height: 8),
          _row(
            icon: Lucide.Eye,
            label: l10n.bottomToolsSheetOcr,
            selected: settings.ocrEnabled,
            onTap: () async {
              Haptics.light();
              final sp = context.read<SettingsProvider>();
              await sp.setOcrEnabled(!sp.ocrEnabled);
              if (!context.mounted) return;
              Navigator.of(context).maybePop();
            },
            onLongPress: () => showOcrPromptSheet(context),
          ),
        ],
        const SizedBox(height: 8),
        _row(
          icon: Lucide.workflow,
          label: l10n.contextManagement,
          onTap: () {
            Haptics.light();
            widget.onClear?.call();
          },
          trailing: Icon(
            Lucide.ChevronRight,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
