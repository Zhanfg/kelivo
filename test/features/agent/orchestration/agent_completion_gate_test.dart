import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/agent/orchestration/agent_completion_gate.dart';

void main() {
  AgentCompletionEvidence evidence({
    AgentExecutionOutcome outcome = AgentExecutionOutcome.succeeded,
    int passed = 2,
    int executed = 2,
    int artifacts = 1,
    Iterable<String> ids = const ['artifact:verified'],
    bool approved = true,
  }) => AgentCompletionEvidence(
    outcome: outcome,
    testsPassed: passed,
    testsExecuted: executed,
    expectedArtifacts: artifacts,
    verifiedArtifactIds: ids,
    operatorApproved: approved,
  );

  const gate = AgentCompletionGate();
  test('verified job with complete tests and artifacts may complete', () {
    expect(gate.evaluate(evidence()), AgentCompletionDecision.accept);
  });
  test('failed tests, absent artifacts and timeout cannot complete', () {
    expect(gate.evaluate(evidence(passed: 1)), AgentCompletionDecision.reject);
    expect(
      gate.evaluate(evidence(ids: const [])),
      AgentCompletionDecision.reject,
    );
    expect(
      gate.evaluate(evidence(outcome: AgentExecutionOutcome.timedOut)),
      AgentCompletionDecision.reject,
    );
    expect(
      gate.evaluate(evidence(executed: 0, passed: 0)),
      AgentCompletionDecision.reject,
    );
  });
  test('unknown outcome and absent operator approval require review', () {
    expect(
      gate.evaluate(evidence(outcome: AgentExecutionOutcome.unknown)),
      AgentCompletionDecision.reviewRequired,
    );
    expect(
      gate.evaluate(evidence(approved: false)),
      AgentCompletionDecision.reviewRequired,
    );
  });
  test('invalid counts, IDs and mutable evidence rejected or frozen', () {
    expect(() => evidence(passed: 3), throwsArgumentError);
    expect(() => evidence(ids: const ['../path']), throwsArgumentError);
    final ids = <String>{'artifact:one'};
    final receipt = evidence(ids: ids);
    ids.clear();
    expect(receipt.verifiedArtifactIds, {'artifact:one'});
    expect(
      () => receipt.verifiedArtifactIds.add('artifact:two'),
      throwsUnsupportedError,
    );
  });
}
