import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../assistant/pages/assistant_settings_page.dart';
import '../../instruction_injection/pages/instruction_injection_page.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../model/pages/default_model_page.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import '../../search/pages/search_services_page.dart';
import '../../settings/pages/display_settings_page.dart';
import '../../settings/pages/memory_settings_page.dart';
import '../../settings/pages/tool_schema_settings_page.dart';
import '../../settings/pages/tts_services_page.dart';
import '../../workspace/pages/skills_page.dart';
import '../../workspace/pages/workspace_settings_page.dart';
import '../../world_book/pages/world_book_page.dart';

class ChatSettingsPage extends StatelessWidget {
  const ChatSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;

    Widget nav(IconData icon, String title, Widget page) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Lucide.ChevronRight, size: 18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      ),
    );

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
          Card(margin: EdgeInsets.zero, child: Column(children: children)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(zh ? '设置' : 'Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          section(zh ? '对话' : 'Chat', [
            nav(Lucide.Heart, zh ? '默认模型' : 'Default model', const DefaultModelPage()),
            nav(Lucide.Bot, zh ? '助手' : 'Assistant', const AssistantSettingsPage()),
            nav(Lucide.Monitor, zh ? '显示' : 'Display', const DisplaySettingsPage()),
            nav(Lucide.Volume2, zh ? '语音' : 'Voice', const TtsServicesPage()),
            nav(Lucide.Search, zh ? '搜索' : 'Search', const SearchServicesPage()),
          ]),
          section(zh ? '上下文与工具' : 'Context and tools', [
            nav(Lucide.Brain, zh ? '记忆' : 'Memory', const MemorySettingsPage()),
            nav(Lucide.BookOpen, zh ? '世界书' : 'World Book', const WorldBookPage()),
            nav(Lucide.WandSparkles, 'Skills', const SkillsPage()),
            nav(Lucide.Terminal, 'MCP', const McpPage()),
            nav(Lucide.FolderCode, zh ? '工作区' : 'Workspace', const WorkspaceSettingsPage()),
            nav(Lucide.Zap, zh ? '快捷短语' : 'Quick phrases', const QuickPhrasesPage()),
            nav(
              Lucide.Layers,
              zh ? '指令注入' : 'Instruction injection',
              const InstructionInjectionPage(),
            ),
            nav(
              Lucide.Wrench,
              zh ? '工具定义' : 'Tool schemas',
              const ToolSchemaSettingsPage(),
            ),
          ]),
        ],
      ),
    );
  }
}
