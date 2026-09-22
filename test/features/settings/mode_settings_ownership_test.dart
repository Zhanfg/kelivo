import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mode settings keep shared capabilities at the top level', () {
    final chat = File(
      'lib/features/chat/pages/chat_settings_page.dart',
    ).readAsStringSync();
    final agent = File(
      'lib/features/agent/ui/agent_settings_page.dart',
    ).readAsStringSync();

    const sharedPages = <String>[
      'McpPage',
      'MemorySettingsPage',
      'SkillsPage',
      'WorkspaceSettingsPage',
      'SearchServicesPage',
      'TtsServicesPage',
    ];

    for (final page in sharedPages) {
      expect(chat, isNot(contains(page)), reason: 'Chat leaked shared $page');
      expect(agent, isNot(contains(page)), reason: 'Agent leaked shared $page');
    }

    expect(chat, contains('perChatModelEnabled'));
    expect(chat, contains('isSuggestionGenerationEnabled'));
    expect(chat, contains('learningModeEnabled'));
    expect(chat, contains('showRegenerateConfirmDialog'));
    expect(chat, contains('forkKeepMessageVersions'));

    expect(agent, contains('AgentPermissionMode'));
    expect(agent, contains('maxParallelAgents'));
    expect(agent, contains('subagentIsolation'));
    expect(agent, contains('hasModelOverride'));
  });

  test('global mobile Display no longer owns Chat-only behavior', () {
    final display = File(
      'lib/features/settings/pages/display_settings_page.dart',
    ).readAsStringSync();

    for (final chatOnly in <String>[
      'displaySettingsPageInsertSuggestionOnlyTitle',
      'displaySettingsPageRegenerateDeleteTrailingMessagesTitle',
      'displaySettingsPageShowRegenerateConfirmDialogTitle',
      'displaySettingsPageForkKeepMessageVersionsTitle',
      'displaySettingsPageEditAssistantKeepThinkingToolCardsTitle',
    ]) {
      expect(
        display,
        isNot(contains(chatOnly)),
        reason: 'Global Display still owns Chat-only setting: $chatOnly',
      );
    }
  });

  test('mode switcher does not convert the current conversation', () {
    final selector = File(
      'lib/features/home/widgets/workspace_mode_selector.dart',
    ).readAsStringSync();

    expect(selector, isNot(contains('ChatService')));
    expect(selector, isNot(contains('StoryModeTransitionService')));
    expect(selector, contains('onModeChanged'));
  });

  test('Home keeps stable mode and model controls together', () {
    final home = File(
      'lib/features/home/pages/home_page.dart',
    ).readAsStringSync();

    expect(home, contains('WorkspaceModeHeader('));
    expect(home, contains('onModeChanged: _handleWorkspaceModeChanged'));
    expect(home, contains('onSelectModel:'));
  });
}
