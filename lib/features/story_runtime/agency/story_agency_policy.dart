/// Local policy gate deciding when Story Mode may continue without explicit
/// user input.
///
/// The story model can suggest a response, but this gate is intentionally
/// deterministic: AI may automate inertia and low-risk habits, never invent a
/// high-impact user commitment.
library;

enum StoryAgencyMode { manual, balanced, cinematic }

enum StoryAgencyDecisionKind {
  autoContinue,
  autoSelfReaction,
  softInput,
  hardInput,
  choiceRequired,
}

final class StoryAgencySignals {
  const StoryAgencySignals({
    required this.requiresSelfAction,
    this.hasStructuredChoices = false,
    this.explicitUserIntervention = false,
    this.consequentiality = 0,
    this.ambiguity = 0,
    this.predictionConfidence = 0,
    this.reversibility = 1,
    this.novelty = 0,
    this.identityImpact = 0,
    this.relationshipImpact = 0,
    this.worldlineImpact = 0,
  }) : assert(consequentiality >= 0 && consequentiality <= 1),
       assert(ambiguity >= 0 && ambiguity <= 1),
       assert(predictionConfidence >= 0 && predictionConfidence <= 1),
       assert(reversibility >= 0 && reversibility <= 1),
       assert(novelty >= 0 && novelty <= 1),
       assert(identityImpact >= 0 && identityImpact <= 1),
       assert(relationshipImpact >= 0 && relationshipImpact <= 1),
       assert(worldlineImpact >= 0 && worldlineImpact <= 1);

  final bool requiresSelfAction;
  final bool hasStructuredChoices;
  final bool explicitUserIntervention;

  final double consequentiality;
  final double ambiguity;
  final double predictionConfidence;
  final double reversibility;
  final double novelty;
  final double identityImpact;
  final double relationshipImpact;
  final double worldlineImpact;
}

final class StoryAgencyDecision {
  const StoryAgencyDecision(this.kind, {required this.reasonCode});

  final StoryAgencyDecisionKind kind;

  /// Stable machine-readable diagnostic code, not hidden chain-of-thought.
  final String reasonCode;

  bool get requiresUserInput =>
      kind == StoryAgencyDecisionKind.hardInput ||
      kind == StoryAgencyDecisionKind.choiceRequired;
}

final class StoryAgencyPolicy {
  const StoryAgencyPolicy({this.mode = StoryAgencyMode.balanced});

  final StoryAgencyMode mode;

  StoryAgencyDecision decide(StoryAgencySignals signals) {
    if (!signals.requiresSelfAction) {
      return const StoryAgencyDecision(
        StoryAgencyDecisionKind.autoContinue,
        reasonCode: 'world_can_continue',
      );
    }

    if (signals.explicitUserIntervention) {
      return _manualDecision(signals, 'user_intervened');
    }

    if (_isHardBoundary(signals)) {
      return _manualDecision(signals, 'high_impact_boundary');
    }

    if (mode == StoryAgencyMode.manual) {
      return _manualDecision(signals, 'manual_mode');
    }

    final thresholds = switch (mode) {
      StoryAgencyMode.manual => (confidence: 1.0, risk: 0.0),
      StoryAgencyMode.balanced => (confidence: 0.82, risk: 0.22),
      StoryAgencyMode.cinematic => (confidence: 0.68, risk: 0.34),
    };

    final risk = _riskScore(signals);
    if (signals.predictionConfidence >= thresholds.confidence &&
        risk <= thresholds.risk) {
      return const StoryAgencyDecision(
        StoryAgencyDecisionKind.autoSelfReaction,
        reasonCode: 'high_confidence_low_risk',
      );
    }

    if (risk <= 0.48 && signals.predictionConfidence >= 0.50) {
      return const StoryAgencyDecision(
        StoryAgencyDecisionKind.softInput,
        reasonCode: 'optional_intervention',
      );
    }

    return _manualDecision(signals, 'insufficient_confidence');
  }

  StoryAgencyDecision _manualDecision(
    StoryAgencySignals signals,
    String reasonCode,
  ) {
    return StoryAgencyDecision(
      signals.hasStructuredChoices
          ? StoryAgencyDecisionKind.choiceRequired
          : StoryAgencyDecisionKind.hardInput,
      reasonCode: reasonCode,
    );
  }

  bool _isHardBoundary(StoryAgencySignals signals) {
    return signals.worldlineImpact >= 0.45 ||
        signals.identityImpact >= 0.55 ||
        signals.relationshipImpact >= 0.65 ||
        signals.consequentiality >= 0.70 ||
        signals.reversibility <= 0.25;
  }

  double _riskScore(StoryAgencySignals signals) {
    final weighted =
        signals.consequentiality * 0.25 +
        signals.ambiguity * 0.20 +
        (1 - signals.reversibility) * 0.15 +
        signals.novelty * 0.10 +
        signals.identityImpact * 0.10 +
        signals.relationshipImpact * 0.10 +
        signals.worldlineImpact * 0.10;
    return weighted.clamp(0.0, 1.0);
  }
}
