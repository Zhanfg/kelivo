import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../models/agent_task.dart';
import '../providers/agent_interaction_broker.dart';
import '../providers/agent_task_provider.dart';
import '../services/agent_task_journal.dart';
import '../services/agent_task_runner.dart';

class AgentTaskDetailPage extends StatefulWidget {
  const AgentTaskDetailPage({super.key, required this.taskId});

  final String taskId;

  @override
  State<AgentTaskDetailPage> createState() => _AgentTaskDetailPageState();
}

class _AgentTaskDetailPageState extends State<AgentTaskDetailPage> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  Future<void> _send({required bool followUp}) async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final runner = context.read<AgentTaskRunner>();
      final accepted = text.startsWith('!')
          ? await runner.runShell(widget.taskId, text.substring(1))
          : followUp
          ? await runner.followUp(widget.taskId, text)
          : await runner.steer(widget.taskId, text);
      if (!mounted) return;
      if (accepted) {
        _composer.clear();
        _focus.requestFocus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _zh ? '当前任务没有可接收指令的运行会话。' : 'This task has no active session.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = context.watch<AgentTaskProvider>().byId(widget.taskId);
    final journal = context.watch<AgentTaskJournal>();
    final interaction = context.watch<AgentInteractionBroker>().forTask(
      widget.taskId,
    );
    final cs = Theme.of(context).colorScheme;

    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_zh ? '任务' : 'Task')),
        body: Center(child: Text(_zh ? '任务不存在' : 'Task not found')),
      );
    }

    final active = {
      AgentTaskPhase.preparing,
      AgentTaskPhase.running,
      AgentTaskPhase.waitingApproval,
      AgentTaskPhase.verifying,
      AgentTaskPhase.recovering,
    }.contains(task.phase);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          task.title.isEmpty ? (_zh ? '代理任务' : 'Agent task') : task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (active)
            IconButton(
              tooltip: _zh ? '取消任务' : 'Cancel task',
              onPressed: () => unawaited(
                context.read<AgentTaskRunner>().cancel(task.id),
              ),
              icon: const Icon(Lucide.Square),
            )
          else if (task.canResume)
            IconButton(
              tooltip: _zh ? '继续任务' : 'Resume task',
              onPressed: () => unawaited(
                context.read<AgentTaskRunner>().run(task.id),
              ),
              icon: const Icon(Lucide.RotateCcw),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<AgentTaskEvent>>(
              future: journal.read(task.id),
              builder: (context, snapshot) {
                final events = snapshot.data ?? const <AgentTaskEvent>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                  children: [
                    _GoalCard(task: task, zh: _zh),
                    if (interaction != null) ...[
                      const SizedBox(height: 10),
                      _ApprovalCard(request: interaction, zh: _zh),
                    ],
                    if (events.isEmpty) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          _zh ? '等待代理开始执行…' : 'Waiting for Agent to start…',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      for (final event in events)
                        if (_visible(event)) ...[
                          _EventCard(event: event, zh: _zh),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ],
                );
              },
            ),
          ),
          if (active)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _composer,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: _zh
                            ? '补充指令；以 ! 开头可直接执行命令…'
                            : 'Steer the task; start with ! to run a shell command…',
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _zh
                                ? '立即调整会在当前工具完成后生效'
                                : 'Steering applies after the current tool call',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.48),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _sending
                              ? null
                              : () => _send(followUp: true),
                          child: Text(_zh ? '稍后执行' : 'Follow up'),
                        ),
                        FilledButton(
                          onPressed: _sending
                              ? null
                              : () => _send(followUp: false),
                          child: Text(_zh ? '调整' : 'Steer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _visible(AgentTaskEvent event) => switch (event.kind) {
    AgentTaskEventKind.phaseChanged ||
    AgentTaskEventKind.turnStarted ||
    AgentTaskEventKind.turnFinished => false,
    _ => true,
  };
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.task, required this.zh});

  final AgentTask task;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Lucide.Activity, size: 17),
              const SizedBox(width: 7),
              Text(
                zh ? '目标' : 'Goal',
                style: TextStyle(fontWeight: AppFontWeights.semibold),
              ),
              const Spacer(),
              _StatusPill(task: task, zh: zh),
            ],
          ),
          const SizedBox(height: 9),
          Text(task.goal),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.task, required this.zh});

  final AgentTask task;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = switch (task.phase) {
      AgentTaskPhase.queued => zh ? '排队' : 'Queued',
      AgentTaskPhase.preparing => zh ? '准备' : 'Preparing',
      AgentTaskPhase.running => zh ? '执行中' : 'Running',
      AgentTaskPhase.waitingApproval => zh ? '等待批准' : 'Approval',
      AgentTaskPhase.verifying => zh ? '检查' : 'Checking',
      AgentTaskPhase.paused => zh ? '暂停' : 'Paused',
      AgentTaskPhase.completed => zh ? '完成' : 'Done',
      AgentTaskPhase.failed => zh ? '失败' : 'Failed',
      AgentTaskPhase.cancelled => zh ? '取消' : 'Cancelled',
      AgentTaskPhase.interrupted => zh ? '中断' : 'Interrupted',
      AgentTaskPhase.recovering => zh ? '恢复' : 'Recovering',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.zh});

  final AgentTaskEvent event;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    return switch (event.kind) {
      AgentTaskEventKind.planUpdated => _PlanEventCard(
          event: event,
          zh: zh,
        ),
      AgentTaskEventKind.assistantMessage => _TextEventCard(
          icon: Lucide.Bot,
          title: zh ? '代理' : 'Agent',
          text: event.payload['text']?.toString() ?? '',
        ),
      AgentTaskEventKind.toolStarted => _ToolEventCard(
          event: event,
          zh: zh,
          running: true,
        ),
      AgentTaskEventKind.toolProgress => _OutputEventCard(
          event: event,
          zh: zh,
        ),
      AgentTaskEventKind.toolFinished => _ToolEventCard(
          event: event,
          zh: zh,
          running: false,
        ),
      AgentTaskEventKind.approvalRequested => _NoticeEventCard(
          icon: Lucide.Shield,
          text: zh ? '等待你的批准' : 'Waiting for approval',
        ),
      AgentTaskEventKind.approvalResolved => _NoticeEventCard(
          icon: Lucide.CheckCircle,
          text: zh ? '批准请求已处理' : 'Approval resolved',
        ),
      AgentTaskEventKind.retry => _NoticeEventCard(
          icon: Lucide.RotateCcw,
          text: event.payload['state'] == 'start'
              ? (zh ? '请求失败，正在自动重试' : 'Retrying after a transient failure')
              : (zh ? '自动重试结束' : 'Retry finished'),
        ),
      AgentTaskEventKind.compaction => _NoticeEventCard(
          icon: Lucide.FoldVertical,
          text: event.payload['state'] == 'start'
              ? (zh ? '正在压缩上下文' : 'Compacting context')
              : (zh ? '上下文压缩完成' : 'Context compaction finished'),
        ),
      AgentTaskEventKind.queueChanged => _NoticeEventCard(
          icon: Lucide.ListPlus,
          text: zh ? '后续指令队列已更新' : 'Queued instructions updated',
        ),
      AgentTaskEventKind.note => _NoteEventCard(event: event, zh: zh),
      AgentTaskEventKind.notice => _NoticeEventCard(
          icon: Lucide.info,
          text: event.payload['message']?.toString() ??
              (zh ? '代理通知' : 'Agent notice'),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _PlanEventCard extends StatelessWidget {
  const _PlanEventCard({required this.event, required this.zh});

  final AgentTaskEvent event;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rawSteps = event.payload['steps'];
    final steps = rawSteps is List
        ? rawSteps.whereType<Map>().toList(growable: false)
        : const <Map>[];
    final summary = event.payload['summary']?.toString();

    if (steps.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Lucide.ListChecks, size: 17),
              const SizedBox(width: 7),
              Text(
                zh ? '计划' : 'Plan',
                style: TextStyle(fontWeight: AppFontWeights.semibold),
              ),
            ],
          ),
          if ((summary ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(summary!),
          ],
          const SizedBox(height: 8),
          for (final step in steps) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    _statusIcon(step['status']?.toString()),
                    size: 15,
                    color: cs.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(step['text']?.toString() ?? ''),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  static IconData _statusIcon(String? status) => switch (status) {
    'completed' => Lucide.CheckCircle,
    'in_progress' => Lucide.Loader,
    _ => Lucide.circleDot,
  };
}

class _ToolEventCard extends StatelessWidget {
  const _ToolEventCard({
    required this.event,
    required this.zh,
    required this.running,
  });

  final AgentTaskEvent event;
  final bool zh;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tool = event.payload['tool']?.toString() ?? 'tool';
    final args = event.payload['args'];
    final output = event.payload['output']?.toString();
    final error = event.payload['isError'] == true;

    final command = args is Map && args['command'] != null
        ? args['command'].toString()
        : null;
    final subagentTasks =
        tool == 'task' && args is Map && args['tasks'] is List
        ? (args['tasks'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final path = args is Map
        ? (args['path'] ?? args['file_path'] ?? args['filePath'])?.toString()
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: error
              ? cs.error.withValues(alpha: 0.35)
              : cs.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_toolIcon(tool), size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _toolTitle(tool, zh),
                  style: TextStyle(fontWeight: AppFontWeights.semibold),
                ),
              ),
              Text(
                running
                    ? (zh ? '开始' : 'Started')
                    : error
                    ? (zh ? '失败' : 'Failed')
                    : (zh ? '完成' : 'Done'),
                style: TextStyle(
                  fontSize: 11,
                  color: error
                      ? cs.error
                      : cs.onSurface.withValues(alpha: 0.52),
                ),
              ),
            ],
          ),
          if (subagentTasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final item in subagentTasks) ...[
              _SubagentTaskRow(item: item, zh: zh),
              const SizedBox(height: 6),
            ],
          ] else if (command != null && command.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CodeBlock(text: '\$ $command'),
          ] else if (path != null && path.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              path,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.68),
              ),
            ),
          ],
          if (tool == 'edit' && args is Map) ..._diffWidgets(args, context),
          if (output != null && output.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _CodeBlock(text: output),
          ],
        ],
      ),
    );
  }

  static List<Widget> _diffWidgets(Map args, BuildContext context) {
    final oldText = (args['oldText'] ?? args['old_text'])?.toString();
    final newText = (args['newText'] ?? args['new_text'])?.toString();
    if ((oldText ?? '').isEmpty && (newText ?? '').isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      const SizedBox(height: 8),
      _CodeBlock(
        text: [
          if ((oldText ?? '').isNotEmpty)
            for (final line in oldText!.split('\n')) '- $line',
          if ((newText ?? '').isNotEmpty)
            for (final line in newText!.split('\n')) '+ $line',
        ].join('\n'),
      ),
    ];
  }

  static IconData _toolIcon(String tool) => switch (tool) {
    'bash' => Lucide.Terminal,
    'task' => Lucide.Network,
    'hub' => Lucide.MessagesSquare,
    'job' => Lucide.Activity,
    'todo' => Lucide.ListChecks,
    'read' => Lucide.FileText,
    'write' => Lucide.FilePlus,
    'edit' => Lucide.FilePen,
    'grep' || 'find' => Lucide.Search,
    'ls' => Lucide.FolderOpen,
    _ => Lucide.Wrench,
  };

  static String _toolTitle(String tool, bool zh) => switch (tool) {
    'bash' => zh ? '执行命令' : 'Run command',
    'task' => zh ? '并行子代理' : 'Subagents',
    'hub' => zh ? '代理协作' : 'Agent coordination',
    'job' => zh ? '后台任务' : 'Background job',
    'todo' => zh ? '任务清单' : 'Todo',
    'read' => zh ? '读取文件' : 'Read file',
    'write' => zh ? '写入文件' : 'Write file',
    'edit' => zh ? '编辑文件' : 'Edit file',
    'grep' => zh ? '搜索内容' : 'Search content',
    'find' => zh ? '查找文件' : 'Find files',
    'ls' => zh ? '列出目录' : 'List directory',
    _ => tool,
  };
}

class _SubagentTaskRow extends StatelessWidget {
  const _SubagentTaskRow({required this.item, required this.zh});

  final Map item;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (item['name'] ?? item['agent'])?.toString().trim();
    final task = item['task']?.toString().trim() ?? '';
    final isolated = item['isolated'] == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isolated ? Lucide.GitFork : Lucide.Bot,
            size: 15,
            color: cs.onSurface.withValues(alpha: 0.62),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null && name.isNotEmpty)
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                if (task.isNotEmpty)
                  Text(
                    task,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: cs.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
              ],
            ),
          ),
          if (isolated)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                zh ? '隔离' : 'isolated',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.48),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OutputEventCard extends StatelessWidget {
  const _OutputEventCard({required this.event, required this.zh});
  final AgentTaskEvent event;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final output = event.payload['output']?.toString() ?? '';
    if (output.trim().isEmpty) return const SizedBox.shrink();
    return _TextEventCard(
      icon: Lucide.SquareTerminal,
      title: zh ? '运行输出' : 'Live output',
      text: output,
      code: true,
    );
  }
}

class _TextEventCard extends StatelessWidget {
  const _TextEventCard({
    required this.icon,
    required this.title,
    required this.text,
    this.code = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final bool code;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 7),
              Text(title, style: TextStyle(fontWeight: AppFontWeights.semibold)),
            ],
          ),
          const SizedBox(height: 8),
          if (code) _CodeBlock(text: text) else Text(text),
        ],
      ),
    );
  }
}

class _NoticeEventCard extends StatelessWidget {
  const _NoticeEventCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurface.withValues(alpha: 0.48)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteEventCard extends StatelessWidget {
  const _NoteEventCard({required this.event, required this.zh});
  final AgentTaskEvent event;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final kind = event.payload['kind']?.toString();
    final text = event.payload['text']?.toString();
    if ((kind == 'steer' || kind == 'follow_up') && text != null) {
      return _TextEventCard(
        icon: Lucide.MessageSquare,
        title: kind == 'steer'
            ? (zh ? '你的调整' : 'Your steering')
            : (zh ? '后续指令' : 'Follow-up'),
        text: text,
      );
    }
    return const SizedBox.shrink();
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            height: 1.35,
            color: cs.onSurface.withValues(alpha: 0.86),
          ),
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({required this.request, required this.zh});

  final AgentInteractionRequest request;
  final bool zh;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  late final TextEditingController _text = TextEditingController(
    text: widget.request.prefill ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _optionLabel(String value) {
    if (!widget.zh) return value;
    return switch (value) {
      'Allow once' => '允许一次',
      'Always allow this tool' => '本次任务始终允许此工具',
      'Block' => '阻止',
      _ => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final broker = context.read<AgentInteractionBroker>();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.secondary.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Lucide.Shield, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.zh ? '需要你的确认' : 'Approval required',
                  style: TextStyle(fontWeight: AppFontWeights.semibold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.request.title.trim().isNotEmpty)
            Text(widget.request.title),
          if ((widget.request.message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(widget.request.message!),
          ],
          const SizedBox(height: 10),
          switch (widget.request.method) {
            AgentInteractionMethod.select => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in widget.request.options)
                    OutlinedButton(
                      onPressed: () => broker.select(widget.request.id, option),
                      child: Text(_optionLabel(option)),
                    ),
                ],
              ),
            AgentInteractionMethod.confirm => Row(
                children: [
                  OutlinedButton(
                    onPressed: () => broker.confirm(widget.request.id, false),
                    child: Text(widget.zh ? '拒绝' : 'Deny'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => broker.confirm(widget.request.id, true),
                    child: Text(widget.zh ? '允许' : 'Allow'),
                  ),
                ],
              ),
            AgentInteractionMethod.input || AgentInteractionMethod.editor =>
              Column(
                children: [
                  TextField(
                    controller: _text,
                    minLines:
                        widget.request.method == AgentInteractionMethod.editor
                        ? 3
                        : 1,
                    maxLines:
                        widget.request.method == AgentInteractionMethod.editor
                        ? 8
                        : 3,
                    decoration: InputDecoration(
                      hintText: widget.request.placeholder,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => broker.cancel(widget.request.id),
                        child: Text(widget.zh ? '取消' : 'Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => broker.submitText(
                          widget.request.id,
                          _text.text,
                        ),
                        child: Text(widget.zh ? '提交' : 'Submit'),
                      ),
                    ],
                  ),
                ],
              ),
          },
        ],
      ),
    );
  }
}
