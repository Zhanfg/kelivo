import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/services/chat/chat_service.dart';
import '../mcp/story_mcp_profile.dart';
import '../mcp/story_mcp_profile_store.dart';
import '../state/story_runtime_machine.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import '../voice/story_voice_routing.dart';
import '../voice/story_voice_store.dart';
import '../world_tree/story_world_tree_models.dart';
import '../world_tree/story_world_tree_store.dart';

class StoryRuntimeControlPage extends StatefulWidget {
  const StoryRuntimeControlPage({super.key});

  @override
  State<StoryRuntimeControlPage> createState() =>
      _StoryRuntimeControlPageState();
}

class _StoryRuntimeControlPageState extends State<StoryRuntimeControlPage> {
  bool _initialized = false;
  bool _loading = true;
  bool _busy = false;
  String? _conversationId;

  late StoryRuntimeStore _sessionStore;
  late StoryRuntimeExecutionStore _executionStore;
  late StoryWorldTreeStore _worldTreeStore;
  late StoryMcpProfileStore _mcpProfileStore;
  late StoryMcpProfileSelectionStore _mcpSelectionStore;
  late StoryVoiceRoutingStore _voiceStore;

  StoryRuntimeSessionState? _session;
  StoryRuntimeExecutionState? _execution;
  StoryWorldTreeState? _tree;
  StoryVoiceRoutingState? _voice;
  List<StoryMcpProfile> _profiles = const <StoryMcpProfile>[];
  String? _selectedProfileId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final preferences = context.read<BusinessPreferences>();
    _sessionStore = StoryRuntimeStore(preferences);
    _executionStore = StoryRuntimeExecutionStore(preferences);
    _worldTreeStore = StoryWorldTreeStore(preferences);
    _mcpProfileStore = StoryMcpProfileStore(preferences);
    _mcpSelectionStore = StoryMcpProfileSelectionStore(preferences);
    _voiceStore = StoryVoiceRoutingStore(preferences);
    _bootstrap();
  }

  List<Conversation> _conversations() {
    final values = context.read<ChatService>().getAllConversations().toList();
    values.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  Future<void> _bootstrap() async {
    final conversations = _conversations();
    _conversationId = conversations.isEmpty ? null : conversations.first.id;
    await _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final id = _conversationId;
      final profiles = await _mcpProfileStore.readAll();
      final session = id == null ? null : await _sessionStore.readOrDefault(id);
      final execution = id == null
          ? null
          : await _executionStore.readOrDefault(id);
      final tree = id == null
          ? null
          : await _worldTreeStore.readForConversation(id);
      final selection = id == null
          ? null
          : await _mcpSelectionStore.readForConversation(id);
      final voice = tree == null
          ? null
          : await _voiceStore.readOrDefault(tree.worldTreeId);
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _session = session;
        _execution = execution;
        _tree = tree;
        _selectedProfileId = selection?.profileId;
        _voice = voice;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _show('读取 Story Runtime 失败：$error');
    }
  }

  Future<void> _selectConversation(String? id) async {
    if (id == null || id == _conversationId) return;
    setState(() => _conversationId = id);
    await _reload();
  }

  Future<void> _setEnabled(bool enabled) async {
    final id = _conversationId;
    if (id == null || _busy) return;
    await _runBusy(() => _sessionStore.setEnabled(id, enabled));
  }

  Future<void> _selectMcpProfile(String? value) async {
    final id = _conversationId;
    if (id == null || _busy) return;
    await _runBusy(
      () => _mcpSelectionStore.select(
        id,
        value == null || value.isEmpty ? null : value,
      ),
    );
  }

  Future<void> _createMcpProfile() async {
    if (_busy) return;
    final nameController = TextEditingController();
    final serversController = TextEditingController();
    final toolsController = TextEditingController();
    var includeAssistantDefaults = false;
    final result = await showDialog<StoryMcpProfile>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建 MCP Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: serversController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Server IDs',
                    hintText: '逗号或换行分隔；留空表示不按 Server ID 放行',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: toolsController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Tool names',
                    hintText: '逗号或换行分隔；按 Kelivo MCP 工具名精确匹配',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('保留 Assistant 原生 MCP 选择'),
                  subtitle: const Text('关闭时，Story Mode 只暴露本 Profile 的 allow-list。'),
                  value: includeAssistantDefaults,
                  onChanged: (value) => setDialogState(
                    () => includeAssistantDefaults = value,
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Approval 不会被此页面关闭；执行仍服从 Kelivo 原生审批。',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final now = DateTime.now().microsecondsSinceEpoch;
                Navigator.of(dialogContext).pop(
                  StoryMcpProfile(
                    id: 'story-mcp-$now',
                    name: name,
                    serverIds: _splitIds(serversController.text),
                    toolNames: _splitIds(toolsController.text),
                    includeAssistantDefaults: includeAssistantDefaults,
                    requireApproval: true,
                  ),
                );
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    serversController.dispose();
    toolsController.dispose();
    if (result == null) return;
    await _runBusy(() async {
      await _mcpProfileStore.upsert(result);
      final id = _conversationId;
      if (id != null) await _mcpSelectionStore.select(id, result.id);
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) _show('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static List<String> _splitIds(String raw) => raw
      .split(RegExp(r'[,\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  String _conversationTitle(String id) {
    for (final conversation in _conversations()) {
      if (conversation.id == id) {
        final title = conversation.title.trim();
        return title.isEmpty ? '未命名会话' : title;
      }
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final conversations = _conversations();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Story Runtime 控制'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _conversationId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '会话',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final conversation in conversations)
                      DropdownMenuItem<String>(
                        value: conversation.id,
                        child: Text(
                          _conversationTitle(conversation.id),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy ? null : _selectConversation,
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Story Mode'),
                        subtitle: const Text('仅影响当前会话；关闭时保持普通 Kelivo Chat 行为。'),
                        value: _session?.enabled ?? false,
                        onChanged: _conversationId == null || _busy
                            ? null
                            : _setEnabled,
                      ),
                      const Divider(height: 1),
                      _statusTile('Execution', _execution?.phase.name ?? 'idle'),
                      _statusTile(
                        'Runtime revision',
                        '${_execution?.runtimeStateVersion ?? 0}',
                      ),
                      _statusTile(
                        'Scene revision',
                        '${_session?.sceneRevision ?? 0}',
                      ),
                      _statusTile(
                        'Worldline',
                        _session?.worldlineId ?? _tree?.headWorldlineId ?? '—',
                      ),
                      _statusTile('Current node', _tree?.currentNodeId ?? '—'),
                      _statusTile(
                        'Memory version',
                        '${_tree?.memoryVersion ?? _execution?.memoryVersion ?? 0}',
                      ),
                      if ((_execution?.recentFailure ?? '').isNotEmpty)
                        ListTile(
                          leading: Icon(Icons.error_outline, color: cs.error),
                          title: const Text('最近一次 Runtime 错误'),
                          subtitle: SelectableText(_execution!.recentFailure!),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text('MCP Profile', style: theme.textTheme.titleMedium),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _createMcpProfile,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('新建'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedProfileId ?? '',
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '当前会话工具暴露策略',
                  ),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('不使用 Story MCP Profile · 保持 Assistant 原生选择'),
                    ),
                    for (final profile in _profiles)
                      DropdownMenuItem<String>(
                        value: profile.id,
                        child: Text(profile.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _conversationId == null || _busy
                      ? null
                      : _selectMcpProfile,
                ),
                if (_selectedProfileId != null) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      StoryMcpProfile? selected;
                      for (final profile in _profiles) {
                        if (profile.id == _selectedProfileId) {
                          selected = profile;
                          break;
                        }
                      }
                      if (selected == null) {
                        return const Text('所选 Profile 已不存在；请重新选择。');
                      }
                      return Text(
                        'Servers ${selected.serverIds.length} · Tools ${selected.toolNames.length} · '
                        '${selected.includeAssistantDefaults ? '叠加 Assistant 工具' : '严格 allow-list'} · Approval 保持开启',
                        style: theme.textTheme.bodySmall,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 20),
                Text('Voice Routing', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  child: Column(
                    children: [
                      _statusTile(
                        'Narrator',
                        _voice?.narrator == null
                            ? '未绑定'
                            : '${_voice!.narrator!.ttsServiceId} / ${_voice!.narrator!.voiceId}',
                      ),
                      _statusTile(
                        'Character bindings',
                        '${_voice?.assignments.length ?? 0}',
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Story 只保存稳定角色→现有 Kelivo TTS 服务/音色的路由，不复制 API Key 或服务配置。',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusTile(String label, String value) => ListTile(
    dense: true,
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: Text(
        value,
        textAlign: TextAlign.end,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}
