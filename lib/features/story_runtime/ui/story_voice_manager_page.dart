import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/tts/network_tts.dart';
import '../../../icons/lucide_adapter.dart';
import '../../settings/pages/tts_services_page.dart';
import '../state/story_scene_runtime_state.dart';
import '../voice/story_voice_playback_service.dart';
import '../voice/story_voice_routing.dart';
import '../voice/story_voice_store.dart';
import '../world_tree/story_world_tree_store.dart';
import 'story_native_settings_widgets.dart';

class StoryVoiceManagerPage extends StatefulWidget {
  const StoryVoiceManagerPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<StoryVoiceManagerPage> createState() => _StoryVoiceManagerPageState();
}

class _StoryVoiceManagerPageState extends State<StoryVoiceManagerPage> {
  bool _loading = true;
  bool _busy = false;
  bool _localInstalled = false;
  bool _localReady = false;
  String? _worldTreeId;
  StorySceneRuntimeState? _scene;
  StoryVoiceRoutingState? _routing;
  List<TtsServiceOptions> _services = const [];
  final Set<String> _selectedCharacters = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _reload();
  }

  Future<void> _reload() async {
    try {
      final preferences = context.read<BusinessPreferences>();
      final settings = context.read<SettingsProvider>();
      final tts = context.read<TtsProvider>();
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
      var localInstalled = false;
      var localReady = false;
      try {
        localInstalled = await tts.isLocalTtsInstalled();
        if (localInstalled) localReady = await tts.isLocalTtsReady();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _worldTreeId = tree?.worldTreeId;
        _scene = scene;
        _routing = routing;
        _services = services;
        _localInstalled = localInstalled;
        _localReady = localReady;
        _selectedCharacters.removeWhere(
          (id) => !_characterIdsFrom(scene, routing).contains(id),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('声音暂时无法加载。');
    }
  }

  List<_VoiceSource> _sources() {
    final sources = <_VoiceSource>[
      _VoiceSource(
        id: storySystemTtsServiceId,
        label: '系统 TTS',
        defaultVoice: 'system',
      ),
      if (_localInstalled)
        _VoiceSource(
          id: storyLocalMossTtsServiceId,
          label: _localReady ? 'MOSS TTS Nano · 本地' : 'MOSS TTS Nano · 未就绪',
          defaultVoice: 'Junhao',
          enabled: _localReady,
        ),
      for (final service in _services)
        _VoiceSource(
          id: service.id,
          label: service.name.trim().isEmpty ? service.kind.name : service.name,
          defaultVoice: '',
        ),
    ];
    return sources;
  }

  Future<_VoiceEditResult?> _showEditor({
    required String title,
    StoryVoiceAssignment? current,
  }) {
    final sources = _sources();
    if (sources.where((source) => source.enabled).isEmpty) {
      _message('当前没有可用声音来源。');
      return Future.value(null);
    }
    return showModalBottomSheet<_VoiceEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _VoiceEditorSheet(
        title: title,
        sources: sources,
        services: _services,
        current: current,
      ),
    );
  }

  Future<void> _editNarrator() async {
    final selected = await _showEditor(
      title: Localizations.localeOf(context).languageCode == 'zh'
          ? '旁白'
          : 'Narrator',
      current: _routing?.narrator,
    );
    if (selected == null) return;
    await _saveAssignment(
      characterId: '__narrator__',
      result: selected,
      current: _routing?.narrator,
      narrator: true,
    );
  }

  Future<void> _editCharacter(
    String characterId,
    StoryVoiceAssignment? current,
    int index,
  ) async {
    final selected = await _showEditor(
      title: _characterName(characterId, current, index),
      current: current,
    );
    if (selected == null) return;
    await _saveAssignment(
      characterId: characterId,
      result: selected,
      current: current,
      narrator: false,
    );
  }

  Future<void> _editSelectedCharacters() async {
    if (_selectedCharacters.isEmpty || _busy) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final selected = await _showEditor(
      title: zh
          ? '批量设置 ${_selectedCharacters.length} 个角色'
          : 'Set ${_selectedCharacters.length} characters',
    );
    if (selected == null || _busy) return;
    final treeId = _worldTreeId;
    if (treeId == null) return;
    setState(() => _busy = true);
    try {
      final store = StoryVoiceRoutingStore(context.read<BusinessPreferences>());
      for (final characterId in _selectedCharacters) {
        final current = _assignmentFor(characterId);
        await store.upsertCharacterAssignment(
          worldTreeId: treeId,
          assignment: StoryVoiceAssignment(
            characterId: characterId,
            ttsServiceId: selected.serviceId,
            voiceId: selected.voiceName,
            personaDescription: selected.performance,
            modelOverride: current?.modelOverride,
            worldlineId: current?.worldlineId,
            revision: (current?.revision ?? 0) + 1,
            lockContinuity: current?.lockContinuity ?? true,
            metadata: current?.metadata ?? const <String, Object?>{},
          ),
        );
      }
      if (mounted) {
        _message(zh ? '已批量更新角色声音。' : 'Character voices updated.');
        setState(() => _selectedCharacters.clear());
      }
      await _reload();
    } catch (_) {
      _message(zh ? '批量保存声音失败。' : 'Could not save voices.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAssignment({
    required String characterId,
    required _VoiceEditResult result,
    required StoryVoiceAssignment? current,
    required bool narrator,
  }) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final treeId = _worldTreeId;
    if (treeId == null || _busy) {
      _message(
        zh
            ? '开始故事后即可固定声音。'
            : 'Start the story before assigning a persistent voice.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final store = StoryVoiceRoutingStore(context.read<BusinessPreferences>());
      final state = await store.readOrDefault(treeId);
      final assignment = StoryVoiceAssignment(
        characterId: characterId,
        ttsServiceId: result.serviceId,
        voiceId: result.voiceName,
        personaDescription: result.performance,
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
      _message(zh ? '保存声音失败。' : 'Could not save the voice.');
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

  List<String> _characterIds() => _characterIdsFrom(_scene, _routing);

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

  String _sourceLabel(StoryVoiceAssignment? assignment) {
    if (assignment == null) return '自动';
    if (assignment.ttsServiceId == storyLocalMossTtsServiceId) {
      return 'MOSS TTS Nano · ${assignment.voiceId}';
    }
    if (assignment.ttsServiceId == storySystemTtsServiceId) return '系统 TTS';
    for (final service in _services) {
      if (service.id == assignment.ttsServiceId) {
        final name = service.name.trim().isEmpty ? service.kind.name : service.name;
        return '$name · ${assignment.voiceId}';
      }
    }
    return assignment.voiceId;
  }

  void _toggleSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedCharacters.add(id);
      } else {
        _selectedCharacters.remove(id);
      }
    });
  }

  void _toggleAll(List<String> ids) {
    setState(() {
      if (_selectedCharacters.length == ids.length && ids.isNotEmpty) {
        _selectedCharacters.clear();
      } else {
        _selectedCharacters
          ..clear()
          ..addAll(ids);
      }
    });
  }

  void _openVoiceServices() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TtsServicesPage()));
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zhText, String enText) => zh ? zhText : enText;
    final characterIds = _characterIds();
    final allSelected =
        characterIds.isNotEmpty && _selectedCharacters.length == characterIds.length;

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
                    '声音来源复用 Kelivo 原生 TTS。可使用系统 TTS、本地 MOSS 或已配置的网络声音服务。',
                    'Voice sources reuse Kelivo native TTS: system, local MOSS, or configured network services.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr('旁白', 'Narrator'),
                      subtitle: _sourceLabel(_routing?.narrator),
                      icon: Lucide.Volume2,
                      onTap: _busy ? null : _editNarrator,
                    ),
                    if (characterIds.isNotEmpty)
                      StoryNativeRow(
                        title: allSelected
                            ? tr('取消全选', 'Clear selection')
                            : tr('全选角色', 'Select all characters'),
                        subtitle: tr(
                          '已选择 ${_selectedCharacters.length} / ${characterIds.length}',
                          '${_selectedCharacters.length} / ${characterIds.length} selected',
                        ),
                        icon: Lucide.ListChecks,
                        onTap: _busy ? null : () => _toggleAll(characterIds),
                      ),
                    for (var index = 0; index < characterIds.length; index++)
                      StoryNativeRow(
                        title: _characterName(
                          characterIds[index],
                          _assignmentFor(characterIds[index]),
                          index,
                        ),
                        subtitle: _sourceLabel(
                          _assignmentFor(characterIds[index]),
                        ),
                        icon: Lucide.User,
                        onTap: _busy
                            ? null
                            : () => _editCharacter(
                                characterIds[index],
                                _assignmentFor(characterIds[index]),
                                index,
                              ),
                        trailing: Checkbox(
                          value: _selectedCharacters.contains(characterIds[index]),
                          onChanged: _busy
                              ? null
                              : (value) => _toggleSelected(
                                  characterIds[index],
                                  value == true,
                                ),
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
                if (_selectedCharacters.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  StoryNativeSection(
                    title: tr('批量操作', 'Batch actions'),
                    children: [
                      StoryNativeRow(
                        title: tr('批量分配声音', 'Assign voice to selected'),
                        subtitle: tr(
                          '一次应用到 ${_selectedCharacters.length} 个角色。',
                          'Apply once to ${_selectedCharacters.length} characters.',
                        ),
                        icon: Lucide.Users,
                        onTap: _busy ? null : _editSelectedCharacters,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('声音来源', 'Voice sources'),
                  children: [
                    StoryNativeRow(
                      title: tr('系统 TTS', 'System TTS'),
                      subtitle: tr('使用设备系统语音引擎。', 'Use the device system voice engine.'),
                      icon: Lucide.Smartphone,
                      enabled: false,
                    ),
                    StoryNativeRow(
                      title: 'MOSS TTS Nano',
                      subtitle: !_localInstalled
                          ? tr('未安装本地模型。', 'Local model is not installed.')
                          : _localReady
                          ? tr('本地运行时可用。', 'Local runtime is ready.')
                          : tr('模型已安装，但本地运行时未就绪。', 'Model installed, runtime not ready.'),
                      icon: Lucide.Cpu,
                      enabled: false,
                    ),
                    for (final service in _services)
                      StoryNativeRow(
                        title: service.name.trim().isEmpty
                            ? service.kind.name
                            : service.name,
                        subtitle: tr('网络声音服务', 'Network voice service'),
                        icon: Lucide.Cloud,
                        enabled: false,
                      ),
                    StoryNativeRow(
                      title: tr('管理声音服务', 'Manage voice services'),
                      subtitle: tr(
                        '配置本地模型、系统 TTS 或网络声音来源。',
                        'Configure local, system or network voice sources.',
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

List<String> _characterIdsFrom(
  StorySceneRuntimeState? scene,
  StoryVoiceRoutingState? routing,
) {
  final ids = <String>{
    ...?scene?.participantCharacterIds,
    ...?routing?.assignments.map((item) => item.characterId),
  }..remove('__narrator__');
  return ids.toList()..sort();
}

class _VoiceSource {
  const _VoiceSource({
    required this.id,
    required this.label,
    required this.defaultVoice,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String defaultVoice;
  final bool enabled;
}

class _VoiceEditorSheet extends StatefulWidget {
  const _VoiceEditorSheet({
    required this.title,
    required this.sources,
    required this.services,
    required this.current,
  });

  final String title;
  final List<_VoiceSource> sources;
  final List<TtsServiceOptions> services;
  final StoryVoiceAssignment? current;

  @override
  State<_VoiceEditorSheet> createState() => _VoiceEditorSheetState();
}

class _VoiceEditorSheetState extends State<_VoiceEditorSheet> {
  late String _serviceId;
  late final TextEditingController _voiceController;
  late final TextEditingController _performanceController;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    final currentService = widget.current?.ttsServiceId;
    final enabledSources = widget.sources.where((source) => source.enabled).toList();
    _serviceId = enabledSources.any((item) => item.id == currentService)
        ? currentService!
        : enabledSources.first.id;
    _voiceController = TextEditingController(
      text: widget.current?.voiceId ?? _sourceById(_serviceId).defaultVoice,
    );
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

  _VoiceSource _sourceById(String id) =>
      widget.sources.firstWhere((source) => source.id == id);

  void _selectSource(String id) {
    final source = _sourceById(id);
    if (!source.enabled) return;
    setState(() {
      _serviceId = id;
      if (_voiceController.text.trim().isEmpty ||
          _serviceId == storySystemTtsServiceId ||
          _serviceId == storyLocalMossTtsServiceId) {
        _voiceController.text = source.defaultVoice;
      }
    });
  }

  Future<void> _preview() async {
    if (_previewing) return;
    final source = _sourceById(_serviceId);
    if (!source.enabled) return;
    var voice = _voiceController.text.trim();
    if (voice.isEmpty) voice = source.defaultVoice;
    if (voice.isEmpty) return;
    setState(() => _previewing = true);
    try {
      final service = StoryVoicePlaybackService(
        preferences: context.read<BusinessPreferences>(),
        ttsProvider: context.read<TtsProvider>(),
      );
      await service.speakAssignment(
        assignment: StoryVoiceAssignment(
          characterId: '__preview__',
          ttsServiceId: _serviceId,
          voiceId: voice,
          personaDescription: _performanceController.text.trim(),
        ),
        text: Localizations.localeOf(context).languageCode == 'zh'
            ? '这是声音预览。'
            : 'This is a voice preview.',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('预览失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zhText, String enText) => zh ? zhText : enText;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final enabledSourceIds = widget.sources
        .where((source) => source.enabled)
        .map((source) => source.id)
        .toList(growable: false);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              StoryNativeSection(
                title: tr('声音设置', 'Voice settings'),
                first: true,
                children: [
                  StoryNativeSelectRow<String>(
                    label: tr('声音来源', 'Voice source'),
                    icon: Lucide.Volume2,
                    value: _serviceId,
                    options: enabledSourceIds,
                    labelFor: (id) => _sourceById(id).label,
                    onSelected: _selectSource,
                  ),
                  if (_serviceId != storySystemTtsServiceId)
                    StoryNativeTextFieldRow(
                      label: tr('声音 / 音色', 'Voice'),
                      controller: _voiceController,
                      hintText: _serviceId == storyLocalMossTtsServiceId
                          ? 'Junhao'
                          : tr('填写服务支持的音色名', 'Voice id supported by the service'),
                    ),
                  StoryNativeTextFieldRow(
                    label: tr('表达方式', 'Performance'),
                    controller: _performanceController,
                    minLines: 2,
                    maxLines: 4,
                    hintText: tr(
                      '例如：克制、偏年轻、语速稍慢',
                      'For example: restrained, youthful, slightly slower',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: StoryNativeButton(
                      label: _previewing ? tr('预览中', 'Previewing') : tr('试听', 'Preview'),
                      icon: Lucide.Play,
                      enabled: !_previewing,
                      onTap: _preview,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StoryNativeButton(
                      label: tr('保存', 'Save'),
                      icon: Lucide.Check,
                      primary: true,
                      onTap: () {
                        final source = _sourceById(_serviceId);
                        var voice = _voiceController.text.trim();
                        if (voice.isEmpty) voice = source.defaultVoice;
                        if (voice.isEmpty) return;
                        Navigator.of(context).pop(
                          _VoiceEditResult(
                            serviceId: _serviceId,
                            voiceName: voice,
                            performance: _performanceController.text.trim(),
                          ),
                        );
                      },
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
