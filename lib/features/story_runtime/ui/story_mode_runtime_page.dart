import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../agency/story_agency_policy.dart';
import '../orchestration/story_break_armor_mode.dart';
import '../orchestration/story_mode_transition_service.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import 'story_conversation_mode_control.dart';
import 'story_native_settings_widgets.dart';

/// Product-facing Story behavior settings.
///
/// World Book, Memory, Characters, Voices, References and Skills live only in
/// the global Story tool bar on Home. This page intentionally does not duplicate
/// those first-level destinations as a second navigation hierarchy.
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
    } catch (error) {
      _showMessage('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStoryEnabled(bool enabled) async {
    final id = _selectedConversationId;
    if (id == null) return;
    final preferences = context.read<BusinessPreferences>();
    final chatService = context.read<ChatService>();
    await _runBusy(() async {
      final transition = StoryModeTransitionService(
        preferences: preferences,
        chatService: chatService,
      );
      await transition.setMode(conversationId: id, storyEnabled: enabled);
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
                  footer: tr(
                    '故事内容工具统一放在主页的全局故事工具栏；此页只配置故事运行行为。',
                    'Story content tools live in the global Story toolbar on Home; this page only configures Story runtime behavior.',
                  ),
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
                        '进入故事时会建立或恢复 World Tree 与 Scene；切回聊天不会删除故事进度。',
                        'Entering Story bootstraps or resumes the World Tree and Scene. Switching back to Chat keeps Story progress.',
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
                if (_busy) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
    );
  }
}
