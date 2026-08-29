import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../icons/lucide_adapter.dart';
import '../../settings/pages/memory_settings_page.dart';
import '../../world_book/pages/world_book_page.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import 'story_character_manager_page.dart';
import 'story_conversation_mode_control.dart';
import 'story_reference_library_page.dart';
import 'story_skill_manager_page.dart';
import 'story_voice_manager_page.dart';

/// Product-level Story quick tools shown above the native input bar.
///
/// This is the single first-level Story tool surface. Story settings must not
/// duplicate these destinations as a second navigation hierarchy.
class StoryModeChatChip extends StatefulWidget {
  const StoryModeChatChip({super.key, required this.conversationId});

  final String? conversationId;

  @override
  State<StoryModeChatChip> createState() => _StoryModeChatChipState();
}

class _StoryModeChatChipState extends State<StoryModeChatChip> {
  String? _loadedConversationId;
  int? _loadedRevision;
  Future<StoryRuntimeSessionState>? _sessionFuture;

  Future<StoryRuntimeSessionState> _futureFor(
    BuildContext context,
    String conversationId,
    int revision,
  ) {
    if (_loadedConversationId != conversationId ||
        _loadedRevision != revision ||
        _sessionFuture == null) {
      _loadedConversationId = conversationId;
      _loadedRevision = revision;
      _sessionFuture = StoryRuntimeStore(
        context.read<BusinessPreferences>(),
      ).readOrDefault(conversationId);
    }
    return _sessionFuture!;
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final conversationId = widget.conversationId;
    if (conversationId == null || conversationId.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<int>(
      valueListenable: storyConversationModeRevision,
      builder: (context, revision, _) {
        return FutureBuilder<StoryRuntimeSessionState>(
          future: _futureFor(context, conversationId, revision),
          builder: (context, snapshot) {
            final enabled = snapshot.data?.enabled == true;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: enabled
                  ? _StoryQuickTools(
                      key: const ValueKey('story-quick-tools'),
                      conversationId: conversationId,
                      onOpen: _open,
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('story-quick-tools-hidden'),
                    ),
            );
          },
        );
      },
    );
  }
}

class _StoryQuickTools extends StatelessWidget {
  const _StoryQuickTools({
    super.key,
    required this.conversationId,
    required this.onOpen,
  });

  final String conversationId;
  final ValueChanged<Widget> onOpen;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tools = <_StoryToolSpec>[
      _StoryToolSpec(
        label: zh ? '世界书' : 'World Book',
        icon: Lucide.BookOpen,
        page: const WorldBookPage(),
      ),
      _StoryToolSpec(
        label: zh ? '记忆' : 'Memory',
        icon: Lucide.Brain,
        page: const MemorySettingsPage(),
      ),
      _StoryToolSpec(
        label: zh ? '角色' : 'Characters',
        icon: Lucide.User,
        page: StoryCharacterManagerPage(conversationId: conversationId),
      ),
      _StoryToolSpec(
        label: zh ? '声音' : 'Voices',
        icon: Lucide.Volume2,
        page: StoryVoiceManagerPage(conversationId: conversationId),
      ),
      _StoryToolSpec(
        label: zh ? '参考' : 'References',
        icon: Lucide.BookOpenText,
        page: const StoryReferenceLibraryPage(),
      ),
      _StoryToolSpec(
        label: zh ? '技能' : 'Skills',
        icon: Lucide.Shapes,
        page: const StorySkillManagerPage(),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withValues(
                alpha: isDark ? 0.64 : 0.78,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.14),
                width: 0.6,
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  for (final tool in tools)
                    _StoryQuickToolButton(
                      label: tool.label,
                      icon: tool.icon,
                      onTap: () => onOpen(tool.page),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryToolSpec {
  const _StoryToolSpec({
    required this.label,
    required this.icon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final Widget page;
}

class _StoryQuickToolButton extends StatelessWidget {
  const _StoryQuickToolButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 68, minHeight: 42),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: cs.onSurface.withValues(alpha: 0.78),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.05,
                      color: cs.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
