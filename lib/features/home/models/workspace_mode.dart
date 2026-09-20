enum WorkspaceMode { chat, story, agent }

extension WorkspaceModeCodec on WorkspaceMode {
  static WorkspaceMode fromStorage(String? value) {
    return WorkspaceMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => WorkspaceMode.chat,
    );
  }
}
