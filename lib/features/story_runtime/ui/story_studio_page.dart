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

class StoryStudioPage extends StatefulWidget {
  const StoryStudioPage({super.key});

  @override
  State<StoryStudioPage> createState() => _StoryStudioPageState();
}

class _StoryStudioPageState extends State<StoryStudioPage> {
  bool _initialized = false;
  bool _loading = true;
  bool _busy = false;
  bool _breakArmorEnabled = true;
  String? _selectedConversationId;

  late StoryRuntimeStore _runtimeStore;
  late StoryBreakArmorMode _breakArmorMode;
  late StoryWorldTreeStore _worldTreeStore;
  late StoryVoiceRoutingStore _voiceStore;

  StoryRuntimeSessionState? _session;
  String? _storyWorldTreeId;
  StoryVoiceAssignment? _narrator;
  String? _narratorServiceId;
  bool _narratorWorldlineScoped = false;
  final TextEditingController _narratorVoiceController =
      TextEditingController();
  final TextEditingController _narratorPersonaController =
      TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final preferences = context.read<BusinessPreferences>();
    _breakArmorMode = StoryBreakArmorMode(preferences);
    _breakArmorEnabled = _breakArmorMode.enabled;
    _runtimeStore = StoryRuntimeStore(preferences);
    _worldTreeStore = StoryWorldTreeStore(preferences);
    _voiceStore = StoryVoiceRoutingStore(preferences);
    _bootstrap();
  }

  List<Conversation> _conversations() {
    final conversations = context
        .read<ChatService>()
        .getAllConversations()
        .toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  Future<void> _bootstrap() async {
    final conversations = _conversations();
    _selectedConversationId = conversations.isEmpty
        ? null
        : conversations.first.id;
    await _reload();
  }

  Conversation? _selectedConversation() {
    final id = _selectedConversationId;
    if (id == null) return null;
    for (final conversation in _conversations()) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final conversationId = _selectedConversationId;
      final session = conversationId == null
          ? null
          : await _runtimeStore.readOrDefault(conversationId);
      final tree = conversationId == null
          ? null
          : await _worldTreeStore.readForConversation(conversationId);
      final voiceRouting = tree == null
          ? null
          : await _voiceStore.readOrDefault(tree.worldTreeId);
      final narrator = voiceRouting?.narrator;
      if (!mounted) return;
      setState(() {
        _session = session;
        _storyWorldTreeId = tree?.worldTreeId;
        _narrator = narrator;
        _narratorServiceId = narrator?.ttsServiceId;
        _narratorWorldlineScoped = narrator?.worldlineId != null;
        _narratorVoiceController.text = narrator?.voiceId ?? '';
        _narratorPersonaController.text = narrator?.personaDescription ?? '';
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

  Future<void> _setBreakArmorEnabled(bool enabled) async {
    await _runBusy(() async {
      await _breakArmorMode.setEnabled(enabled);
      _breakArmorEnabled = enabled;
    }, reload: false);
  }

  Future<void> _setStoryEnabled(bool enabled) async {
    final id = _selectedConversationId;
    if (id == null) return;
    await _runBusy(() => _runtimeStore.setEnabled(id, enabled));
  }

  Future<void> _setAgencyMode(StoryAgencyMode mode) async {
    final state = _session;
    if (state == null) return;
    await _runBusy(
      () => _runtimeStore.upsert(state.copyWith(agencyMode: mode)),
    );
  }

  Future<void> _saveNarratorVoice() async {
    final worldTreeId = _storyWorldTreeId;
    final serviceId = _narratorServiceId?.trim() ?? '';
    final voiceId = _narratorVoiceController.text.trim();
    if (worldTreeId == null) {
      _showMessage('请先启用故事模式并完成至少一个故事回合，再配置旁白音色。');
      return;
    }
    if (serviceId.isEmpty || voiceId.isEmpty) {
      _showMessage('请选择 TTS 服务并填写 Voice ID。');
      return;
    }

    await _runBusy(() async {
      final current = await _voiceStore.readOrDefault(worldTreeId);
      final scopedWorldlineId = _narratorWorldlineScoped
          ? _session?.worldlineId
          : null;
      final assignment = StoryVoiceAssignment(
        characterId: '__narrator__',
        ttsServiceId: serviceId,
        voiceId: voiceId,
        personaDescription: _narratorPersonaController.text.trim(),
        worldlineId: scopedWorldlineId,
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
    if (mounted) _showMessage('旁白音色已保存，并会复用 Kelivo 原生 TTS 服务。');
  }

  Future<void> _clearNarratorVoice() async {
    final worldTreeId = _storyWorldTreeId;
    if (worldTreeId == null) return;
    await _runBusy(() async {
      final current = await _voiceStore.readOrDefault(worldTreeId);
      await _voiceStore.upsertState(
        StoryVoiceRoutingState(
          worldTreeId: current.worldTreeId,
          assignments: current.assignments,
        ),
      );
    });
    if (mounted) _showMessage('旁白音色绑定已清除。');
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
      if (!reload && mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error) {
    _showMessage('操作失败：$error');
  }

  @override
  Widget build(BuildContext context) {
    final conversations = _conversations();
    final selectedConversation = _selectedConversation();
    final assistantProvider = context.watch<AssistantProvider>();
    final assistant = selectedConversation?.assistantId == null
        ? assistantProvider.currentAssistant
        : assistantProvider.getById(selectedConversation!.assistantId!);
    final settings = context.watch<SettingsProvider>();
    final enabledTtsServices = settings.ttsServices
        .where((service) => service.enabled)
        .toList(growable: false);
    final narratorServiceId =
        enabledTtsServices.any((service) => service.id == _narratorServiceId)
        ? _narratorServiceId
        : null;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zh, String en) => isZh ? zh : en;

    String conversationLabel(String id) {
      for (final conversation in conversations) {
        if (conversation.id == id) {
          return conversation.title.trim().isEmpty
              ? tr('未命名会话', 'Untitled conversation')
              : conversation.title;
        }
      }
      return tr('未命名会话', 'Untitled conversation');
    }

    String serviceLabel(String id) {
      if (id.isEmpty) return tr('未选择', 'Not selected');
      for (final service in enabledTtsServices) {
        if (service.id == id) {
          return service.name.trim().isEmpty ? service.kind.name : service.name;
        }
      }
      return tr('未选择', 'Not selected');
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                  title: tr('故事运行时', 'Story Runtime'),
                  first: true,
                  footer: tr(
                    '这里只管理当前故事会话的运行时行为。Skills 与参考文本在设置中独立管理。',
                    'This page only manages runtime behavior for story conversations. Skills and reference texts are managed independently in Settings.',
                  ),
                  children: [
                    StoryNativeSwitchRow(
                      title: tr('破甲模式', 'Break Armor'),
                      subtitle: tr(
                        '仅在故事模式启用时注入叙事约束，不影响普通聊天。',
                        'Injects narrative constraints only while Story Mode is enabled.',
                      ),
                      icon: Lucide.Shield,
                      value: _breakArmorEnabled,
                      onChanged: _busy ? null : _setBreakArmorEnabled,
                    ),
                    if (conversations.isNotEmpty)
                      StoryNativeSelectRow<String>(
                        label: tr('会话', 'Conversation'),
                        subtitle: tr(
                          '选择要应用故事运行时的现有会话。',
                          'Choose the existing conversation that should use Story Runtime.',
                        ),
                        icon: Lucide.MessageCircle,
                        value:
                            _selectedConversationId ?? conversations.first.id,
                        options: conversations.map((item) => item.id).toList(),
                        labelFor: conversationLabel,
                        onSelected: _busy ? null : _selectConversation,
                      )
                    else
                      StoryNativeRow(
                        title: tr('没有可用会话', 'No conversations'),
                        subtitle: tr(
                          '先创建一个聊天会话，再回来启用故事模式。',
                          'Create a chat conversation first, then return to enable Story Mode.',
                        ),
                        icon: Lucide.MessageCircle,
                        enabled: false,
                      ),
                    StoryNativeRow(
                      title: 'Assistant',
                      subtitle:
                          assistant?.name ??
                          tr('默认 Assistant', 'Default Assistant'),
                      icon: Lucide.Bot,
                    ),
                    StoryNativeSwitchRow(
                      title: tr('启用故事模式', 'Enable Story Mode'),
                      subtitle: tr(
                        '启用 World Tree、世界线记忆与 Story Runtime；不会在这里管理 Skills 或参考文本。',
                        'Enables World Tree, worldline memory and Story Runtime; Skills and reference texts are configured separately.',
                      ),
                      icon: Lucide.Map,
                      value: _session?.enabled ?? false,
                      onChanged: _busy || selectedConversation == null
                          ? null
                          : _setStoryEnabled,
                    ),
                    if (_session != null)
                      StoryNativeSelectRow<StoryAgencyMode>(
                        label: tr('用户自主权', 'User agency'),
                        subtitle: tr(
                          '控制运行时允许补全用户动作的程度。',
                          'Controls how much connective user action the runtime may fill in.',
                        ),
                        icon: Lucide.User,
                        value: _session!.agencyMode,
                        options: StoryAgencyMode.values,
                        labelFor: (mode) => switch (mode) {
                          StoryAgencyMode.manual => tr(
                            'Manual · 不替用户行动',
                            'Manual',
                          ),
                          StoryAgencyMode.balanced => tr(
                            'Balanced · 仅低影响动作',
                            'Balanced',
                          ),
                          StoryAgencyMode.cinematic => tr(
                            'Cinematic · 保留关键决定',
                            'Cinematic',
                          ),
                        },
                        onSelected: _busy ? null : _setAgencyMode,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('故事语音', 'Story Voice'),
                  footer: tr(
                    '旁白继续复用 Kelivo 已配置的网络 TTS。这里仅保存服务 ID、Voice ID 与表达描述，不复制密钥或 Endpoint。',
                    'Narration reuses Kelivo network TTS. This page stores only service ID, voice ID and performance direction.',
                  ),
                  children: [
                    if (enabledTtsServices.isNotEmpty)
                      StoryNativeSelectRow<String>(
                        label: tr('旁白 TTS 服务', 'Narrator TTS service'),
                        icon: Lucide.Volume2,
                        value: narratorServiceId ?? '',
                        options: <String>[
                          '',
                          ...enabledTtsServices.map((item) => item.id),
                        ],
                        labelFor: serviceLabel,
                        onSelected: _busy
                            ? null
                            : (value) => setState(
                                () => _narratorServiceId = value.isEmpty
                                    ? null
                                    : value,
                              ),
                      )
                    else
                      StoryNativeRow(
                        title: tr('没有已启用的网络 TTS', 'No enabled network TTS'),
                        subtitle: tr(
                          '请先在“语音服务”中配置并启用一个 TTS 服务。',
                          'Configure and enable a TTS service in Voice Services first.',
                        ),
                        icon: Lucide.AudioWaveform,
                        enabled: false,
                      ),
                    StoryNativeTextFieldRow(
                      label: tr('Voice ID / 音色名', 'Voice ID'),
                      controller: _narratorVoiceController,
                      hintText: tr(
                        '填写当前 TTS 服务原生 voice id',
                        'Use the native voice id of the selected TTS service',
                      ),
                      enabled: !_busy,
                    ),
                    StoryNativeTextFieldRow(
                      label: tr('表达描述', 'Performance direction'),
                      controller: _narratorPersonaController,
                      hintText: tr(
                        '例如：冷静、低沉、克制，重要场景略微放慢。',
                        'Example: calm, low, restrained; slow slightly for key scenes.',
                      ),
                      enabled: !_busy,
                      minLines: 2,
                      maxLines: 4,
                    ),
                    StoryNativeSwitchRow(
                      title: tr('仅当前 Worldline 使用', 'Current worldline only'),
                      subtitle: _session?.worldlineId == null
                          ? tr(
                              '首个故事回合建立 Worldline 后可配置。',
                              'Available after the first Story turn creates a worldline.',
                            )
                          : tr(
                              '关闭后，同一 World Tree 的其他分支也可复用该旁白。',
                              'When off, other branches in this World Tree may reuse the narrator.',
                            ),
                      icon: Lucide.GitFork,
                      value:
                          _narratorWorldlineScoped &&
                          _session?.worldlineId != null,
                      onChanged: _busy || _session?.worldlineId == null
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
                  const SizedBox(height: 20),
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
