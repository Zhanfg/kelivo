import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../settings/pages/memory_settings_page.dart';
import '../../settings/pages/tts_services_page.dart';
import '../../world_book/pages/world_book_page.dart';
import '../agency/story_agency_policy.dart';
import '../orchestration/story_break_armor_mode.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import 'story_character_manager_page.dart';
import 'story_conversation_mode_control.dart';
import 'story_native_settings_widgets.dart';
import 'story_reference_library_page.dart';
import 'story_skill_manager_page.dart';
import 'story_voice_manager_page.dart';

/// Product-facing Story settings.
///
/// Internal runtime ids, engine readiness, provider state, cache state and
/// other diagnostics deliberately do not belong on this surface.
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

  List<Conversation> _conversations = const <Conversation>[];
  String? _selectedConversationId;
  StoryRuntimeSessionState? _session;

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
    _ready = true;
    await _reload(selectNewestIfNeeded: true);
  }

  Future<void> _reload({bool selectNewestIfNeeded = false}) async {
    if (!_ready) return;
    if (mounted) setState(() => _loading = true);
    try {
      final conversations =
          context.read<ChatService>().getAllConversations().toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      var selectedId = _selectedConversationId;
      if (selectNewestIfNeeded ||
          selectedId == null ||
          !conversations.any((item) => item.id == selectedId)) {
        selectedId = conversations.isEmpty ? null : conversations.first.id;
      }
      final session = selectedId == null
          ? null
          : await _runtimeStore.readOrDefault(selectedId);
      if (!mounted) return;
      setState(() {
        _conversations = List.unmodifiable(conversations);
        _selectedConversationId = selectedId;
        _session = session;
        _breakArmorEnabled = _breakArmorMode.enabled;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('故事设置暂时无法加载。');
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
    } catch (_) {
      _showMessage('操作失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStoryEnabled(bool enabled) async {
    final id = _selectedConversationId;
    if (id == null) return;
    await _runBusy(() async {
      await _runtimeStore.setEnabled(id, enabled);
      storyConversationModeRevision.value++;
    });
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

  String _conversationLabel(String id, bool zh) {
    for (final conversation in _conversations) {
      if (conversation.id != id) continue;
      final title = conversation.title.trim();
      return title.isEmpty ? (zh ? '未命名会话' : 'Untitled') : title;
    }
    return zh ? '未命名会话' : 'Untitled';
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zhText, String enText) => zh ? zhText : enText;
    final selectedId = _selectedConversationId;
    final session = _session;

    return Scaffold(
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('故事设置', 'Story settings')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StoryNativeSection(
                  title: tr('当前故事', 'Current story'),
                  first: true,
                  children: [
                    if (_conversations.isNotEmpty)
                      StoryNativeSelectRow<String>(
                        label: tr('会话', 'Conversation'),
                        icon: Lucide.MessageCircle,
                        value: selectedId ?? _conversations.first.id,
                        options: _conversations.map((item) => item.id).toList(),
                        labelFor: (id) => _conversationLabel(id, zh),
                        onSelected: _busy ? null : _selectConversation,
                      )
                    else
                      StoryNativeRow(
                        title: tr('没有可用会话', 'No conversations'),
                        subtitle: tr(
                          '先创建一个会话。',
                          'Create a conversation first.',
                        ),
                        icon: Lucide.MessageCircle,
                        enabled: false,
                      ),
                    StoryNativeSwitchRow(
                      title: tr('故事模式', 'Story mode'),
                      subtitle: tr(
                        '只影响当前会话；切回聊天不会删除故事进度。',
                        'Affects only this conversation. Switching back to Chat keeps story progress.',
                      ),
                      icon: Lucide.Compass,
                      value: session?.enabled ?? false,
                      onChanged: _busy || selectedId == null
                          ? null
                          : _setStoryEnabled,
                    ),
                    StoryNativeSwitchRow(
                      title: tr('叙事约束增强', 'Narrative guardrails'),
                      subtitle: tr(
                        '加强角色一致性与用户自主权，不影响普通聊天。',
                        'Strengthens character consistency and user agency without affecting normal Chat.',
                      ),
                      icon: Lucide.Shield,
                      value: _breakArmorEnabled,
                      onChanged: _busy ? null : _setBreakArmorEnabled,
                    ),
                    if (session != null)
                      StoryNativeSelectRow<StoryAgencyMode>(
                        label: tr('叙事主动程度', 'Narrative initiative'),
                        icon: Lucide.User,
                        value: session.agencyMode,
                        options: StoryAgencyMode.values,
                        labelFor: (mode) => switch (mode) {
                          StoryAgencyMode.manual => tr('手动', 'Manual'),
                          StoryAgencyMode.balanced => tr('平衡', 'Balanced'),
                          StoryAgencyMode.cinematic => tr('电影感', 'Cinematic'),
                        },
                        onSelected: _busy ? null : _setAgencyMode,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('故事内容', 'Story content'),
                  children: [
                    StoryNativeRow(
                      title: tr('世界书', 'World Book'),
                      icon: Lucide.BookOpen,
                      onTap: () => _open(const WorldBookPage()),
                    ),
                    StoryNativeRow(
                      title: tr('记忆', 'Memory'),
                      icon: Lucide.Brain,
                      onTap: () => _open(const MemorySettingsPage()),
                    ),
                    StoryNativeRow(
                      title: tr('角色', 'Characters'),
                      icon: Lucide.User,
                      enabled: selectedId != null,
                      onTap: selectedId == null
                          ? null
                          : () => _open(
                              StoryCharacterManagerPage(
                                conversationId: selectedId,
                              ),
                            ),
                    ),
                    StoryNativeRow(
                      title: tr('声音', 'Voices'),
                      icon: Lucide.Volume2,
                      enabled: selectedId != null,
                      onTap: selectedId == null
                          ? null
                          : () => _open(
                              StoryVoiceManagerPage(conversationId: selectedId),
                            ),
                    ),
                    StoryNativeRow(
                      title: tr('技能', 'Skills'),
                      icon: Lucide.Shapes,
                      onTap: () => _open(const StorySkillManagerPage()),
                    ),
                    StoryNativeRow(
                      title: tr('参考文本', 'Reference texts'),
                      icon: Lucide.BookOpenText,
                      onTap: () => _open(const StoryReferenceLibraryPage()),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('高级设置', 'Advanced settings'),
                  children: [
                    StoryNativeRow(
                      title: tr('声音服务', 'Voice services'),
                      subtitle: tr(
                        '配置本地模型或网络声音来源。',
                        'Configure local models or network voice sources.',
                      ),
                      icon: Lucide.Settings,
                      onTap: () => _open(const TtsServicesPage()),
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
