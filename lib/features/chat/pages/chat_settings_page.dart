import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../model/widgets/model_select_sheet.dart';

class ChatSettingsPage extends StatelessWidget {
  const ChatSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = context.watch<SettingsProvider>();
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
          section(zh ? '模型策略' : 'Model behavior', [
            SwitchListTile(
              secondary: const Icon(Lucide.MessagesSquare),
              title: Text(zh ? '每个对话独立选择模型' : 'Per-chat model selection'),
              subtitle: Text(
                zh
                    ? '开启后，聊天页切换模型只影响当前对话；关闭后会修改当前助手的默认模型。'
                    : 'When enabled, changing the model in Chat only affects the current conversation; otherwise it changes the current assistant default.',
              ),
              value: settings.perChatModelEnabled,
              onChanged: settings.setPerChatModelEnabled,
            ),
          ]),
          section(zh ? '建议回复' : 'Suggested replies', [
            SwitchListTile(
              secondary: const Icon(Lucide.Sparkles),
              title: Text(zh ? '生成建议回复' : 'Generate suggested replies'),
              subtitle: Text(
                zh
                    ? '在模型回复后生成可继续发送的下一步消息；默认跟随当前聊天模型。'
                    : 'Generate useful next-message suggestions after a reply; by default this follows the current chat model.',
              ),
              value: settings.isSuggestionGenerationEnabled,
              onChanged: (enabled) {
                if (enabled) {
                  settings.resetSuggestionModel();
                } else {
                  settings.disableSuggestionGeneration();
                }
              },
            ),
            ListTile(
              enabled: settings.isSuggestionGenerationEnabled,
              leading: const Icon(Lucide.Bot),
              title: Text(zh ? '建议回复模型' : 'Suggestion model'),
              subtitle: Text(
                settings.suggestionModelKey == null
                    ? (zh ? '跟随当前聊天模型' : 'Follow current chat model')
                    : '${settings.suggestionModelProvider} / ${settings.suggestionModelId}',
              ),
              trailing: const Icon(Lucide.ChevronRight, size: 18),
              onTap: !settings.isSuggestionGenerationEnabled
                  ? null
                  : () async {
                      final selected = await showModelSelector(
                        context,
                        initialProviderKey:
                            settings.suggestionModelProvider ??
                            settings.currentModelProvider,
                        initialModelId:
                            settings.suggestionModelId ??
                            settings.currentModelId,
                        allowInherit: settings.suggestionModelKey != null,
                        inheritLabel: zh
                            ? '跟随当前聊天模型'
                            : 'Follow current chat model',
                      );
                      if (selected == null || !context.mounted) return;
                      if (selected.isInherit) {
                        await settings.resetSuggestionModel();
                      } else {
                        await settings.setSuggestionModel(
                          selected.providerKey,
                          selected.modelId,
                        );
                      }
                    },
            ),
            SwitchListTile(
              secondary: const Icon(Lucide.Pencil),
              title: Text(zh ? '点击仅填入输入框' : 'Tap to insert only'),
              subtitle: Text(
                zh
                    ? '点击建议回复时只填入输入框，不立即发送，便于继续编辑。'
                    : 'Insert a suggestion into the composer without sending it immediately.',
              ),
              value: settings.insertSuggestionOnTapOnly,
              onChanged: settings.isSuggestionGenerationEnabled
                  ? settings.setInsertSuggestionOnTapOnly
                  : null,
            ),
          ]),
          section(zh ? '对话行为' : 'Conversation behavior', [
            SwitchListTile(
              secondary: const Icon(Lucide.Lightbulb),
              title: Text(zh ? '学习模式' : 'Learning mode'),
              subtitle: Text(
                zh
                    ? '让普通聊天更偏向讲解、引导和循序推理。'
                    : 'Bias ordinary Chat toward explanation, guidance and step-by-step reasoning.',
              ),
              value: settings.learningModeEnabled,
              onChanged: settings.setLearningModeEnabled,
            ),
            SwitchListTile(
              secondary: const Icon(Lucide.RotateCcw),
              title: Text(zh ? '重新生成前确认' : 'Confirm before regenerating'),
              subtitle: Text(
                zh
                    ? '重新生成消息前先确认，降低误触导致上下文变化的风险。'
                    : 'Ask for confirmation before regenerating a message.',
              ),
              value: settings.showRegenerateConfirmDialog,
              onChanged: settings.setShowRegenerateConfirmDialog,
            ),
            SwitchListTile(
              secondary: const Icon(Lucide.MessageSquare),
              title: Text(
                zh ? '重新生成时删除后续消息' : 'Delete trailing messages on regenerate',
              ),
              subtitle: Text(
                zh
                    ? '从历史位置重新生成时，删除该位置之后的旧分支消息。'
                    : 'When regenerating from history, remove messages that followed the regenerated point.',
              ),
              value: settings.regenerateDeleteTrailingMessages,
              onChanged: settings.setRegenerateDeleteTrailingMessages,
            ),
            SwitchListTile(
              secondary: const Icon(Lucide.GitFork),
              title: Text(zh ? '分支时保留消息版本' : 'Keep message versions when forking'),
              subtitle: Text(
                zh
                    ? '创建对话分支时保留当前消息的版本历史。'
                    : 'Preserve message-version history when creating a conversation fork.',
              ),
              value: settings.forkKeepMessageVersions,
              onChanged: settings.setForkKeepMessageVersions,
            ),
            SwitchListTile(
              secondary: const Icon(Lucide.Brain),
              title: Text(
                zh
                    ? '编辑助手消息时保留思考与工具卡片'
                    : 'Keep thinking and tool cards when editing assistant messages',
              ),
              subtitle: Text(
                zh
                    ? '编辑模型回复正文时，不自动丢弃其已有思考过程和工具调用记录。'
                    : 'Editing assistant text does not automatically discard its existing reasoning and tool-call cards.',
              ),
              value: settings.keepThinkingAndToolCardsWhenEditingAssistant,
              onChanged: settings.setKeepThinkingAndToolCardsWhenEditingAssistant,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              zh
                  ? '此页只管理聊天模式。MCP、记忆、Skills、工作区、搜索、语音等共享能力统一在顶层“设置”中管理。'
                  : 'This page only controls Chat behavior. Shared capabilities such as MCP, Memory, Skills, Workspace, Search and Voice are managed from the top-level Settings page.',
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
