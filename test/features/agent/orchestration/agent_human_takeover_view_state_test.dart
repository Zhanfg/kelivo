import 'package:Kelivo/features/agent/orchestration/agent_human_takeover_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AgentHumanTakeoverViewState state() => AgentHumanTakeoverViewState([
    AgentPanelNode(
      agentId: 'root',
      parentId: null,
      phase: AgentViewPhase.running,
      approvalPending: false,
      budgetRemaining: 100,
      logCount: 2,
    ),
    AgentPanelNode(
      agentId: 'child',
      parentId: 'root',
      phase: AgentViewPhase.queued,
      approvalPending: true,
      budgetRemaining: 50,
      logCount: 0,
    ),
  ]);

  test('defaults to human-owned and paused, mock tree read-only', () {
    final panel = state();
    expect(panel.mockAgentMayContinue, isFalse);
    expect(panel.nodes['child']!.approvalPending, isTrue);
    expect(() => panel.nodes.clear(), throwsUnsupportedError);
  });

  test('explicit approval required to resume, takeover always pauses', () {
    final panel = state();
    expect(
      () => panel.approveAgentControl(userApproved: false),
      throwsStateError,
    );
    panel.approveAgentControl(userApproved: true);
    expect(panel.mockAgentMayContinue, isTrue);
    panel.takeOver();
    expect(panel.owner, AgentViewOwner.human);
    expect(panel.paused, isTrue);
    expect(panel.mockAgentMayContinue, isFalse);
  });

  test('orphan, negative budget and duplicate agent IDs are refused', () {
    expect(
      () => AgentHumanTakeoverViewState([
        AgentPanelNode(
          agentId: 'orphan',
          parentId: 'missing',
          phase: AgentViewPhase.queued,
          approvalPending: false,
          budgetRemaining: 0,
          logCount: 0,
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => AgentPanelNode(
        agentId: 'bad',
        parentId: null,
        phase: AgentViewPhase.running,
        approvalPending: false,
        budgetRemaining: -1,
        logCount: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => AgentHumanTakeoverViewState([
        AgentPanelNode(
          agentId: 'dup',
          parentId: null,
          phase: AgentViewPhase.queued,
          approvalPending: false,
          budgetRemaining: 0,
          logCount: 0,
        ),
        AgentPanelNode(
          agentId: 'dup',
          parentId: null,
          phase: AgentViewPhase.queued,
          approvalPending: false,
          budgetRemaining: 0,
          logCount: 0,
        ),
      ]),
      throwsArgumentError,
    );
  });
}
