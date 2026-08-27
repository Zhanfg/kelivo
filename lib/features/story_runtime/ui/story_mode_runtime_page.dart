import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../agency/story_agency_policy.dart';
import '../orchestration/story_break_armor_mode.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import '../voice/story_voice_routing.dart';
import '../voice/story_voice_store.dart';
import '../world_tree/story_world_tree_store.dart';
import 'story_native_settings_widgets.dart';

/// Lifecycle-safe Story Mode control surface.
///
/// This page intentionally avoids `context.watch` subscriptions. Story Mode is
/// a settings/control surface, so provider snapshots are read after the first
/// frame and copied into local state. This keeps route deactivation independent
/// from Provider/InheritedWidget dependency teardown and avoids the
/// `_dependents.isEmpty` assertion observed in Android debug builds.
class StoryModeRuntimePage extends StatefulWidget {
  const StoryModeRuntimePage({super.key});

  @override
  State<StoryModeRuntimePage> createState() => _StoryModeRuntimePageState();
}

class _StoryModeRuntimePageState extends State<StoryModeRuntimePage> {
  bool _ready = false;
  bool _loading = true;
  bool _busy = false;
  bool _breakArmorEnabled = false;

  late StoryRuntimeStore _runtimeStore;
  late StoryBreakArmorMode _breakArmorMode;
  late StoryWorldTreeStore _worldTreeStore;
  late StoryVoiceRoutingStore _voiceStore;

  List<Conversation> _conversations = const <Conversation>[];
  String? _selectedConversationId;
  StoryRuntimeSessionState? _session;
  String? _assistantName;
  String? _storyWorldTreeId;
  StoryVoiceAssignment? _narrator;
  String? _narratorServiceId;
  bool _narratorWorldlineScoped = false;
  List<String> _ttsServiceIds = const <String>[];
  Map<String, String> _ttsServiceLabels = const <String, String>{};

  final TextEditingController _narratorVoiceController =
      TextEditingController();
  final TextEditingController _narratorPersonaController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  Future<void> _initialize() async {
    if (_ready) return;
    final preferences = context.read<BusinessPreferences>();
    _runtimeStore = StoryRuntimeStore(preferences);
    _breakArmorMode = StoryBreakArmorMode(preferences);
    _worldTreeStore = StoryWorldTreeStore(preferences);
    _voiceStore = StoryVoiceRoutingStore(preferences);
    _ready = true;
    await _reload(selectNewestIfNeeded: true);
  }

  Future<void> _reload({bool selectNewestIfNeeded = false}) async {
    if (!_ready) return;
    if (mounted) setState(() => _loading = true);
    try {
      final chatService = context.read<ChatService>();
      final assistantProvider = context.read<AssistantProvider>();
      final settingsProvider = context.read<SettingsProvider>();

      final conversations = chatService.getAllConversations().toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      var selectedId = _selectedConversationId;
      if (selectNewestIfNeeded ||
          selectedId == null ||
          !conversations.any((item) => item.id == selectedId)) {
        selectedId = conversations.isEmpty ? null : conversations.first.id;
      }

      Conversation? selected;
      if (selectedId != null) {
        for (final item in conversations) {
          if (item.id == selectedId) {
            selected = item;
            break;
          }
        }
      }

      final session = selectedId == null
          ? null
          : await _runtimeStore.readOrDefault(selectedId);
      final tree = selectedId == null
          ? null
          : await _worldTreeStore.readForConversation(selectedId);
      final voiceRouting = tree == null
          ? null
          : await _voiceStore.readOrDefault(tree.worldTreeId);
      final narrator = voiceRouting?.narrator;

      String? assistantName;
      if (selected != null) {
        final assistant = selected.assistantId == null
            ? assistantProvider.currentAssistant
            : assistantProvider.getById(selected.assistantId!);
        assistantName = assistant?.name;
      }

      final serviceIds = <String>[];
      final serviceLabels = <String, String>{};
      for (final service in settingsProvider.ttsServices) {
        if (!service.enabled) continue;
        serviceIds.add(service.id);
        final name = service.name.trim();
        serviceLabels[service.id] = name.isEmpty ? service.kind.name : name;
      }

      if (!mounted) return;
      setState(() {
        _conversations = List.unmodifiable(conversations);
        _selectedConversationId = selectedId;
        _session = session;
        _assistantName = assistantName;
        _storyWorldTreeId = tree?.worldTreeId;
        _narrator = narrator;
        _narratorServiceId = narrator?.ttsServiceId;
        _narratorWorldlineScoped = narrator?.worldlineId != null;
        _narratorVoiceController.text = narrator?.voiceId ?? '';
        _narratorPersonaController.text = narrator?.personaDescription ?? '';
        _ttsServiceIds = List.unmodifiable(serviceIds);
        _ttsServiceLabels = Map.unmodifiable(serviceLabels);
        _breakArmorEnabled = _breakArmorMode.enabled;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _selectConversation(String? value) async {
    if (value == null || value == _selectedConversationId) return;
    setState(() => _selectedConversationId = value);
    await _reload();
  }

  Future<void> _runBusy(
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (reload) await _reload();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStoryEnabled(bool enabled) async {
    final id = _selectedConversationId;
    if (id == null) return;
    await _runBusy(() => _runtimeStore.setEnabled(id, enabled));
  }

  Future<void> _setBreakArmorEnabled(bool enabled) async {
    await _runBusy(() async {
      await _breakArmorMode.setEnabled(enabled);
      _breakArmorEnabled = enabled;
    }, reload: false);
  }

  Future<void> _setAgencyMode(StoryAgencyMode mode) async {
    final session = _session;
    if (session == null) return;
    await _runBusy(
      () => _runtimeStore.upsert(session.copyWith(agencyMode: mode)),
    );
  }

  Future<void> _saveNarratorVoice() async {
    final treeId = _storyWorldTreeId;
    final serviceId = _narratorServiceId?.trim() ?? '';
    final voiceId = _narratorVoiceController.text.trim();
    if (treeId == null) {
      _showMessage('请先启用故事模式并完成至少一个故事回合。');
      return;
    }
    if (serviceId.isEmpty || voiceId.isEmpty) {
      _showMessage('请选择 TTS 服务并填写 Voice ID。');
      return;
    }
    await _runBusy(() async {
      final current = await _voiceStore.readOrDefault(treeId);
      final assignment = StoryVoiceAssignment(
        characterId: '__narrator__',
        ttsServiceId: serviceId,
        voiceId: voiceId,
        personaDescription: _narratorPersonaController.text.trim(),
        worldlineId: _narratorWorldlineScoped ? _session?.worldlineId : null,
        revision: (_narrator?.revision ?? 0) + 1,
      );
      await _voiceStore.upsertState(
        StoryVoiceRoutingState(
          worldTreeId: current.worldTreeId,
          narrator: assignment,
          assignments: current.assignments,
        ),
      );
    });
  }

  Future<void> _clearNarratorVoice() async {
    final treeId = _storyWorldTreeId;
    if (treeId == null) return;
    await _runBusy(() async {
      final current = await _voiceStore.readOrDefault(treeId);
      await _voiceStore.upsertState(
        StoryVoiceRoutingState(
          worldTreeId: current.worldTreeId,
          assignments: current.assignments,
        ),
      );
    });
  }

  String _conversationLabel(String id, bool zh) {
    for (final conversation in _conversations) {
      if (conversation.id == id) {
        final title = conversation.title.trim();
        return title.isEmpty ? (zh ? '未命名会话' : 'Untitled') : title;
      }
    }
    return zh ? '未命名会话' : 'Untitled';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error) => _showMessage('操作失败：$error');

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zhText, String enText) => zh ? zhText : enText;
    final session = _session;
    final selectedId = _selectedConversationId;
    final narratorServiceId = _ttsServiceIds.contains(_narratorServiceId)
        ? _narratorServiceId
        : null;

    return Scaffold(
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('故事模式', 'Story Mode')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StoryNativeSection(
                  key: const ValueKey('story-runtime-section'),
                  title: tr('故事运行时', 'Story Runtime'),
                  first: true,
                  footer: tr(
                    'Skills 与参考文本是独立能力；这里只控制当前会话的故事运行时。',
                    'Skills and reference texts are independent capabilities; this page controls Story Runtime for the current conversation.',
                  ),
                  children: [
                    if (_conversations.isNotEmpty)
                      StoryNativeSelectRow<String>(
                        key: const ValueKey('story-conversation-row'),
                        label: tr('会话', 'Conversation'),
                        icon: Lucide.MessageCircle,
                        value: selectedId ?? _conversations.first.id,
                        options: _conversations.map((item) => item.id).toList(),
                        labelFor: (id) => _conversationLabel(id, zh),
                        onSelected: _busy ? null : _selectConversation,
                      )
                    else
                      StoryNativeRow(
                        key: const ValueKey('story-no-conversation-row'),
                        title: tr('没有可用会话', 'No conversations'),
                        subtitle: tr('先创建一个聊天会话。', 'Create a chat first.'),
                        icon: Lucide.MessageCircle,
                        enabled: false,
                      ),
                    StoryNativeRow(
                      key: const ValueKey('story-assistant-row'),
                      title: 'Assistant',
                      subtitle: _assistantName ?? tr('默认 Assistant', 'Default'),
                      icon: Lucide.Bot,
                    ),
                    StoryNativeSwitchRow(
                      key: const ValueKey('story-enable-row'),
                      title: tr('启用故事模式', 'Enable Story Mode'),
                      subtitle: tr(
                        '开启 World Tree、世界线记忆、Story Runtime 与故事能力编排。',
                        'Enables World Tree, worldline memory, Story Runtime and story capability orchestration.',
                      ),
                      icon: Lucide.Compass,
                      value: session?.enabled ?? false,
                      onChanged: _busy || selectedId == null
                          ? null
                          : _setStoryEnabled,
                    ),
                    StoryNativeSwitchRow(
                      key: const ValueKey('story-break-armor-row'),
                      title: tr('叙事约束增强', 'Narrative guardrails'),
                      subtitle: tr(
                        '只在故事模式开启时生效，不影响普通聊天。',
                        'Only affects Story Mode; normal chat is unchanged.',
                      ),
                      icon: Lucide.Shield,
                      value: _breakArmorEnabled,
                      onChanged: _busy ? null : _setBreakArmorEnabled,
                    ),
                    if (session != null)
                      StoryNativeSelectRow<StoryAgencyMode>(
                        key: const ValueKey('story-agency-row'),
                        label: tr('用户自主权', 'User agency'),
                        icon: Lucide.User,
                        value: session.agencyMode,
                        options: StoryAgencyMode.values,
                        labelFor: (mode) => switch (mode) {
                          StoryAgencyMode.manual => 'Manual',
                          StoryAgencyMode.balanced => 'Balanced',
                          StoryAgencyMode.cinematic => 'Cinematic',
                        },
                        onSelected: _busy ? null : _setAgencyMode,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  key: const ValueKey('story-status-section'),
                  title: tr('运行状态', 'Runtime status'),
                  children: [
                    StoryNativeRow(
                      key: const ValueKey('story-worldline-status'),
                      title: 'Worldline',
                      subtitle: session?.worldlineId ?? tr('尚未建立', 'Not created'),
                      icon: Lucide.GitFork,
                      enabled: false,
                    ),
                    StoryNativeRow(
                      key: const ValueKey('story-scene-status'),
                      title: tr('场景修订', 'Scene revision'),
                      subtitle: '${session?.sceneRevision ?? 0}',
                      icon: Lucide.History,
                      enabled: false,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  key: const ValueKey('story-voice-section'),
                  title: tr('故事语音', 'Story Voice'),
                  footer: tr(
                    '复用 Kelivo 已启用的网络 TTS；这里只保存服务、Voice ID 与表达描述。',
                    'Reuses enabled Kelivo network TTS; only service, Voice ID and performance direction are stored here.',
                  ),
                  children: [
                    StoryNativeSelectRow<String>(
                      key: const ValueKey('story-tts-service-row'),
                      label: tr('旁白 TTS 服务', 'Narrator TTS service'),
                      icon: Lucide.Volume2,
                      value: narratorServiceId ?? '',
                      options: <String>['', ..._ttsServiceIds],
                      labelFor: (id) => id.isEmpty
                          ? tr('未选择', 'Not selected')
                          : (_ttsServiceLabels[id] ?? id),
                      onSelected: _busy
                          ? null
                          : (value) => setState(
                              () => _narratorServiceId = value.isEmpty ? null : value,
                            ),
                    ),
                    StoryNativeTextFieldRow(
                      key: const ValueKey('story-voice-id-row'),
                      label: tr('Voice ID / 音色名', 'Voice ID'),
                      controller: _narratorVoiceController,
                      enabled: !_busy,
                    ),
                    StoryNativeTextFieldRow(
                      key: const ValueKey('story-voice-persona-row'),
                      label: tr('表达描述', 'Performance direction'),
                      controller: _narratorPersonaController,
                      enabled: !_busy,
                      minLines: 2,
                      maxLines: 4,
                    ),
                    StoryNativeSwitchRow(
                      key: const ValueKey('story-voice-scope-row'),
                      title: tr('仅当前 Worldline 使用', 'Current worldline only'),
                      icon: Lucide.GitFork,
                      value: _narratorWorldlineScoped && session?.worldlineId != null,
                      onChanged: _busy || session?.worldlineId == null
                          ? null
                          : (value) => setState(
                              () => _narratorWorldlineScoped = value,
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: StoryNativeButton(
                              label: tr('保存旁白音色', 'Save narrator voice'),
                              icon: Lucide.Check,
                              primary: true,
                              enabled: !_busy && _storyWorldTreeId != null,
                              onTap: _saveNarratorVoice,
                            ),
                          ),
                          if (_narrator != null) ...[
                            const SizedBox(width: 8),
                            StoryNativeButton(
                              label: tr('清除', 'Clear'),
                              icon: Lucide.Trash2,
                              enabled: !_busy,
                              onTap: _clearNarratorVoice,
                            ),
                          ],
                        ],
                      ),
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

  @override
  void dispose() {
    _narratorVoiceController.dispose();
    _narratorPersonaController.dispose();
    super.dispose();
  }
}
