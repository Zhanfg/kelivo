import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/environment_state.dart';
import '../../../core/models/workspace.dart';
import '../../../core/models/workspace_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/environment_provider.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../models/agent_task.dart';
import '../providers/agent_task_provider.dart';
import '../services/agent_context_bridge.dart';
import '../services/agent_task_runner.dart';

class AgentModePage extends StatefulWidget {
  const AgentModePage({super.key});

  @override
  State<AgentModePage> createState() => _AgentModePageState();
}

class _AgentModePageState extends State<AgentModePage> {
  final TextEditingController _taskController = TextEditingController();
  final FocusNode _taskFocus = FocusNode();
  bool _submitting = false;
  String? _contextKey;
  Future<AgentContextSnapshot>? _contextFuture;

  @override
  void dispose() {
    _taskController.dispose();
    _taskFocus.dispose();
    super.dispose();
  }

  Future<void> _submitTask() async {
    final goal = _taskController.text.trim();
    if (goal.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    try {
      final workspace = await _resolveWorkspace();
      if (!mounted) return;

      final chat = context.read<ChatService>();
      final assistant = context.read<AssistantProvider>().currentAssistant;
      final conversationId = chat.currentConversationId;
      final conversation = conversationId == null
          ? null
          : chat.getConversation(conversationId);

      final task = await context.read<AgentTaskProvider>().create(
        title: _titleForGoal(goal),
        goal: goal,
        workspaceId: workspace.id,
        conversationId: conversationId,
        assistantId: conversation?.assistantId ?? assistant?.id,
      );

      if (!mounted) return;
      unawaited(context.read<AgentTaskRunner>().run(task.id));
      _taskController.clear();
      _taskFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isZh(context)
                ? '任务已加入代理队列：${task.title}'
                : 'Task queued for Agent: ${task.title}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isZh(context)
                ? '创建代理任务失败：$error'
                : 'Failed to create Agent task: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<Workspace> _resolveWorkspace() async {
    final zh = _isZh(context);
    final chat = context.read<ChatService>();
    final workspaces = context.read<WorkspaceProvider>();
    final assistants = context.read<AssistantProvider>();
    await workspaces.loaded;

    final conversationId = chat.currentConversationId;
    if (conversationId != null) {
      final conversation = chat.getConversation(conversationId);
      if (conversation != null) {
        final binding = WorkspaceBinding.fromExtras(conversation.extras);
        if (binding.isBound) {
          final existing = workspaces.byId(binding.workspaceId!);
          if (existing != null) return existing;
        }
      }
    }

    final assistantWorkspaceId =
        assistants.currentAssistant?.defaultWorkspaceId;
    if (assistantWorkspaceId != null && assistantWorkspaceId.isNotEmpty) {
      final existing = workspaces.byId(assistantWorkspaceId);
      if (existing != null) return existing;
    }

    for (final workspace in workspaces.workspaces) {
      if (workspace.name == 'Agent Workspace' || workspace.name == '代理工作区') {
        return workspace;
      }
    }

    return workspaces.create(
      name: zh ? '代理工作区' : 'Agent Workspace',
      kind: WorkspaceKind.managed,
    );
  }

  String _titleForGoal(String goal) {
    final firstLine = goal.split(RegExp(r'[\r\n]+')).first.trim();
    final runes = firstLine.runes.toList(growable: false);
    if (runes.length <= 40) return firstLine;
    return '${String.fromCharCodes(runes.take(40))}…';
  }

  Future<AgentContextSnapshot> _contextSnapshot() {
    final chat = context.read<ChatService>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final conversationId = chat.currentConversationId;
    final conversation = conversationId == null
        ? null
        : chat.getConversation(conversationId);
    final skillIds = assistant?.skillIds;
    final key = [
      assistant?.id ?? '',
      ...(skillIds ?? const <String>[]),
      ...(conversation?.mcpServerIds ?? const <String>[]),
    ].join('|');

    if (_contextKey != key || _contextFuture == null) {
      _contextKey = key;
      _contextFuture = context.read<AgentContextBridge>().build(
        assistantId: conversation?.assistantId ?? assistant?.id,
        skillIds: skillIds?.toSet(),
        mcpServerIds: conversation?.mcpServerIds.toSet(),
      );
    }
    return _contextFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final zh = _isZh(context);
    final tasks = List<AgentTask>.of(context.watch<AgentTaskProvider>().tasks)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final environment = context.watch<EnvironmentProvider>().state;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 12;

    return SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, topInset, 16, 24),
        children: [
          _HeroCard(
            zh: zh,
            environment: environment,
            contextFuture: _contextSnapshot(),
          ),
          const SizedBox(height: 14),
          _TaskComposer(
            controller: _taskController,
            focusNode: _taskFocus,
            submitting: _submitting,
            onSubmit: _submitTask,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                zh ? '任务' : 'Tasks',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
              const Spacer(),
              Text(
                tasks.length.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (tasks.isEmpty)
            _EmptyTasks(zh: zh)
          else
            for (final task in tasks.take(12)) ...[
              _TaskCard(task: task, zh: zh),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  static bool _isZh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.zh,
    required this.environment,
    required this.contextFuture,
  });

  final bool zh;
  final EnvironmentState environment;
  final Future<AgentContextSnapshot> contextFuture;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final environmentReady = environment.phase == EnvironmentPhase.ready;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.18),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Lucide.Bot, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zh ? '代理' : 'Agent',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      zh
                          ? '把任务交给 KELIVO，由代理持续规划、执行和恢复。'
                          : 'Hand work to KELIVO for durable planning, execution and recovery.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                icon: Lucide.Terminal,
                label: environmentReady
                    ? (zh ? '环境就绪' : 'Environment ready')
                    : (zh ? '环境待准备' : 'Environment pending'),
              ),
              FutureBuilder<AgentContextSnapshot>(
                future: contextFuture,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  if (data == null) {
                    return _StatusChip(
                      icon: Lucide.workflow,
                      label: zh ? '正在载入上下文' : 'Loading context',
                    );
                  }
                  final counts =
                      '${data.memories.length} · '
                      '${data.skills.length} · '
                      '${data.mcpServers.length}';
                  return _StatusChip(
                    icon: Lucide.workflow,
                    label: zh
                        ? '记忆 / 技能 / MCP  $counts'
                        : 'Memory / Skills / MCP  $counts',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskComposer extends StatelessWidget {
  const _TaskComposer({
    required this.controller,
    required this.focusNode,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.28),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            minLines: 3,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: zh
                  ? '描述你希望代理完成的任务…'
                  : 'Describe the task you want Agent to complete…',
              hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.38)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Lucide.workflow,
                size: 16,
                color: cs.onSurface.withValues(alpha: 0.46),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  zh
                      ? '任务状态、工作区和环境会持久保存'
                      : 'Task, workspace and environment state are durable',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: submitting ? null : onSubmit,
                icon: submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Lucide.Play, size: 16),
                label: Text(zh ? '开始' : 'Start'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurface.withValues(alpha: 0.68)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: cs.onSurface.withValues(alpha: 0.68),
              fontWeight: AppFontWeights.medium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.zh});

  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            Lucide.Bot,
            size: 28,
            color: cs.onSurface.withValues(alpha: 0.34),
          ),
          const SizedBox(height: 10),
          Text(
            zh ? '还没有代理任务' : 'No Agent tasks yet',
            style: TextStyle(
              fontWeight: AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            zh
                ? '上方输入一个目标即可创建第一项任务。'
                : 'Enter a goal above to create the first task.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.48),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.zh});

  final AgentTask task;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _phaseLabel(task.phase, zh);
    final active = {
      AgentTaskPhase.preparing,
      AgentTaskPhase.running,
      AgentTaskPhase.waitingApproval,
      AgentTaskPhase.verifying,
      AgentTaskPhase.recovering,
    }.contains(task.phase);
    final resumable = {
      AgentTaskPhase.queued,
      AgentTaskPhase.paused,
      AgentTaskPhase.failed,
      AgentTaskPhase.interrupted,
    }.contains(task.phase);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.14),
          width: 0.6,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              task.phase == AgentTaskPhase.completed
                  ? Lucide.CheckCircle
                  : task.phase == AgentTaskPhase.failed
                  ? Lucide.CircleAlert
                  : Lucide.Bot,
              size: 17,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                if ((task.currentStep ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.currentStep!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.52),
                    ),
                  ),
                ],
                if ((task.lastError ?? '').isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    task.lastError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.error.withValues(alpha: 0.82),
                    ),
                  ),
                ],
                if (active || resumable) ...[
                  const SizedBox(height: 9),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final runner = context.read<AgentTaskRunner>();
                        if (active) {
                          unawaited(runner.cancel(task.id));
                        } else {
                          unawaited(runner.run(task.id));
                        }
                      },
                      icon: Icon(
                        active ? Lucide.X : Lucide.RotateCcw,
                        size: 14,
                      ),
                      label: Text(
                        active
                            ? (zh ? '取消' : 'Cancel')
                            : task.phase == AgentTaskPhase.queued
                            ? (zh ? '开始' : 'Start')
                            : (zh ? '继续' : 'Resume'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _phaseLabel(AgentTaskPhase phase, bool zh) => switch (phase) {
    AgentTaskPhase.queued => zh ? '排队中' : 'Queued',
    AgentTaskPhase.preparing => zh ? '准备中' : 'Preparing',
    AgentTaskPhase.running => zh ? '执行中' : 'Running',
    AgentTaskPhase.waitingApproval => zh ? '等待批准' : 'Approval',
    AgentTaskPhase.verifying => zh ? '验证中' : 'Verifying',
    AgentTaskPhase.paused => zh ? '已暂停' : 'Paused',
    AgentTaskPhase.completed => zh ? '已完成' : 'Completed',
    AgentTaskPhase.failed => zh ? '失败' : 'Failed',
    AgentTaskPhase.cancelled => zh ? '已取消' : 'Cancelled',
    AgentTaskPhase.interrupted => zh ? '已中断' : 'Interrupted',
    AgentTaskPhase.recovering => zh ? '恢复中' : 'Recovering',
  };
}

