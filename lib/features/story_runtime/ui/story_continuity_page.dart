import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/memory_entry.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/memory/memory_repository.dart';
import '../../../icons/lucide_adapter.dart';
import '../memory/story_worldline_memory.dart';
import '../memory/story_worldline_memory_store.dart';
import '../world_tree/story_world_tree_coordinator.dart';
import '../world_tree/story_world_tree_models.dart';
import '../world_tree/story_world_tree_store.dart';
import 'story_native_settings_widgets.dart';

class StoryContinuityPage extends StatefulWidget {
  const StoryContinuityPage({
    super.key,
    required this.conversationId,
  });

  final String conversationId;

  @override
  State<StoryContinuityPage> createState() => _StoryContinuityPageState();
}

class _StoryContinuityPageState extends State<StoryContinuityPage> {
  late final StoryWorldTreeStore _treeStore;
  late final StoryWorldTreeCoordinator _coordinator;
  late final StoryWorldlineMemoryStore _memoryLinkStore;
  late final MemoryRepository _memoryRepository;

  bool _loading = true;
  bool _busy = false;
  StoryWorldTreeState? _tree;
  List<StoryWorldlineMemoryLink> _links = const [];
  Map<String, MemoryEntry> _memoryById = const {};
  String? _selectedWorldlineId;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String tr(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    final preferences = context.read<BusinessPreferences>();
    _treeStore = StoryWorldTreeStore(preferences);
    _coordinator = StoryWorldTreeCoordinator(repository: _treeStore);
    _memoryLinkStore = StoryWorldlineMemoryStore(preferences);
    _memoryRepository = MemoryRepository(preferences);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final tree = await _treeStore.readForConversation(widget.conversationId);
      final links = tree == null
          ? const <StoryWorldlineMemoryLink>[]
          : await _memoryLinkStore.readForTree(tree.worldTreeId);
      final memories = await _memoryRepository.readAll();
      final selected = tree?.worldlineForConversation(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _links = List.unmodifiable(links);
        _memoryById = {
          for (final entry in memories) entry.id: entry,
        };
        _selectedWorldlineId ??= selected?.id ?? tree?.headWorldlineId;
        if (tree != null &&
            tree.worldlineById(_selectedWorldlineId ?? '') == null) {
          _selectedWorldlineId = tree.headWorldlineId;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _show(tr('连续性数据加载失败：$error', 'Failed to load continuity data: $error'));
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _conversationLabel(String conversationId) {
    final conversation =
        context.read<ChatService>().getConversation(conversationId);
    final title = conversation?.title.trim() ?? '';
    if (title.isNotEmpty) return title;
    return tr('未命名分支', 'Untitled branch');
  }

  String _short(String value) {
    if (value.length <= 10) return value;
    return value.substring(0, 8);
  }

  Future<void> _switchWorldline(StoryWorldline line) async {
    final tree = _tree;
    if (tree == null || line.status == StoryWorldlineStatus.archived) return;
    await _run(() async {
      await _coordinator.switchHead(
        worldTreeId: tree.worldTreeId,
        worldlineId: line.id,
      );
      context.read<ChatService>().setCurrentConversation(line.conversationId);
      if (mounted) {
        setState(() => _selectedWorldlineId = line.id);
      }
    });
  }

  Future<void> _setMainline(StoryWorldline line) async {
    final tree = _tree;
    if (tree == null || line.status == StoryWorldlineStatus.archived) return;
    await _run(() async {
      await _coordinator.setMainline(
        worldTreeId: tree.worldTreeId,
        worldlineId: line.id,
      );
    });
  }

  Future<void> _archiveWorldline(StoryWorldline line) async {
    final tree = _tree;
    if (tree == null || line.id == tree.headWorldlineId) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('归档分支？', 'Archive branch?')),
        content: Text(
          tr(
            '该分支不会被删除，但会从可切换的活动分支中移除。',
            'The branch is kept, but it will no longer be available as an active branch.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('归档', 'Archive')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _coordinator.archiveWorldline(
        worldTreeId: tree.worldTreeId,
        worldlineId: line.id,
      );
    });
  }

  Future<void> _addManualMemory() async {
    final tree = _tree;
    final worldlineId = _selectedWorldlineId;
    if (tree == null || worldlineId == null) return;

    final controller = TextEditingController();
    var strategy = StoryMemoryInheritanceStrategy.inherited;
    final result =
        await showDialog<({String text, StoryMemoryInheritanceStrategy strategy})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr('添加分支记忆', 'Add branch memory')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: tr('事实或连续性说明', 'Fact or continuity note'),
                    hintText: tr(
                      '例如：本分支中角色 A 已经知道钥匙的位置。',
                      'Example: In this branch, Character A knows where the key is.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<StoryMemoryInheritanceStrategy>(
                  initialValue: strategy,
                  decoration: InputDecoration(
                    labelText: tr('继承方式', 'Inheritance'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: StoryMemoryInheritanceStrategy.inherited,
                      child: Text(tr('子分支继承', 'Inherited by child branches')),
                    ),
                    DropdownMenuItem(
                      value: StoryMemoryInheritanceStrategy.local,
                      child: Text(tr('仅当前分支', 'Current branch only')),
                    ),
                    DropdownMenuItem(
                      value: StoryMemoryInheritanceStrategy.isolated,
                      child: Text(tr('隔离记忆', 'Isolated memory')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => strategy = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.of(context).pop((text: text, strategy: strategy));
              },
              child: Text(tr('保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;

    await _run(() async {
      final entry = await _memoryRepository.create(
        scope: MemoryScope.global,
        type: MemoryType.instruction,
        content: result.text,
        source: MemorySource.manual,
      );
      final currentLinks =
          await _memoryLinkStore.readForTree(tree.worldTreeId);
      final link = StoryWorldlineMemoryLink(
        memoryId: entry.id,
        sourceWorldlineId: worldlineId,
        updatedAt: DateTime.now().toUtc(),
        visibilityScope:
            result.strategy == StoryMemoryInheritanceStrategy.inherited
                ? StoryMemoryVisibilityScope.ancestry
                : StoryMemoryVisibilityScope.worldline,
        strategy: result.strategy,
        sourceKind: StoryMemorySourceKind.manual,
      );
      await _memoryLinkStore.writeForTree(
        tree.worldTreeId,
        [...currentLinks, link],
      );
      final latest = await _treeStore.read(tree.worldTreeId);
      if (latest != null) {
        await _treeStore.upsert(
          latest.copyWith(memoryVersion: latest.memoryVersion + 1),
        );
      }
    });
  }

  Future<void> _removeManualMemory(StoryWorldlineMemoryLink link) async {
    final tree = _tree;
    if (tree == null || link.sourceKind != StoryMemorySourceKind.manual) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('删除这条分支记忆？', 'Delete this branch memory?')),
        content: Text(
          tr(
            '该记忆会同时从基础 Memory 存储中归档，避免删除链接后意外变成全局记忆。',
            'The backing Memory entry will also be archived so it cannot leak into global memory after unlinking.',
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
      final currentLinks =
          await _memoryLinkStore.readForTree(tree.worldTreeId);
      await _memoryLinkStore.writeForTree(
        tree.worldTreeId,
        [
          for (final item in currentLinks)
            if (!(item.memoryId == link.memoryId &&
                item.sourceWorldlineId == link.sourceWorldlineId))
              item,
        ],
      );
      await _memoryRepository.archive(link.memoryId);
      final latest = await _treeStore.read(tree.worldTreeId);
      if (latest != null) {
        await _treeStore.upsert(
          latest.copyWith(memoryVersion: latest.memoryVersion + 1),
        );
      }
    });
  }

  String _statusLabel(StoryWorldline line) {
    return switch (line.status) {
      StoryWorldlineStatus.active => tr('活动', 'Active'),
      StoryWorldlineStatus.merged => tr('已合并', 'Merged'),
      StoryWorldlineStatus.archived => tr('已归档', 'Archived'),
    };
  }

  String _memoryStrategyLabel(StoryWorldlineMemoryLink link) {
    return switch (link.strategy) {
      StoryMemoryInheritanceStrategy.inherited => tr('可继承', 'Inherited'),
      StoryMemoryInheritanceStrategy.local => tr('仅本分支', 'Local'),
      StoryMemoryInheritanceStrategy.isolated => tr('隔离', 'Isolated'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final selectedWorldlineId = _selectedWorldlineId;
    final selectedLinks = selectedWorldlineId == null
        ? const <StoryWorldlineMemoryLink>[]
        : _links
            .where((link) => link.sourceWorldlineId == selectedWorldlineId)
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('连续性与分支', 'Continuity & branches')),
        actions: [
          IconButton(
            tooltip: tr('刷新', 'Refresh'),
            onPressed: _busy ? null : _reload,
            icon: const Icon(Lucide.RefreshCw),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : tree == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      tr(
                        '这个会话还没有 World Tree。先启用故事模式并发送一条消息。',
                        'This conversation does not have a World Tree yet. Enable Story mode and send a message first.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                  children: [
                    StoryNativeSection(
                      title: 'World Tree',
                      first: true,
                      footer: tr(
                        '切换分支会同时切换实际聊天会话；归档不会删除历史。',
                        'Switching branches also switches the actual chat conversation. Archiving never deletes history.',
                      ),
                      children: [
                        for (final line in tree.worldlines)
                          StoryNativeRow(
                            title: _conversationLabel(line.conversationId),
                            subtitle: [
                              _statusLabel(line),
                              if (line.id == tree.headWorldlineId)
                                tr('当前', 'Head'),
                              if (line.id == tree.mainlineWorldlineId)
                                tr('主线', 'Mainline'),
                              '#${_short(line.id)}',
                            ].join(' · '),
                            icon: line.parentWorldlineId == null
                                ? Lucide.BookOpen
                                : Lucide.GitFork,
                            trailing: PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (value) {
                                if (value == 'open') {
                                  _switchWorldline(line);
                                } else if (value == 'mainline') {
                                  _setMainline(line);
                                } else if (value == 'archive') {
                                  _archiveWorldline(line);
                                }
                              },
                              itemBuilder: (context) => [
                                if (line.status !=
                                        StoryWorldlineStatus.archived &&
                                    line.id != tree.headWorldlineId)
                                  PopupMenuItem(
                                    value: 'open',
                                    child: Text(
                                      tr('切换到此分支', 'Switch to branch'),
                                    ),
                                  ),
                                if (line.status !=
                                        StoryWorldlineStatus.archived &&
                                    line.id != tree.mainlineWorldlineId)
                                  PopupMenuItem(
                                    value: 'mainline',
                                    child:
                                        Text(tr('设为主线', 'Set as mainline')),
                                  ),
                                if (line.status !=
                                        StoryWorldlineStatus.archived &&
                                    line.id != tree.headWorldlineId)
                                  PopupMenuItem(
                                    value: 'archive',
                                    child: Text(tr('归档', 'Archive')),
                                  ),
                              ],
                            ),
                            onTap: () {
                              setState(
                                () => _selectedWorldlineId = line.id,
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    StoryNativeSection(
                      title: tr('检查点', 'Checkpoints'),
                      footer: tr(
                        '当前仅展示稳定检查点；下一步会在这里开放安全的回退/重放操作。',
                        'Stable checkpoints are visible here. Safe rewind/replay controls will be added here next.',
                      ),
                      children: [
                        if (tree.checkpoints.isEmpty)
                          StoryNativeRow(
                            title: tr('暂无检查点', 'No checkpoints yet'),
                            subtitle: tr(
                              '运行时创建的检查点会显示在这里。',
                              'Runtime checkpoints will appear here.',
                            ),
                            icon: Lucide.History,
                            enabled: false,
                          )
                        else
                          for (final checkpoint
                              in tree.checkpoints.reversed.take(20))
                            StoryNativeRow(
                              title:
                                  checkpoint.label?.trim().isNotEmpty == true
                                      ? checkpoint.label!.trim()
                                      : tr('检查点', 'Checkpoint'),
                              subtitle:
                                  '${tr('消息', 'Message')} ${_short(checkpoint.messageId)} · ${_short(checkpoint.worldlineId)}',
                              icon: Lucide.History,
                              enabled: false,
                            ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    StoryNativeSection(
                      title: tr('分支记忆', 'Worldline memory'),
                      footer: tr(
                        '手工记忆会写入原生 Memory 存储，并额外绑定 Worldline 可见范围；删除时会同时归档底层 Memory，避免泄漏为全局记忆。',
                        'Manual memories use Kelivo Memory plus a Worldline visibility link. Deleting one archives the backing Memory so it cannot leak globally.',
                      ),
                      children: [
                        StoryNativeRow(
                          title: tr('添加手工记忆', 'Add manual memory'),
                          subtitle: tr(
                            '为当前选中的分支补充连续性事实。',
                            'Add a continuity fact to the selected branch.',
                          ),
                          icon: Lucide.Plus,
                          enabled: !_busy && selectedWorldlineId != null,
                          onTap: _addManualMemory,
                        ),
                        if (selectedLinks.isEmpty)
                          StoryNativeRow(
                            title: tr(
                              '当前分支暂无专属记忆',
                              'No branch-specific memory',
                            ),
                            icon: Lucide.Brain,
                            enabled: false,
                          )
                        else
                          for (final link in selectedLinks)
                            StoryNativeRow(
                              title: _memoryById[link.memoryId]?.content ??
                                  tr(
                                    '记忆内容不可用',
                                    'Memory content unavailable',
                                  ),
                              subtitle:
                                  '${_memoryStrategyLabel(link)} · ${link.sourceKind.name}',
                              icon: Lucide.Brain,
                              trailing:
                                  link.sourceKind == StoryMemorySourceKind.manual
                                      ? IconButton(
                                          tooltip: tr('删除', 'Delete'),
                                          onPressed: _busy
                                              ? null
                                              : () =>
                                                  _removeManualMemory(link),
                                          icon: const Icon(Lucide.Trash),
                                        )
                                      : null,
                              enabled: false,
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
