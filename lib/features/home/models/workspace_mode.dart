enum WorkspaceMode { chat, story, agent }

const String conversationWorkspaceModeKey = 'workspace_mode_v1';

extension WorkspaceModeCodec on WorkspaceMode {
  static WorkspaceMode fromStorage(String? value) {
    return WorkspaceMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => WorkspaceMode.chat,
    );
  }
}

/// Returns the workspace that owns a native conversation.
///
/// Legacy conversations predate workspace isolation, so an absent or unknown
/// tag remains Chat by default. Agent owns durable AgentTask records rather
/// than native ChatService conversations.
WorkspaceMode workspaceModeFromConversationExtras(
  Map<String, dynamic> extras,
) {
  final raw = extras[conversationWorkspaceModeKey];
  if (raw is! String) return WorkspaceMode.chat;
  final parsed = WorkspaceModeCodec.fromStorage(raw);
  return parsed == WorkspaceMode.agent ? WorkspaceMode.chat : parsed;
}

Map<String, dynamic> withConversationWorkspaceMode(
  Map<String, dynamic> extras,
  WorkspaceMode mode,
) {
  final next = Map<String, dynamic>.from(extras);
  next[conversationWorkspaceModeKey] =
      (mode == WorkspaceMode.story ? WorkspaceMode.story : WorkspaceMode.chat)
          .name;
  return next;
}
