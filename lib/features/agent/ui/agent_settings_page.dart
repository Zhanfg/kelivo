import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../providers/agent_settings_provider.dart';

class AgentSettingsPage extends StatelessWidget {
  const AgentSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = context.watch<AgentSettingsProvider>();
    final appSettings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(zh ? '设置' : 'Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          section(zh ? '执行权限' : 'Execution permissions', [
            ListTile(
              leading: Icon(
                settings.permissionMode == AgentPermissionMode.ask
                    ? Lucide.CheckCircle
                    : Lucide.circleDot,
              ),
              title: Text(zh ? '请求批准' : 'Ask for approval'),
              subtitle: Text(
                zh
                    ? '读取操作自动执行；命令、写入和其他有副作用的工具先询问。'
                    : 'Reads run automatically; commands, writes and other mutating tools ask first.',
              ),
              onTap: () => settings.setPermissionMode(
                AgentPermissionMode.ask,
              ),
            ),
            ListTile(
              leading: Icon(
                settings.permissionMode == AgentPermissionMode.auto
                    ? Lucide.CheckCircle
                    : Lucide.circleDot,
              ),
              title: Text(zh ? '自动执行' : 'Auto'),
              subtitle: Text(
                zh
                    ? '允许代理在受管执行环境内连续工作，不逐项询问。'
                    : 'Let Agent work continuously inside its managed environment.',
              ),
              onTap: () => settings.setPermissionMode(
                AgentPermissionMode.auto,
              ),
            ),
            ListTile(
              leading: Icon(
                settings.permissionMode == AgentPermissionMode.planFirst
                    ? Lucide.CheckCircle
                    : Lucide.circleDot,
              ),
              title: Text(zh ? '先计划' : 'Plan first'),
              subtitle: Text(
                zh
                    ? '先只读分析并提交计划；你批准后，代理再连续实施。'
                    : 'Research read-only, present a plan, then implement continuously after approval.',
              ),
              onTap: () => settings.setPermissionMode(
                AgentPermissionMode.planFirst,
              ),
            ),
            ListTile(
              leading: Icon(
                settings.permissionMode == AgentPermissionMode.readOnly
                    ? Lucide.CheckCircle
                    : Lucide.circleDot,
              ),
              title: Text(zh ? '只读' : 'Read only'),
              subtitle: Text(
                zh
                    ? '允许读取、搜索和分析，但阻止命令与文件修改。'
                    : 'Allow reading, searching and analysis while blocking commands and edits.',
              ),
              onTap: () => settings.setPermissionMode(
                AgentPermissionMode.readOnly,
              ),
            ),
          ]),
          section(zh ? '调度与并行' : 'Scheduling and parallelism', [
            ListTile(
              leading: const Icon(Lucide.Network),
              title: Text(zh ? '最大并行子代理' : 'Max parallel subagents'),
              subtitle: Text(
                zh
                    ? '独立子任务可以并发执行；移动端默认 3 个，最多 4 个。'
                    : 'Independent subtasks may run concurrently; mobile defaults to 3 and caps at 4.',
              ),
              trailing: DropdownButton<int>(
                value: settings.maxParallelAgents,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                  DropdownMenuItem(value: 4, child: Text('4')),
                ],
                onChanged: (value) {
                  if (value != null) settings.setMaxParallelAgents(value);
                },
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Lucide.GitFork),
              title: Text(zh ? '子代理隔离工作区' : 'Isolated subagent workspaces'),
              subtitle: Text(
                zh
                    ? 'Git 项目中的并行修改可在隔离工作区执行并返回补丁，降低互相覆盖风险。'
                    : 'Parallel changes in Git projects can run in isolated workspaces and return patches.',
              ),
              value: settings.subagentIsolation,
              onChanged: settings.setSubagentIsolation,
            ),
          ]),
          section(zh ? '显示' : 'Display', [
            SwitchListTile(
              secondary: const Icon(Lucide.SquareTerminal),
              title: Text(zh ? '显示工具与命令输出' : 'Show tool and command output'),
              subtitle: Text(
                zh
                    ? '在任务时间线中显示命令、文件操作和运行输出。'
                    : 'Show commands, file operations and output in the task timeline.',
              ),
              value: settings.showToolOutput,
              onChanged: settings.setShowToolOutput,
            ),
          ]),
          section(zh ? '模型' : 'Model', [
            ListTile(
              leading: const Icon(Lucide.Bot),
              title: Text(zh ? '代理模型' : 'Agent model'),
              subtitle: Text(
                settings.hasModelOverride
                    ? '${settings.modelProvider} / ${settings.modelId}'
                    : (zh ? '跟随当前聊天模型' : 'Follow current chat model'),
              ),
              trailing: const Icon(Lucide.ChevronRight, size: 18),
              onTap: () async {
                final selected = await showModelSelector(
                  context,
                  initialProviderKey: settings.hasModelOverride
                      ? settings.modelProvider
                      : appSettings.currentModelProvider,
                  initialModelId: settings.hasModelOverride
                      ? settings.modelId
                      : appSettings.currentModelId,
                  allowInherit: settings.hasModelOverride,
                  inheritLabel: zh
                      ? '跟随当前聊天模型'
                      : 'Follow current chat model',
                );
                if (selected == null || !context.mounted) return;
                if (selected.isInherit) {
                  await settings.clearModelOverride();
                } else {
                  await settings.setModel(
                    selected.providerKey,
                    selected.modelId,
                  );
                }
              },
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              zh
                  ? '这里只配置代理模式自身行为。Memory、MCP、Skills、Workspace 等共享能力请在总设置中统一管理；执行环境由 KELIVO 自动维护，不暴露 Linux 实现细节。'
                  : 'This page only configures Agent-owned behavior. Shared capabilities such as Memory, MCP, Skills and Workspace are managed in the main Settings page; KELIVO manages the execution environment without exposing Linux internals.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
