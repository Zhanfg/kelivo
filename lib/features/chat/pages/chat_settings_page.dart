import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../theme/app_font_weights.dart';

/// Settings owned by Chat mode.
///
/// Shared product capabilities (providers, MCP, memory, Skills, workspace,
/// search, TTS, etc.) live in the top-level Settings page. Keeping this page
/// limited to Chat behavior prevents a mode-specific "settings manager" from
/// silently becoming a duplicate global settings tree.
class ChatSettingsPage extends StatelessWidget {
  const ChatSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    Widget section(String title, List<Widget> children, {String? footer}) {
      return Padding(
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
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface.withValues(alpha: 0.66),
                ),
              ),
            ),
            SectionCard(children: children, dividers: true),
            if (footer != null) ...[
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  footer,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: cs.onSurface.withValues(alpha: 0.50),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget toggle({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
      bool enabled = true,
    }) {
      return SwitchListTile(
        secondary: Icon(
          icon,
          color: cs.onSurface.withValues(alpha: enabled ? 0.82 : 0.36),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: enabled ? onChanged : null,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(zh ? '设置' : 'Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          section(
            zh ? '模型行为' : 'Model behavior',
            [
              toggle(
                icon: Lucide.MessagesSquare,
                title: zh ? '每个对话独立选择模型' : 'Model per conversation',
                subtitle: zh
                    ? '开启后，顶部模型选择只固定当前对话；关闭后会修改当前助手的默认模型。'
                    : 'When enabled, the model picker pins only this conversation; otherwise it changes the current assistant default.',
                value: settings.perChatModelEnabled,
                onChanged: settings.setPerChatModelEnabled,
              ),
            ],
            footer: zh
                ? '全局默认模型与 Provider 在总设置中管理。'
                : 'Global default model and providers are managed in the main Settings page.',
          ),
          section(zh ? '思考与工具' : 'Reasoning and tools', [
            toggle(
              icon: Lucide.Brain,
              title: zh ? '显示思考卡片' : 'Show reasoning cards',
              subtitle: zh
                  ? '在聊天消息中显示模型的思考/推理过程。'
                  : 'Show model reasoning/thinking sections in chat messages.',
              value: settings.showThinkingCards,
              onChanged: settings.setShowThinkingCards,
            ),
            toggle(
              icon: Lucide.ChevronsUpDown,
              title: zh ? '完成后自动折叠思考' : 'Auto-collapse reasoning',
              subtitle: zh
                  ? '回复结束后自动收起较长的思考内容。'
                  : 'Collapse long reasoning sections after a response finishes.',
              value: settings.autoCollapseThinking,
              onChanged: settings.showThinkingCards
                  ? settings.setAutoCollapseThinking
                  : (_) {},
              enabled: settings.showThinkingCards,
            ),
            toggle(
              icon: Lucide.ListTree,
              title: zh ? '合并思考步骤' : 'Collapse reasoning steps',
              subtitle: zh
                  ? '将多个连续思考步骤收拢为更紧凑的展示。'
                  : 'Group consecutive reasoning steps into a more compact presentation.',
              value: settings.collapseThinkingSteps,
              onChanged: settings.showThinkingCards
                  ? settings.setCollapseThinkingSteps
                  : (_) {},
              enabled: settings.showThinkingCards,
            ),
            toggle(
              icon: Lucide.Wrench,
              title: zh ? '显示工具调用' : 'Show tool calls',
              subtitle: zh
                  ? '显示 MCP、本地工具与其他工具调用卡片。'
                  : 'Show MCP, local-tool and other tool-call cards.',
              value: settings.showToolCards,
              onChanged: settings.setShowToolCards,
            ),
            toggle(
              icon: Lucide.FileText,
              title: zh ? '显示工具结果摘要' : 'Show tool-result summary',
              subtitle: zh
                  ? '在工具结果较长时优先显示简洁摘要。'
                  : 'Prefer a compact summary when tool results are long.',
              value: settings.showToolResultSummary,
              onChanged: settings.showToolCards
                  ? settings.setShowToolResultSummary
                  : (_) {},
              enabled: settings.showToolCards,
            ),
          ]),
          section(zh ? '编辑与重生成' : 'Editing and regeneration', [
            toggle(
              icon: Lucide.RotateCcw,
              title: zh ? '重生成前确认' : 'Confirm before regenerating',
              subtitle: zh
                  ? '执行可能改变后续消息的重生成操作前先确认。'
                  : 'Ask before regeneration can alter the following message chain.',
              value: settings.showRegenerateConfirmDialog,
              onChanged: settings.setShowRegenerateConfirmDialog,
            ),
            toggle(
              icon: Lucide.Trash2,
              title: zh ? '重生成时删除后续消息' : 'Delete trailing messages on regenerate',
              subtitle: zh
                  ? '从较早消息重新生成时，删除它后面的现有分支。'
                  : 'When regenerating an earlier message, remove the existing trailing branch.',
              value: settings.regenerateDeleteTrailingMessages,
              onChanged: settings.setRegenerateDeleteTrailingMessages,
            ),
            toggle(
              icon: Lucide.GitFork,
              title: zh ? '分叉时保留消息版本' : 'Keep message versions when forking',
              subtitle: zh
                  ? '创建对话分叉时保留消息的历史版本信息。'
                  : 'Preserve message-version history when creating a conversation fork.',
              value: settings.forkKeepMessageVersions,
              onChanged: settings.setForkKeepMessageVersions,
            ),
            toggle(
              icon: Lucide.Sparkles,
              title: zh ? '编辑助手回复时保留思考与工具卡片' : 'Keep reasoning/tool cards when editing assistant',
              subtitle: zh
                  ? '手动编辑助手正文时，不自动丢弃已有思考和工具记录。'
                  : 'Keep existing reasoning and tool records when manually editing assistant text.',
              value: settings.keepThinkingAndToolCardsWhenEditingAssistant,
              onChanged: settings.setKeepThinkingAndToolCardsWhenEditingAssistant,
            ),
          ]),
          section(
            zh ? '学习模式' : 'Learning mode',
            [
              toggle(
                icon: Lucide.GraduationCap,
                title: zh ? '启用学习模式' : 'Enable learning mode',
                subtitle: zh
                    ? '让 Chat 在回答时更偏向教学、引导与逐步解释。'
                    : 'Bias Chat toward teaching, guided reasoning and step-by-step explanation.',
                value: settings.learningModeEnabled,
                onChanged: settings.setLearningModeEnabled,
              ),
            ],
            footer: zh
                ? 'Memory、MCP、Skills、Workspace、Search、TTS 等共享能力统一在总设置中配置。'
                : 'Shared capabilities such as Memory, MCP, Skills, Workspace, Search and TTS are configured in the main Settings page.',
          ),
        ],
      ),
    );
  }
}
