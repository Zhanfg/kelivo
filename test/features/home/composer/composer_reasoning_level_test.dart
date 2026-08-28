import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/composer/composer_reasoning_level.dart';

void main() {
  group('composerReasoningLevelForBudget', () {
    test('treats null and -1 as auto', () {
      expect(
        composerReasoningLevelForBudget(null),
        ComposerReasoningLevel.auto,
      );
      expect(
        composerReasoningLevelForBudget(-1),
        ComposerReasoningLevel.auto,
      );
    });

    test('maps standard presets to the six-level vocabulary', () {
      expect(
        composerReasoningLevelForBudget(0),
        ComposerReasoningLevel.off,
      );
      expect(
        composerReasoningLevelForBudget(1024),
        ComposerReasoningLevel.low,
      );
      expect(
        composerReasoningLevelForBudget(16000),
        ComposerReasoningLevel.medium,
      );
      expect(
        composerReasoningLevelForBudget(32000),
        ComposerReasoningLevel.high,
      );
      expect(
        composerReasoningLevelForBudget(64000),
        ComposerReasoningLevel.max,
      );
      expect(
        composerReasoningLevelForBudget(128000),
        ComposerReasoningLevel.max,
      );
    });

    test('does not require custom budgets to be rewritten before display', () {
      expect(
        composerReasoningLevelForBudget(2048),
        ComposerReasoningLevel.low,
      );
      expect(
        composerReasoningLevelForBudget(20000),
        ComposerReasoningLevel.medium,
      );
      expect(
        composerReasoningLevelForBudget(30000),
        ComposerReasoningLevel.high,
      );
      expect(
        composerReasoningLevelForBudget(48000),
        ComposerReasoningLevel.max,
      );
    });
  });

  group('budgetForComposerReasoningLevel', () {
    test('keeps auto/off/low/medium/high provider independent', () {
      expect(
        budgetForComposerReasoningLevel(
          ComposerReasoningLevel.auto,
          supportsXhigh: false,
          supportsMax: false,
        ),
        -1,
      );
      expect(
        budgetForComposerReasoningLevel(
          ComposerReasoningLevel.off,
          supportsXhigh: false,
          supportsMax: false,
        ),
        0,
      );
      expect(
        budgetForComposerReasoningLevel(
          ComposerReasoningLevel.low,
          supportsXhigh: false,
          supportsMax: false,
        ),
        1024,
      );
      expect(
        budgetForComposerReasoningLevel(
          ComposerReasoningLevel.medium,
          supportsXhigh: false,
          supportsMax: false,
        ),
        16000,
      );
      expect(
        budgetForComposerReasoningLevel(
          ComposerReasoningLevel.high,
          supportsXhigh: false,
          supportsMax: false,
        ),
        32000,
      );
    });

    test('resolves max to the selected model capability ceiling', () {
      expect(
        budgetForComposerReasoningLevel(
          ComposerReasoningLevel.max,
          supportsXhigh: false,
          supportsMax: false,
        ),
        32000,
      );
      expect(
        budgetForComposerReasoningLevel(
          ComposerReasoningLevel.max,
          supportsXhigh: true,
          supportsMax: false,
        ),
        64000,
      );
      expect(
        budgetForComposerReasoningLevel(
          ComposerReasoningLevel.max,
          supportsXhigh: true,
          supportsMax: true,
        ),
        128000,
      );
    });
  });
}
