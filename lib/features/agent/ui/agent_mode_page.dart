import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/workspace.dart';
import '../../../core/models/workspace_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../models/agent_task.dart';
import '../providers/agent_task_provider.dart';
import '../services/agent_task_runner.dart';
import 'agent_task_detail_page.dart';

class AgentModePage extends StatefulWidget {
  const AgentModePage({super.key});

  @override
  State<AgentModePage> createState() => _AgentModePageState();
}

class _AgentModePageState extends State<AgentModePage> {
  final TextEditingController _taskController = TextEditingController();
  final FocusNode _taskFocus = FocusNode();
  bool _submitting = false;

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
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AgentTaskDetailPage(taskId: task.id),
        ),
      );
      if (mounted) _taskFocus.requestFocus();
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

  @override
  Widget build(BuildContext context) {
    final zh = _isZh(context);
    final tasks = List<AgentTask>.of(context.watch<AgentTaskProvider>().tasks)
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, topInset, 16, 12),
              children: [
                if (tasks.isEmpty)
                  _EmptyTasks(zh: zh)
                else
                  for (final task in tasks) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AgentTaskDetailPage(taskId: task.id),
                        ),
                      ),
                      child: _TaskCard(task: task, zh: zh),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: _TaskComposer(
              controller: _taskController,
              focusNode: _taskFocus,
              submitting: _submitting,
              onSubmit: _submitTask,
            ),
          ),
        ],
      ),
    );
  }

  static bool _isZh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';
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
                      ? '工作区、计划与结果会自动保存'
                      : 'Workspace, plans and results are saved automatically',
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
            zh ? '把一个目标交给代理' : 'Give Agent a goal',
            style: TextStyle(
              fontWeight: AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            zh
                ? '代理会在当前工作区持续执行，并把进度和结果保留下来。'
                : 'Agent works in the current workspace and keeps progress and results.',
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
    final step = _friendlyStep(task.currentStep, zh);
    final error = _friendlyError(task.lastError, zh);
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
                  ? Lucide.TriangleAlert
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
                if (step != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    step,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.52),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    error,
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

  static String? _friendlyStep(String? raw, bool zh) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final lower = value.toLowerCase();
  if (lower.contains('preparing pi') || lower.contains('runtime')) {
    return zh ? '正在准备任务' : 'Preparing task';
  }
  if (lower.contains('pi is working') ||
      lower.contains('tool:') ||
      lower.startsWith('running ')) {
    return zh ? '正在使用工具' : 'Using tools';
  }
  if (lower.contains('requested user input')) {
    return zh ? '等待你的确认' : 'Waiting for your input';
  }
  if (lower.contains('verifying pi') || lower.contains('verifying')) {
    return zh ? '正在检查结果' : 'Checking results';
  }
  if (lower == 'completed') return zh ? '已完成' : 'Completed';
  if (lower == 'cancelled') return zh ? '已取消' : 'Cancelled';
  if (lower == 'agent failed') return zh ? '执行失败' : 'Task failed';
  return value;
}

String? _friendlyError(String? raw, bool zh) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final lower = value.toLowerCase();
  if (lower.contains('agent_model_not_configured')) {
    return zh ? '尚未配置可用模型，请先选择默认模型。' : 'No model is configured. Choose a default model first.';
  }
  if (lower.contains('runtime') ||
      lower.contains('rootfs') ||
      lower.contains('proot') ||
      lower.contains('pi_')) {
    return zh ? '代理运行环境启动失败，可以重试或查看日志。' : 'Agent runtime could not start. Retry or check logs.';
  }
  return zh ? '任务执行失败，可以重试或查看日志。' : 'Task failed. Retry or check logs.';
}

String _phaseLabel(AgentTaskPhase phase, bool zh) => switch (phase) {
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
