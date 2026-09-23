import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';

final class StoryWorldTreeNode {
  const StoryWorldTreeNode({
    required this.nodeId,
    required this.messageId,
    required this.groupId,
    required this.version,
    required this.selected,
    this.parentNodeId,
  });

  final String nodeId;
  final String messageId;
  final String groupId;
  final int version;
  final bool selected;
  final String? parentNodeId;
}

final class StoryWorldTreeProjection {
  const StoryWorldTreeProjection({
    required this.nodes,
    required this.selectedPath,
  });

  final List<StoryWorldTreeNode> nodes;
  final List<StoryWorldTreeNode> selectedPath;

  StoryWorldTreeNode? get currentNode =>
      selectedPath.isEmpty ? null : selectedPath.last;

  static StoryWorldTreeProjection fromKelivoTimeline({
    required Conversation conversation,
    required List<ChatMessage> messages,
  }) {
    final groupOrder = <String>[];
    final groups = <String, List<ChatMessage>>{};
    for (final message in messages) {
      final groupId = message.groupId ?? message.id;
      final revisions = groups[groupId];
      if (revisions == null) {
        groupOrder.add(groupId);
        groups[groupId] = <ChatMessage>[message];
      } else {
        revisions.add(message);
      }
    }

    final nodes = <StoryWorldTreeNode>[];
    final selectedPath = <StoryWorldTreeNode>[];
    String? selectedParentNodeId;
    for (final groupId in groupOrder) {
      final revisions = groups[groupId]!;
      final selected = _selectRevision(
        revisions,
        conversation.versionSelections[groupId],
      );
      final selectedNodeId = nodeId(groupId, selected.version);
      for (final revision in revisions) {
        final isSelected = revision.id == selected.id;
        final node = StoryWorldTreeNode(
          nodeId: nodeId(groupId, revision.version),
          messageId: revision.id,
          groupId: groupId,
          version: revision.version,
          selected: isSelected,
          parentNodeId: selectedParentNodeId,
        );
        nodes.add(node);
        if (isSelected) selectedPath.add(node);
      }
      selectedParentNodeId = selectedNodeId;
    }
    return StoryWorldTreeProjection(
      nodes: List.unmodifiable(nodes),
      selectedPath: List.unmodifiable(selectedPath),
    );
  }

  static String nodeId(String groupId, int version) => '$groupId@$version';

  static ChatMessage _selectRevision(
    List<ChatMessage> revisions,
    int? selectedVersion,
  ) {
    if (selectedVersion != null) {
      for (var index = revisions.length - 1; index >= 0; index--) {
        final revision = revisions[index];
        if (revision.version == selectedVersion) return revision;
      }
    }
    var selected = revisions.first;
    for (final revision in revisions.skip(1)) {
      if (revision.version >= selected.version) selected = revision;
    }
    return selected;
  }
}
