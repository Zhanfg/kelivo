import '../utils/prompt_injection_selection.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/skills_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../home/widgets/instruction_injection_sheet.dart';
import '../../home/widgets/world_book_sheet.dart';
import '../../instruction_injection/pages/instruction_injection_page.dart';
import '../../world_book/pages/world_book_page.dart';
import '../../settings/pages/memory_settings_page.dart';
import '../../story_runtime/ui/story_character_manager_page.dart';
import '../../story_runtime/ui/story_reference_library_page.dart';
import '../../story_runtime/ui/story_skill_manager_page.dart';
import '../../story_runtime/ui/story_voice_manager_page.dart';
import '../../model/widgets/ocr_prompt_sheet.dart';
import '../../workspace/pages/skills_page.dart';
import '../../workspace/widgets/skills/conversation_skills_sheet.dart';
import '../utils/ensure_conversation.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';
import 'tools_sheet_row.dart';

/// Row that opens the session skills picker, and pushes the skills library on
/// a long press.
const Key sessionSkillsKey = ValueKey<String>('bottom-tools-session-skills');

class BottomToolsSheet extends StatelessWidget {
  const BottomToolsSheet({
    super.key,
    this.onCamera,
    this.onPhotos,
    this.onUpload,
    this.onDrawing,
    this.onSearch,
    this.onMcp,
    this.onQuickPhrase,
    this.onManageQuickPhrases,
    this.onClear,
    this.clearLabel,
    this.assistantId,
    this.conversationId,
    this.storyConversationId,
    this.onClose,
  });

  final VoidCallback? onCamera;
  final VoidCallback? onPhotos;
  final VoidCallback? onUpload;
  final VoidCallback? onDrawing;
  final VoidCallback? onSearch;
  final VoidCallback? onMcp;
  final VoidCallback? onQuickPhrase;
  final VoidCallback? onManageQuickPhrases;
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;
  final String? conversationId;
  final String? storyConversationId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = context.overlaySurface;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    final storyConversationId = this.storyConversationId;

    void openStoryPage(Widget page) {
      final navigator = Navigator.of(context, rootNavigator: true);
      Navigator.of(context).maybePop();
      Future.microtask(
        () => navigator.push(MaterialPageRoute(builder: (_) => page)),
      );
    }

    Widget secondaryAction({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
      VoidCallback? onLongPress,
    }) {
      final cs = Theme.of(context).colorScheme;
      return SizedBox(
        height: 48,
        child: IosCardPress(
          borderRadius: BorderRadius.circular(14),
          baseColor: cs.surface,
          duration: const Duration(milliseconds: 220),
          onTap: onTap,
          onLongPress: onLongPress,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.medium,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Icon(
                Lucide.ChevronRight,
                size: 18,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      );
    }

    Widget roundedAction({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    }) {
      final cardColor = sheetTileColor(context);
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
                          icon: Lucide.Image,
                          label: l10n.bottomToolsSheetPhotos,
                          onTap: onPhotos,
                        ),
                        const SizedBox(width: 12),
                        roundedAction(
                          icon: Lucide.Camera,
                          label: l10n.bottomToolsSheetCamera,
                          onTap: onCamera,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        roundedAction(
                          icon: Lucide.Paperclip,
                          label: l10n.bottomToolsSheetUpload,
                          onTap: onUpload,
                        ),
                        const SizedBox(width: 12),
                        roundedAction(
                          icon: Lucide.Brush,
                          label:
                              Localizations.localeOf(context).languageCode ==
                                  'zh'
                              ? '绘画'
                              : 'Draw',
                          onTap: onDrawing,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _LearningAndClearSection(
                      clearLabel: clearLabel,
                      onClear: onClear,
                      assistantId: assistantId,
                      conversationId: conversationId,
                      onClose: onClose,
                    ),
                    if (storyConversationId != null) ...[
                      const SizedBox(height: 8),
                      secondaryAction(
                        icon: Lucide.BookOpen,
                        label:
                            Localizations.localeOf(context).languageCode == 'zh'
                            ? '世界书'
                            : 'World Book',
                        onTap: () => openStoryPage(const WorldBookPage()),
                      ),
                      secondaryAction(
                        icon: Lucide.Brain,
                        label:
                            Localizations.localeOf(context).languageCode == 'zh'
                            ? '记忆'
                            : 'Memory',
                        onTap: () => openStoryPage(const MemorySettingsPage()),
                      ),
                      secondaryAction(
                        icon: Lucide.User,
                        label:
                            Localizations.localeOf(context).languageCode == 'zh'
                            ? '角色'
                            : 'Characters',
                        onTap: () => openStoryPage(
                          StoryCharacterManagerPage(
                            conversationId: storyConversationId,
                          ),
                        ),
                      ),
                      secondaryAction(
                        icon: Lucide.Volume2,
                        label:
                            Localizations.localeOf(context).languageCode == 'zh'
                            ? '声音'
                            : 'Voices',
                        onTap: () => openStoryPage(
                          StoryVoiceManagerPage(
                            conversationId: storyConversationId,
                          ),
                        ),
                      ),
                      secondaryAction(
                        icon: Lucide.BookOpenText,
                        label:
                            Localizations.localeOf(context).languageCode == 'zh'
                            ? '参考资料'
                            : 'References',
                        onTap: () =>
                            openStoryPage(const StoryReferenceLibraryPage()),
                      ),
                      secondaryAction(
                        icon: Lucide.Shapes,
                        label:
                            Localizations.localeOf(context).languageCode == 'zh'
                            ? '故事技能'
                            : 'Story Skills',
                        onTap: () =>
                            openStoryPage(const StorySkillManagerPage()),
                      ),
                    ] else if (onSearch != null ||
                        onMcp != null ||
                        onQuickPhrase != null) ...[
                      const SizedBox(height: 8),
                      if (onSearch != null)
                        secondaryAction(
                          icon: Lucide.Globe,
                          label: l10n.chatInputBarOnlineSearchTooltip,
                          onTap: onSearch,
                        ),
                      if (onMcp != null)
                        secondaryAction(
                          icon: Lucide.Hammer,
                          label: l10n.chatInputBarMcpServersTooltip,
                          onTap: onMcp,
                        ),
                      if (onQuickPhrase != null)
                        secondaryAction(
                          icon: Lucide.Zap,
                          label: l10n.chatInputBarQuickPhraseTooltip,
                          onTap: onQuickPhrase,
                          onLongPress: onManageQuickPhrases,
                        ),
                    ],
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

class _LearningAndClearSection extends StatefulWidget {
  const _LearningAndClearSection({
    this.onClear,
    this.clearLabel,
    this.assistantId,
    this.conversationId,
    this.onClose,
  });
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;
  final String? conversationId;
  final VoidCallback? onClose;

  @override
  State<_LearningAndClearSection> createState() =>
      _LearningAndClearSectionState();
}

class _LearningAndClearSectionState extends State<_LearningAndClearSection> {
  String? _promptConversationId;

  Future<String?> _promptScopeId() async {
    if (_assistant()?.allowConversationPromptInjection != true) return null;
    return _promptConversationId ??= await ensureConversationId(
      context,
      conversationId: widget.conversationId,
      assistantId: widget.assistantId,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future.wait([
        context.read<WorldBookProvider>().initialize(),
        context.read<InstructionInjectionProvider>().initialize(),
      ]);
    });
  }

  Assistant? _assistant({bool listen = false}) {
    try {
      final provider = Provider.of<AssistantProvider>(context, listen: listen);
      final id = widget.assistantId;
      if (id != null) return provider.getById(id);
      return provider.currentAssistant;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openSessionSkills() async {
    Haptics.light();
    final id = await ensureConversationId(
      context,
      conversationId: _promptConversationId ?? widget.conversationId,
      assistantId: widget.assistantId,
    );
    if (id == null || !mounted) return;
    _promptConversationId = id;
    await showConversationSkillsSheet(
      context,
      conversationId: id,
      assistant: _assistant(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final worldBookProvider = context.watch<WorldBookProvider>();
    final injections = context.watch<InstructionInjectionProvider>();
    final skills = context.watch<SkillsService>();
    final chat = context.watch<ChatService>();
    final assistant = _assistant(listen: true);
    final hasOcrModel =
        settings.ocrModelProvider != null && settings.ocrModelId != null;
    final hasWorldBooks = worldBookProvider.books.isNotEmpty;
    final scoped = assistant?.allowConversationPromptInjection == true;
    final scopeId = _promptConversationId ?? widget.conversationId;
    Set<String> activeIds(PromptSelectionKind kind) => scoped && scopeId == null
        ? <String>{}
        : promptSelectionIds(
            context,
            kind: kind,
            assistantId: widget.assistantId,
            conversationId: scoped ? scopeId : null,
          ).toSet();
    final activeWorldBookIds = activeIds(PromptSelectionKind.worldBook);
    final enabledWorldBookCount = worldBookProvider.books
        .where((book) => book.enabled && activeWorldBookIds.contains(book.id))
        .length;
    final activeInstructionIds = activeIds(PromptSelectionKind.instruction);
    final enabledInstructionCount = injections.items
        .where((item) => activeInstructionIds.contains(item.id))
        .length;
    final skillBinding = SkillsBinding.fromExtras(
      scopeId == null
          ? const {}
          : chat.getConversation(scopeId)?.extras ?? const {},
    );
    final enabledSkillCount = skills
        .resolveForAssistant(
          assistant,
          conversationOverride: skillBinding.skillIds,
        )
        .length;
    final chevron = ToolsSheetRow.chevron(context);
    Widget selectionTrailing(int enabled, int total) => enabled == 0
        ? chevron
        : Text(
            '$enabled/$total',
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.medium,
              color: Theme.of(context).colorScheme.primary,
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolsSheetRow(
          key: sessionSkillsKey,
          icon: Lucide.WandSparkles,
          label: l10n.workspaceEntrySessionSkills,
          onTap: () => unawaited(_openSessionSkills()),
          onLongPress: () {
            Haptics.light();
            final rootNav = Navigator.of(context, rootNavigator: true);
            Navigator.of(context).maybePop();
            Future.microtask(() {
              if (!rootNav.mounted) return;
              unawaited(openSkillsPage(rootNav.context));
            });
          },
          trailing: selectionTrailing(enabledSkillCount, skills.skills.length),
        ),
        const SizedBox(height: 8),
        ToolsSheetRow(
          icon: Lucide.Layers,
          label: l10n.instructionInjectionTitle,
          onTap: () async {
            Haptics.light();
            final scoped =
                _assistant()?.allowConversationPromptInjection == true;
            final scopeId = await _promptScopeId();
            if (!context.mounted || (scoped && scopeId == null)) return;
            await showInstructionInjectionSheet(
              context,
              assistantId: widget.assistantId,
              conversationId: scopeId,
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
          trailing: selectionTrailing(
            enabledInstructionCount,
            injections.items.length,
          ),
        ),
        if (hasWorldBooks) ...[
          const SizedBox(height: 8),
          ToolsSheetRow(
            icon: Lucide.BookOpen,
            label: l10n.worldBookTitle,
            onTap: () async {
              Haptics.light();
              final scoped =
                  _assistant()?.allowConversationPromptInjection == true;
              final scopeId = await _promptScopeId();
              if (!context.mounted || (scoped && scopeId == null)) return;
              await showWorldBookSheet(
                context,
                assistantId: widget.assistantId,
                conversationId: scopeId,
              );
            },
            onLongPress: () {
              Haptics.light();
              final rootNav = Navigator.of(context, rootNavigator: true);
              Navigator.of(context).maybePop();
              Future.microtask(() {
                rootNav.push(
                  MaterialPageRoute(builder: (_) => const WorldBookPage()),
                );
              });
            },
            trailing: selectionTrailing(
              enabledWorldBookCount,
              worldBookProvider.books.length,
            ),
          ),
        ],
        if (hasOcrModel) ...[
          const SizedBox(height: 8),
          ToolsSheetRow(
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
        ToolsSheetRow(
          icon: Lucide.workflow,
          label: l10n.contextManagement,
          onTap: () {
            Haptics.light();
            widget.onClear?.call();
          },
          trailing: chevron,
        ),
      ],
    );
  }
}
