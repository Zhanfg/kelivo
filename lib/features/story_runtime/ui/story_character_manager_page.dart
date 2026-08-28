import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../icons/lucide_adapter.dart';
import '../state/story_scene_runtime_state.dart';
import '../voice/story_voice_routing.dart';
import '../voice/story_voice_store.dart';
import '../world_tree/story_world_tree_store.dart';
import 'story_native_settings_widgets.dart';
import 'story_voice_manager_page.dart';

class StoryCharacterManagerPage extends StatefulWidget {
  const StoryCharacterManagerPage({
    super.key,
    required this.conversationId,
  });

  final String conversationId;

  @override
  State<StoryCharacterManagerPage> createState() =>
      _StoryCharacterManagerPageState();
}

class _StoryCharacterManagerPageState
    extends State<StoryCharacterManagerPage> {
  late Future<_CharacterPageData> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _load();
  }

  Future<_CharacterPageData> _load() async {
    final preferences = context.read<BusinessPreferences>();
    final scene = await StorySceneRuntimeStore(
      preferences,
    ).readOrDefault(widget.conversationId);
    final tree = await StoryWorldTreeStore(
      preferences,
    ).readForConversation(widget.conversationId);
    final routing = tree == null
        ? null
        : await StoryVoiceRoutingStore(preferences).readOrDefault(
            tree.worldTreeId,
          );

    final ids = <String>{
      ...scene.participantCharacterIds,
      ...?routing?.assignments.map((item) => item.characterId),
    }..remove('__narrator__');
    final sortedIds = ids.toList()..sort();
    final characters = <_CharacterView>[];
    for (var index = 0; index < sortedIds.length; index++) {
      final id = sortedIds[index];
      final assignment = _assignmentFor(routing, id);
      characters.add(
        _CharacterView(
          displayName: _displayName(
            scene.continuityState,
            assignment,
            id,
            index,
          ),
          voiceName: assignment?.voiceId,
        ),
      );
    }
    return _CharacterPageData(characters: characters);
  }

  StoryVoiceAssignment? _assignmentFor(
    StoryVoiceRoutingState? routing,
    String characterId,
  ) {
    if (routing == null) return null;
    StoryVoiceAssignment? fallback;
    for (final assignment in routing.assignments) {
      if (assignment.characterId != characterId) continue;
      fallback ??= assignment;
      if (assignment.worldlineId == null) return assignment;
    }
    return fallback;
  }

  String _displayName(
    Map<String, Object?> continuity,
    StoryVoiceAssignment? assignment,
    String characterId,
    int index,
  ) {
    for (final key in const ['displayName', 'name', 'label']) {
      final value = assignment?.metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }

    for (final containerKey in const [
      'characters',
      'characterNames',
      'character_names',
    ]) {
      final container = continuity[containerKey];
      if (container is! Map) continue;
      final raw = container[characterId];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      if (raw is Map) {
        for (final key in const ['displayName', 'name', 'label']) {
          final value = raw[key]?.toString().trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }
    }

    return '角色 ${index + 1}';
  }

  void _openVoices() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryVoiceManagerPage(
          conversationId: widget.conversationId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zhText, String enText) => zh ? zhText : enText;

    return Scaffold(
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('角色', 'Characters')),
      ),
      body: FutureBuilder<_CharacterPageData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CharacterEmptyState(
              icon: Lucide.User,
              title: tr('角色暂时无法加载', 'Characters are unavailable'),
              subtitle: tr(
                '稍后返回故事再试。',
                'Return to the story and try again.',
              ),
            );
          }
          final characters =
              snapshot.data?.characters ?? const <_CharacterView>[];
          if (characters.isEmpty) {
            return _CharacterEmptyState(
              icon: Lucide.User,
              title: tr('还没有持续角色', 'No recurring characters yet'),
              subtitle: tr(
                '角色会在故事推进中自动出现；持续参与的角色会在这里保持稳定身份与声音。',
                'Characters appear as the story develops. Recurring characters keep a stable identity and voice here.',
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: characters.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final character = characters[index];
              final cs = Theme.of(context).colorScheme;
              return Material(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  minTileHeight: 68,
                  leading: CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    child: Text(
                      character.displayName.isEmpty
                          ? '•'
                          : character.displayName[0],
                    ),
                  ),
                  title: Text(character.displayName),
                  subtitle: Text(
                    character.voiceName == null
                        ? tr('声音：自动', 'Voice: Auto')
                        : tr(
                            '声音：${character.voiceName}',
                            'Voice: ${character.voiceName}',
                          ),
                  ),
                  trailing: Icon(
                    Lucide.ChevronRight,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  onTap: _openVoices,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CharacterPageData {
  const _CharacterPageData({required this.characters});

  final List<_CharacterView> characters;
}

class _CharacterView {
  const _CharacterView({
    required this.displayName,
    this.voiceName,
  });

  final String displayName;
  final String? voiceName;
}

class _CharacterEmptyState extends StatelessWidget {
  const _CharacterEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: cs.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
