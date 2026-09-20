import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../mcp/story_mcp_profile.dart';
import '../mcp/story_mcp_profile_store.dart';
import 'story_native_settings_widgets.dart';

class StoryMcpProfilePage extends StatefulWidget {
  const StoryMcpProfilePage({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<StoryMcpProfilePage> createState() => _StoryMcpProfilePageState();
}

class _StoryMcpProfilePageState extends State<StoryMcpProfilePage> {
  late final StoryMcpProfileStore _profileStore;
  late final StoryMcpProfileSelectionStore _selectionStore;

  bool _loading = true;
  bool _busy = false;
  List<StoryMcpProfile> _profiles = const [];
  String? _selectedProfileId;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String tr(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    final preferences = context.read<BusinessPreferences>();
    _profileStore = StoryMcpProfileStore(preferences);
    _selectionStore = StoryMcpProfileSelectionStore(preferences);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profiles = await _profileStore.readAll();
      final selection = await _selectionStore.readForConversation(
        widget.conversationId,
      );
      if (!mounted) return;
      setState(() {
        _profiles = List.unmodifiable(profiles);
        _selectedProfileId = selection.profileId;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _show(
        tr('MCP Profile 加载失败：$error', 'Failed to load MCP profiles: $error'),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (error) {
      _show(tr('操作失败：$error', 'Operation failed: $error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectProfile(String? profileId) async {
    await _run(() => _selectionStore.select(widget.conversationId, profileId));
  }

  String _profileSubtitle(StoryMcpProfile profile) {
    final parts = <String>[
      tr(
        '${profile.serverIds.length} 个 MCP 服务器',
        '${profile.serverIds.length} MCP servers',
      ),
      if (profile.toolNames.isNotEmpty)
        tr(
          '${profile.toolNames.length} 个单工具规则',
          '${profile.toolNames.length} individual tool rules',
        ),
      if (profile.includeAssistantDefaults)
        tr('保留 Assistant 默认 MCP', 'Keeps Assistant defaults'),
    ];
    return parts.join(' · ');
  }

  Future<void> _editProfile([StoryMcpProfile? existing]) async {
    final mcpProvider = context.read<McpProvider>();
    await mcpProvider.loaded;
    if (!mounted) return;

    final servers = mcpProvider.servers.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final nameController = TextEditingController(text: existing?.name ?? '');
    final selectedServers = <String>{...?existing?.serverIds};
    var includeAssistantDefaults = existing?.includeAssistantDefaults ?? false;

    final result =
        await showDialog<
          ({String name, Set<String> serverIds, bool includeAssistantDefaults})
        >(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                existing == null
                    ? tr('新建 MCP Profile', 'New MCP profile')
                    : tr('编辑 MCP Profile', 'Edit MCP profile'),
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        autofocus: existing == null,
                        decoration: InputDecoration(
                          labelText: tr('名称', 'Name'),
                          hintText: tr('例如：写作工具', 'Example: Writing tools'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          tr(
                            '保留 Assistant 原有 MCP',
                            'Keep Assistant MCP defaults',
                          ),
                        ),
                        subtitle: Text(
                          tr(
                            '关闭后，Story 只暴露下面勾选的服务器和已有单工具规则。',
                            'When disabled, Story exposes only the servers selected below plus existing per-tool rules.',
                          ),
                        ),
                        value: includeAssistantDefaults,
                        onChanged: (value) {
                          setDialogState(
                            () => includeAssistantDefaults = value,
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('允许的 MCP 服务器', 'Allowed MCP servers'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      if (servers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            tr(
                              'Kelivo 目前没有已配置的 MCP 服务器。',
                              'Kelivo currently has no configured MCP servers.',
                            ),
                          ),
                        )
                      else
                        for (final server in servers)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selectedServers.contains(server.id),
                            title: Text(server.name),
                            subtitle: Text(
                              [
                                server.transport.name,
                                if (!server.enabled) tr('已停用', 'Disabled'),
                              ].join(' · '),
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedServers.add(server.id);
                                } else {
                                  selectedServers.remove(server.id);
                                }
                              });
                            },
                          ),
                      const SizedBox(height: 10),
                      Text(
                        tr(
                          'Profile 只限制模型可见路由。实际连接、工具执行与审批仍由 Kelivo 原生 MCP 系统负责。',
                          'Profiles only narrow model-visible routes. Connection, execution and approval still use Kelivo\'s native MCP system.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('取消', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.of(context).pop((
                      name: name,
                      serverIds: Set<String>.from(selectedServers),
                      includeAssistantDefaults: includeAssistantDefaults,
                    ));
                  },
                  child: Text(tr('保存', 'Save')),
                ),
              ],
            ),
          ),
        );
    nameController.dispose();
    if (result == null) return;

    final profile = StoryMcpProfile(
      id: existing?.id ?? const Uuid().v4(),
      name: result.name,
      serverIds: result.serverIds.toList()..sort(),
      toolNames: existing?.toolNames ?? const <String>[],
      includeAssistantDefaults: result.includeAssistantDefaults,
      requireApproval: true,
      metadata: existing?.metadata ?? const <String, Object?>{},
    );
    await _run(() async {
      await _profileStore.upsert(profile);
      if (existing == null && _selectedProfileId == null) {
        await _selectionStore.select(widget.conversationId, profile.id);
      }
    });
  }

  Future<void> _deleteProfile(StoryMcpProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('删除 MCP Profile？', 'Delete MCP profile?')),
        content: Text(
          tr(
            '所有会话中指向这个 Profile 的选择都会自动清空，不会删除任何 MCP 服务器配置。',
            'Selections pointing to this profile will be cleared in every conversation. No MCP server configuration will be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      await _selectionStore.clearProfileReferences(profile.id);
      await _profileStore.remove(profile.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('Story MCP Profiles', 'Story MCP Profiles')),
        actions: [
          IconButton(
            tooltip: tr('新建', 'New profile'),
            onPressed: _busy ? null : () => _editProfile(),
            icon: const Icon(Lucide.Plus),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              children: [
                StoryNativeSection(
                  title: tr('当前会话', 'Current conversation'),
                  first: true,
                  footer: tr(
                    '不选择 Profile 时，Story 不额外收窄 Assistant 的 MCP 路由。',
                    'With no profile selected, Story does not add extra MCP narrowing.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr(
                        '不使用 Story MCP Profile',
                        'No Story MCP profile',
                      ),
                      subtitle: tr(
                        '保持 Assistant 当前 MCP 行为。',
                        'Keep the Assistant\'s current MCP behavior.',
                      ),
                      icon: Lucide.Globe,
                      trailing: _selectedProfileId == null
                          ? const Icon(Lucide.Check)
                          : null,
                      onTap: _busy ? null : () => _selectProfile(null),
                    ),
                    for (final profile in _profiles)
                      StoryNativeRow(
                        title: profile.name,
                        subtitle: _profileSubtitle(profile),
                        icon: Lucide.Globe,
                        trailing: _selectedProfileId == profile.id
                            ? const Icon(Lucide.Check)
                            : null,
                        onTap: _busy ? null : () => _selectProfile(profile.id),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                StoryNativeSection(
                  title: tr('Profile 管理', 'Profile management'),
                  footer: tr(
                    '服务器白名单与单工具规则采用“任一匹配即允许”；关闭“保留 Assistant 原有 MCP”后才会真正收窄路由。',
                    'Server allow-lists and per-tool rules are additive. Routes are narrowed only when “Keep Assistant MCP defaults” is disabled.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr('新建 Profile', 'New profile'),
                      subtitle: tr(
                        '从 Kelivo 已配置的 MCP 服务器中选择允许范围。',
                        'Choose allowed servers from Kelivo\'s configured MCP connections.',
                      ),
                      icon: Lucide.Plus,
                      onTap: _busy ? null : () => _editProfile(),
                    ),
                    for (final profile in _profiles)
                      StoryNativeRow(
                        title: profile.name,
                        subtitle: _profileSubtitle(profile),
                        icon: Lucide.Settings,
                        trailing: PopupMenuButton<String>(
                          enabled: !_busy,
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editProfile(profile);
                            } else if (value == 'delete') {
                              _deleteProfile(profile);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(tr('编辑', 'Edit')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(tr('删除', 'Delete')),
                            ),
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
}
