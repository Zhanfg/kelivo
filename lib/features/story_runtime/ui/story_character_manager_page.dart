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
  const StoryCharacterManagerPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<StoryCharacterManagerPage> createState() =>
      _StoryCharacterManagerPageState();
}

class _StoryCharacterManagerPageState extends State<StoryCharacterManagerPage> {
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
        : await StoryVoiceRoutingStore(
            preferences,
          ).readOrDefault(tree.worldTreeId);

    final zh = Localizations.localeOf(context).languageCode == 'zh';
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
          characterId: id,
          displayName: _displayName(
            scene.continuityState,
            assignment,
            id,
            index,
            zh: zh,
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
    int index, {
    required bool zh,
  }) {
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

    return zh ? '角色 ${index + 1}' : 'Character ${index + 1}';
  }

  Future<void> _editCharacterName(_CharacterView character) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final controller = TextEditingController(text: character.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(zh ? '修正角色名称' : 'Edit character name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: zh ? '显示名称' : 'Display name',
            helperText: zh
                ? '只修正展示身份，不会改变稳定角色 ID。'
                : 'This changes presentation only; the stable character ID is preserved.',
          ),
          onSubmitted: (value) {
            final normalized = value.trim();
            if (normalized.isNotEmpty) Navigator.of(context).pop(normalized);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final normalized = controller.text.trim();
              if (normalized.isNotEmpty) Navigator.of(context).pop(normalized);
            },
            child: Text(zh ? '保存' : 'Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name == character.displayName) return;

    try {
      final preferences = context.read<BusinessPreferences>();
      final sceneStore = StorySceneRuntimeStore(preferences);
      final scene = await sceneStore.readOrDefault(widget.conversationId);
      final continuity = Map<String, Object?>.from(scene.continuityState);
      final rawCharacters = continuity['characters'];
      final characters = rawCharacters is Map
          ? Map<String, Object?>.from(rawCharacters)
          : <String, Object?>{};
      final rawCharacter = characters[character.characterId];
      final characterState = rawCharacter is Map
          ? Map<String, Object?>.from(rawCharacter)
          : <String, Object?>{};
      characterState['displayName'] = name;
      characters[character.characterId] = characterState;
      continuity['characters'] = characters;
      await sceneStore.upsert(
        scene.copyWith(
          continuityState: continuity,
          revision: scene.revision + 1,
        ),
      );

      final tree = await StoryWorldTreeStore(
        preferences,
      ).readForConversation(widget.conversationId);
      if (tree != null) {
        final voiceStore = StoryVoiceRoutingStore(preferences);
        final routing = await voiceStore.readOrDefault(tree.worldTreeId);
        var changed = false;
        final assignments = <StoryVoiceAssignment>[
          for (final assignment in routing.assignments)
            if (assignment.characterId == character.characterId) ...[
              assignment.copyWith(
                metadata: <String, Object?>{
                  ...assignment.metadata,
                  'displayName': name,
                },
                revision: assignment.revision + 1,
              ),
            ] else ...[
              assignment,
            ],
        ];
        for (var index = 0; index < routing.assignments.length; index++) {
          if (!identical(assignments[index], routing.assignments[index])) {
            changed = true;
            break;
          }
        }
        if (changed) {
          await voiceStore.upsertState(
            StoryVoiceRoutingState(
              worldTreeId: routing.worldTreeId,
              narrator: routing.narrator,
              assignments: assignments,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zh ? '角色名称已修正。' : 'Character name updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '角色名称保存失败：$error' : 'Failed to save character name: $error',
          ),
        ),
      );
    }
  }

  void _openVoices() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            StoryVoiceManagerPage(conversationId: widget.conversationId),
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
              subtitle: tr('稍后返回故事再试。', 'Return to the story and try again.'),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tr('修正名称', 'Edit name'),
                        onPressed: () => _editCharacterName(character),
                        icon: const Icon(Lucide.Pencil),
                      ),
                      Icon(
                        Lucide.ChevronRight,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
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
    required this.characterId,
    required this.displayName,
    this.voiceName,
  });

  final String characterId;
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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
