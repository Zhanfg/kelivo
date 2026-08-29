enum ComposerReasoningLevel { auto, off, low, medium, high, max }

const int composerReasoningAutoBudget = -1;
const int composerReasoningOffBudget = 0;
const int composerReasoningLowBudget = 1024;
const int composerReasoningMediumBudget = 16000;
const int composerReasoningHighBudget = 32000;
const int composerReasoningXhighBudget = 64000;
const int composerReasoningMaxBudget = 128000;

/// Maps Kelivo's persisted thinking budget to the six-level Composer vocabulary.
///
/// Existing custom budgets are not rewritten by this function. The mapping is
/// only used to present a stable label/slider position until the user explicitly
/// chooses one of the Composer presets.
ComposerReasoningLevel composerReasoningLevelForBudget(int? budget) {
  if (budget == null || budget == composerReasoningAutoBudget) {
    return ComposerReasoningLevel.auto;
  }
  if (budget <= composerReasoningOffBudget) {
    return ComposerReasoningLevel.off;
  }
  if (budget <= 8192) {
    return ComposerReasoningLevel.low;
  }
  if (budget <= 24000) {
    return ComposerReasoningLevel.medium;
  }
  if (budget <= composerReasoningHighBudget) {
    return ComposerReasoningLevel.high;
  }
  return ComposerReasoningLevel.max;
}

/// Resolves a Composer preset back to the highest budget supported by the
/// selected model. This keeps the UI vocabulary independent from provider-
/// specific numeric budgets.
int budgetForComposerReasoningLevel(
  ComposerReasoningLevel level, {
  required bool supportsXhigh,
  required bool supportsMax,
}) {
  return switch (level) {
    ComposerReasoningLevel.auto => composerReasoningAutoBudget,
    ComposerReasoningLevel.off => composerReasoningOffBudget,
    ComposerReasoningLevel.low => composerReasoningLowBudget,
    ComposerReasoningLevel.medium => composerReasoningMediumBudget,
    ComposerReasoningLevel.high => composerReasoningHighBudget,
    ComposerReasoningLevel.max =>
      supportsMax
          ? composerReasoningMaxBudget
          : supportsXhigh
          ? composerReasoningXhighBudget
          : composerReasoningHighBudget,
  };
}

bool isComposerReasoningPresetBudget(int? budget) {
  return budget == null ||
      budget == composerReasoningAutoBudget ||
      budget == composerReasoningOffBudget ||
      budget == composerReasoningLowBudget ||
      budget == composerReasoningMediumBudget ||
      budget == composerReasoningHighBudget ||
      budget == composerReasoningXhighBudget ||
      budget == composerReasoningMaxBudget;
}
