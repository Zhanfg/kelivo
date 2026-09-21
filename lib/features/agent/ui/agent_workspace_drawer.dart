import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../../settings/pages/settings_page.dart';
import '../models/agent_task.dart';
import '../providers/agent_task_provider.dart';
import 'agent_settings_page.dart';
import 'agent_task_detail_page.dart';

class AgentWorkspaceDrawer extends StatelessWidget {
  const AgentWorkspaceDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final tasks = List<AgentTask>.of(context.watch<AgentTaskProvider>().tasks)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Material(
      color: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      zh ? '代理' : 'Agent',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                  ),
                  Text(
                    zh ? '任务' : 'Tasks',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: cs.outlineVariant.withValues(alpha: 0.35)),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          zh
                              ? '还没有任务。关闭侧栏后，直接在代理页面输入目标即可开始。'
                              : 'No tasks yet. Close the drawer and enter a goal on the Agent page.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.56),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return ListTile(
                          leading: Icon(_icon(task.phase)),
                          title: Text(
                            task.title.isEmpty
                                ? (zh ? '未命名任务' : 'Untitled task')
                                : task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _phase(task.phase, zh),
                            maxLines: 1,
                          ),
                          trailing: const Icon(
                            Lucide.ChevronRight,
                            size: 17,
                          ),
                          onTap: () => Navigator.of(
                            context,
                            rootNavigator: true,
                          ).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AgentTaskDetailPage(taskId: task.id),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Divider(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ListTile(
              leading: const Icon(Lucide.Settings),
              title: Text(zh ? '设置' : 'Settings'),
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const AgentSettingsPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Lucide.Settings2),
              title: Text(zh ? '全部设置' : 'All settings'),
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(AgentTaskPhase phase) => switch (phase) {
    AgentTaskPhase.running ||
    AgentTaskPhase.preparing ||
    AgentTaskPhase.verifying ||
    AgentTaskPhase.recovering => Lucide.Loader,
    AgentTaskPhase.waitingApproval => Lucide.Shield,
    AgentTaskPhase.completed => Lucide.CheckCircle,
    AgentTaskPhase.failed => Lucide.CircleX,
    AgentTaskPhase.cancelled => Lucide.Ban,
    AgentTaskPhase.interrupted || AgentTaskPhase.paused => Lucide.Pause,
    AgentTaskPhase.queued => Lucide.clock,
  };

  static String _phase(AgentTaskPhase phase, bool zh) => switch (phase) {
    AgentTaskPhase.queued => zh ? '排队' : 'Queued',
    AgentTaskPhase.preparing => zh ? '准备中' : 'Preparing',
    AgentTaskPhase.running => zh ? '执行中' : 'Running',
    AgentTaskPhase.waitingApproval => zh ? '等待批准' : 'Waiting for approval',
    AgentTaskPhase.verifying => zh ? '检查结果' : 'Checking',
    AgentTaskPhase.paused => zh ? '已暂停' : 'Paused',
    AgentTaskPhase.completed => zh ? '已完成' : 'Completed',
    AgentTaskPhase.failed => zh ? '失败' : 'Failed',
    AgentTaskPhase.cancelled => zh ? '已取消' : 'Cancelled',
    AgentTaskPhase.interrupted => zh ? '已中断' : 'Interrupted',
    AgentTaskPhase.recovering => zh ? '恢复中' : 'Recovering',
  };
}
