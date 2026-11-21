/// #44 read-only mock Agent panel with explicit human takeover.
/// No runtime scheduler, subprocess, approval UI or task execution is wired.
enum AgentViewOwner { agent, human }

enum AgentViewPhase { queued, running, paused, completed, failed }

final class AgentPanelNode {
  AgentPanelNode({
    required this.agentId,
    required this.parentId,
    required this.phase,
    required this.approvalPending,
    required this.budgetRemaining,
    required this.logCount,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_.:-]{1,64}$').hasMatch(agentId) ||
        parentId != null &&
            !RegExp(r'^[A-Za-z0-9_.:-]{1,64}$').hasMatch(parentId!) ||
        budgetRemaining < 0 ||
        logCount < 0 ||
        parentId == agentId) {
      throw ArgumentError('Invalid Agent panel observation');
    }
  }
  final String agentId;
  final String? parentId;
  final AgentViewPhase phase;
  final bool approvalPending;
  final int budgetRemaining;
  final int logCount;
}

final class AgentHumanTakeoverViewState {
  AgentHumanTakeoverViewState(Iterable<AgentPanelNode> observations)
    : nodes = Map.unmodifiable({
        for (final node in observations) node.agentId: node,
      }) {
    final input = observations.toList();
    if (input.isEmpty ||
        input.length != nodes.length ||
        input.any(
          (node) => node.parentId != null && !nodes.containsKey(node.parentId),
        )) {
      throw ArgumentError('Duplicate, orphaned or missing mock Agent tree');
    }
  }

  final Map<String, AgentPanelNode> nodes;
  AgentViewOwner _owner = AgentViewOwner.human;
  bool _paused = true;
  AgentViewOwner get owner => _owner;
  bool get paused => _paused;

  /// Allow simulated autonomy only after explicit human approval.
  void approveAgentControl({required bool userApproved}) {
    if (!userApproved) throw StateError('Human approval required');
    _owner = AgentViewOwner.agent;
    _paused = false;
  }

  /// Human takeover always revokes simulated Agent control.
  void takeOver() {
    _owner = AgentViewOwner.human;
    _paused = true;
  }

  /// Never claim this state changes real scheduling or OS permissions.
  bool get mockAgentMayContinue => _owner == AgentViewOwner.agent && !_paused;
}
