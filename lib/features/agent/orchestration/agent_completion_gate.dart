/// #45 Independent completion policy. No execution or Artifact IO is performed.
enum AgentCompletionDecision { accept, reject, reviewRequired }

enum AgentExecutionOutcome { succeeded, failed, timedOut, unknown }

final class AgentCompletionEvidence {
  AgentCompletionEvidence({
    required this.outcome,
    required this.testsPassed,
    required this.testsExecuted,
    required this.expectedArtifacts,
    required Iterable<String> verifiedArtifactIds,
    required this.operatorApproved,
  }) : verifiedArtifactIds = Set.unmodifiable(verifiedArtifactIds) {
    if (testsPassed < 0 ||
        testsExecuted < 0 ||
        testsPassed > testsExecuted ||
        expectedArtifacts < 0 ||
        this.verifiedArtifactIds.length > 128 ||
        this.verifiedArtifactIds.any(
          (id) => !RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(id),
        )) {
      throw ArgumentError('Invalid completion evidence');
    }
  }

  final AgentExecutionOutcome outcome;
  final int testsPassed;
  final int testsExecuted;
  final int expectedArtifacts;
  final Set<String> verifiedArtifactIds;
  final bool operatorApproved;
}

final class AgentCompletionGate {
  const AgentCompletionGate();

  AgentCompletionDecision evaluate(AgentCompletionEvidence evidence) {
    if (evidence.outcome == AgentExecutionOutcome.unknown) {
      return AgentCompletionDecision.reviewRequired;
    }
    if (evidence.outcome != AgentExecutionOutcome.succeeded ||
        evidence.testsExecuted == 0 ||
        evidence.testsPassed != evidence.testsExecuted ||
        evidence.verifiedArtifactIds.length < evidence.expectedArtifacts) {
      return AgentCompletionDecision.reject;
    }
    if (!evidence.operatorApproved) {
      return AgentCompletionDecision.reviewRequired;
    }
    return AgentCompletionDecision.accept;
  }
}
