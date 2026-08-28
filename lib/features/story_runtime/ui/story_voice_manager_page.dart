import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/tts/network_tts.dart';
import '../../../icons/lucide_adapter.dart';
import '../../settings/pages/tts_services_page.dart';
import '../state/story_scene_runtime_state.dart';
import '../voice/story_voice_routing.dart';
import '../voice/story_voice_store.dart';
import '../world_tree/story_world_tree_store.dart';
import 'story_native_settings_widgets.dart';

class StoryVoiceManagerPage extends StatefulWidget {
  const StoryVoiceManagerPage({
    super.key,
    required this.conversationId,
  });

  final String conversationId;

  @override
  State<StoryVoiceManagerPage> createState() => _StoryVoiceManagerPageState();
}

class _StoryVoiceManagerPageState extends State<StoryVoiceManagerPage> {
  bool _loading = true;
  bool _busy = false;
  String? _worldTreeId;
  StorySceneRuntimeState? _scene;
  StoryVoiceRoutingState? _routing;
  List<TtsServiceOptions> _services = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _reload();
  }

  Future<void> _reload() async {
    try {
      final preferences = context.read<BusinessPreferences>();
      final settings = context.read<SettingsProvider>();
      final tree = await StoryWorldTreeStore(
        preferences,
      ).readForConversation(widget.conversationId);
      final scene = await StorySceneRuntimeStore(
        preferences,
      ).readOrDefault(widget.conversationId);
      final routing = tree == null
          ? null
          : await StoryVoiceRoutingStore(
              preferences,
            ).readOrDefault(tree.worldTreeId);
      final services = settings.ttsServices
          .where((service) => service.enabled)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _worldTreeId = tree?.worldTreeId;
        _scene = scene;
        _routing = routing;
        _services = services;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('声音暂时无法加载。');
    }
  }

  Future<void> _editNarrator() async {
    await _editAssignment(
      displayName: Localizations.localeOf(context).languageCode == 'zh'
          ? '旁白'
          : 'Narrator',
      characterId: '__narrator__',
      current: _routing?.narrator,
      narrator: true,
    );
  }

  Future<void> _editCharacter(
    String characterId,
    StoryVoiceAssignment? current,
    int index,
  ) async {
    await _editAssignment(
      displayName: _characterName(characterId, current, index),
      characterId: characterId,
      current: current,
      narrator: false,
    );
  }

  Future<void> _editAssignment({
    required String displayName,
    required String characterId,
    required StoryVoiceAssignment? current,
    required bool narrator,
  }) async {
    final treeId = _worldTreeId;
    if (treeId == null) {
      _message(
        Localizations.localeOf(context).languageCode == 'zh'
            ? '开始故事后即可固定声音。'
            : 'Start the story before assigning a persistent voice.',
      );
      return;
    }
    if (_services.isEmpty) {
      _message(
        Localizations.localeOf(context).languageCode == 'zh'
            ? '请先在声音服务中启用至少一个声音来源。'
            : 'Enable at least one voice source first.',
      );
      return;
    }

    final selected = await showModalBottomSheet<_VoiceEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _VoiceEditorSheet(
        title: displayName,
        services: _services,
        current: current,
      ),
    );
    if (selected == null || _busy) return;

    setState(() => _busy = true);
    try {
      final store = StoryVoiceRoutingStore(
        context.read<BusinessPreferences>(),
      );
      final state = await store.readOrDefault(treeId);
      final assignment = StoryVoiceAssignment(
        characterId: characterId,
        ttsServiceId: selected.serviceId,
        voiceId: selected.voiceName,
        personaDescription: selected.performance,
        modelOverride: current?.modelOverride,
        worldlineId: current?.worldlineId,
        revision: (current?.revision ?? 0) + 1,
        lockContinuity: current?.lockContinuity ?? true,
        metadata: current?.metadata ?? const <String, Object?>{},
      );
      if (narrator) {
        await store.upsertState(
          StoryVoiceRoutingState(
            worldTreeId: state.worldTreeId,
            narrator: assignment,
            assignments: state.assignments,
          ),
        );
      } else {
        await store.upsertCharacterAssignment(
          worldTreeId: state.worldTreeId,
          assignment: assignment,
        );
      }
      await _reload();
    } catch (_) {
      _message(
        Localizations.localeOf(context).languageCode == 'zh'
            ? '保存声音失败。'
            : 'Could not save the voice.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _characterName(
    String characterId,
    StoryVoiceAssignment? assignment,
    int index,
  ) {
    for (final key in const ['displayName', 'name', 'label']) {
      final value = assignment?.metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final continuity = _scene?.continuityState ?? const <String, Object?>{};
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
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '角色 ${index + 1}'
        : 'Character ${index + 1}';
  }

  List<String> _characterIds() {
    final ids = <String>{
      ...?_scene?.participantCharacterIds,
      ...?_routing?.assignments.map((item) => item.characterId),
    }..remove('__narrator__');
    return ids.toList()..sort();
  }

  StoryVoiceAssignment? _assignmentFor(String characterId) {
    StoryVoiceAssignment? fallback;
    for (final assignment
        in _routing?.assignments ?? const <StoryVoiceAssignment>[]) {
      if (assignment.characterId != characterId) continue;
      fallback ??= assignment;
      if (assignment.worldlineId == null) return assignment;
    }
    return fallback;
  }

  void _openVoiceServices() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TtsServicesPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zhText, String enText) => zh ? zhText : enText;
    final characterIds = _characterIds();

    return Scaffold(
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('声音', 'Voices')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StoryNativeSection(
                  title: tr('故事声音', 'Story voices'),
                  first: true,
                  footer: tr(
                    '同一个声音来源可以给多个角色使用不同声音；情绪、语速和语气会根据故事上下文动态调整。',
                    'One voice source can serve multiple characters with different voices. Delivery adapts to story context.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr('旁白', 'Narrator'),
                      subtitle: _routing?.narrator?.voiceId ?? tr('自动', 'Auto'),
                      icon: Lucide.Volume2,
                      onTap: _busy ? null : _editNarrator,
                    ),
                    for (var index = 0; index < characterIds.length; index++)
                      StoryNativeRow(
                        title: _characterName(
                          characterIds[index],
                          _assignmentFor(characterIds[index]),
                          index,
                        ),
                        subtitle: _assignmentFor(characterIds[index])?.voiceId ??
                            tr('自动', 'Auto'),
                        icon: Lucide.User,
                        onTap: _busy
                            ? null
                            : () => _editCharacter(
                                  characterIds[index],
                                  _assignmentFor(characterIds[index]),
                                  index,
                                ),
                      ),
                    if (characterIds.isEmpty)
                      StoryNativeRow(
                        title: tr(
                          '角色声音会自动出现',
                          'Character voices appear automatically',
                        ),
                        subtitle: tr(
                          '角色参与故事后，可在这里固定或调整声音。',
                          'Once characters join the story, their voices can be fixed or adjusted here.',
                        ),
                        icon: Lucide.User,
                        enabled: false,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('更多', 'More'),
                  children: [
                    StoryNativeRow(
                      title: tr('声音服务设置', 'Voice service settings'),
                      subtitle: tr(
                        '配置本地或网络声音来源。',
                        'Configure local or network voice sources.',
                      ),
                      icon: Lucide.Settings,
                      onTap: _openVoiceServices,
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
    );
  }
}

class _VoiceEditorSheet extends StatefulWidget {
  const _VoiceEditorSheet({
    required this.title,
    required this.services,
    required this.current,
  });

  final String title;
  final List<TtsServiceOptions> services;
  final StoryVoiceAssignment? current;

  @override
  State<_VoiceEditorSheet> createState() => _VoiceEditorSheetState();
}

class _VoiceEditorSheetState extends State<_VoiceEditorSheet> {
  late String _serviceId;
  late final TextEditingController _voiceController;
  late final TextEditingController _performanceController;

  @override
  void initState() {
    super.initState();
    final currentService = widget.current?.ttsServiceId;
    _serviceId = widget.services.any((item) => item.id == currentService)
        ? currentService!
        : widget.services.first.id;
    _voiceController = TextEditingController(text: widget.current?.voiceId ?? '');
    _performanceController = TextEditingController(
      text: widget.current?.personaDescription ?? '',
    );
  }

  @override
  void dispose() {
    _voiceController.dispose();
    _performanceController.dispose();
    super.dispose();
  }

  String _serviceLabel(TtsServiceOptions service) {
    final name = service.name.trim();
    return name.isEmpty ? service.kind.name : name;
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zhText, String enText) => zh ? zhText : enText;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _serviceId,
            decoration: InputDecoration(labelText: tr('声音来源', 'Voice source')),
            items: [
              for (final service in widget.services)
                DropdownMenuItem(
                  value: service.id,
                  child: Text(_serviceLabel(service)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _serviceId = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _voiceController,
            decoration: InputDecoration(labelText: tr('声音', 'Voice')),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _performanceController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: tr('表达方式', 'Performance'),
              hintText: tr(
                '例如：克制、偏年轻、语速稍慢',
                'For example: restrained, youthful, slightly slower',
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              final voice = _voiceController.text.trim();
              if (voice.isEmpty) return;
              Navigator.of(context).pop(
                _VoiceEditResult(
                  serviceId: _serviceId,
                  voiceName: voice,
                  performance: _performanceController.text.trim(),
                ),
              );
            },
            child: Text(tr('保存', 'Save')),
          ),
        ],
      ),
    );
  }
}

class _VoiceEditResult {
  const _VoiceEditResult({
    required this.serviceId,
    required this.voiceName,
    required this.performance,
  });

  final String serviceId;
  final String voiceName;
  final String performance;
}
