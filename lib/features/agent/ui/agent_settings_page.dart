import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../model/pages/default_model_page.dart';
import '../../settings/pages/memory_settings_page.dart';
import '../../workspace/pages/skills_page.dart';
import '../../workspace/pages/workspace_settings_page.dart';
import '../providers/agent_settings_provider.dart';

class AgentSettingsPage extends StatelessWidget {
  const AgentSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = context.watch<AgentSettingsProvider>();
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

    Widget nav(IconData icon, String title, Widget page, {String? subtitle}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Lucide.ChevronRight, size: 18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => page),
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
          section(zh ? '上下文与能力' : 'Context and capabilities', [
            nav(
              Lucide.Heart,
              zh ? '模型' : 'Model',
              const DefaultModelPage(),
            ),
            nav(
              Lucide.FolderCode,
              zh ? '工作区' : 'Workspace',
              const WorkspaceSettingsPage(),
            ),
            nav(
              Lucide.WandSparkles,
              'Skills',
              const SkillsPage(),
            ),
            nav(
              Lucide.Terminal,
              'MCP',
              const McpPage(),
            ),
            nav(
              Lucide.Brain,
              zh ? '记忆' : 'Memory',
              const MemorySettingsPage(),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              zh
                  ? '执行环境由 KELIVO 自动管理；这里配置的是代理行为，不暴露 Linux 实现细节。'
                  : 'KELIVO manages the execution environment automatically; this page configures Agent behavior rather than Linux internals.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
