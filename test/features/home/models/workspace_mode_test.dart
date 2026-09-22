import 'package:Kelivo/features/home/models/workspace_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy untagged conversations stay in Chat', () {
    expect(
      workspaceModeFromConversationExtras(const <String, dynamic>{}),
      WorkspaceMode.chat,
    );
  });

  test('Story ownership round-trips without dropping other extras', () {
    final extras = withConversationWorkspaceMode(
      const <String, dynamic>{'workspace_id': 'ws-1'},
      WorkspaceMode.story,
    );

    expect(extras['workspace_id'], 'ws-1');
    expect(extras[conversationWorkspaceModeKey], 'story');
    expect(workspaceModeFromConversationExtras(extras), WorkspaceMode.story);
  });

  test('Agent never claims a native chat conversation', () {
    final extras = withConversationWorkspaceMode(
      const <String, dynamic>{},
      WorkspaceMode.agent,
    );

    expect(extras[conversationWorkspaceModeKey], 'chat');
    expect(workspaceModeFromConversationExtras(extras), WorkspaceMode.chat);
  });
}
