import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/agency/story_agency_policy.dart';
import 'package:Kelivo/features/story_runtime/cache/story_prompt_cache_plan.dart';
import 'package:Kelivo/features/story_runtime/models/story_runtime_models.dart';
import 'package:Kelivo/features/story_runtime/voice/story_voice_models.dart';

void main() {
  group('Story runtime semantics', () {
    test('SELF is the real user and never carries a character id', () {
      const actor = StoryActorRef.self();

      expect(actor.isSelf, isTrue);
      expect(actor.characterId, isNull);
      expect(actor.isCharacter, isFalse);
    });

    test('one stable character id can have changing presentations', () {
      const unknown = StoryCharacterPresentation(
        characterId: 'char-17',
        presentationId: 'unknown',
        displayName: '陌生女孩',
      );
      const promoted = StoryCharacterPresentation(
        characterId: 'char-17',
        presentationId: 'acting-director',
        displayName: '代理负责人',
      );

      expect(unknown.characterId, promoted.characterId);
      expect(unknown.displayName, isNot(promoted.displayName));
      expect(unknown.avatar.kind, StoryAvatarKind.initials);
    });
  });

  group('Story prompt cache plan', () {
    test('canonicalizes sections and keeps volatile data at the tail', () {
      final plan = StoryPromptCachePlan.compile(const [
        StoryPromptContribution(
          id: 'memory',
          stability: StoryPromptStability.volatile,
          content: 'retrieved memory',
        ),
        StoryPromptContribution(
          id: 'voice-persona',
          stability: StoryPromptStability.localOnly,
          content: 'never send this to the story model',
        ),
        StoryPromptContribution(
          id: 'history',
          stability: StoryPromptStability.appendOnly,
          content: 'turn history',
        ),
        StoryPromptContribution(
          id: 'scene',
          stability: StoryPromptStability.epochStable,
          content: 'scene baseline',
        ),
        StoryPromptContribution(
          id: 'system',
          stability: StoryPromptStability.frozen,
          content: 'story contract',
        ),
      ]);

      expect(
        plan.providerSections.map((section) => section.id),
        orderedEquals(['system', 'scene', 'history', 'memory']),
      );
      expect(
        plan.buildProviderText(),
        isNot(contains('never send this to the story model')),
      );
      expect(plan.localOnlySections.single.id, 'voice-persona');
    });

    test('volatile changes do not change the stable-prefix identity', () {
      final first = StoryPromptCachePlan.compile(const [
        StoryPromptContribution(
          id: 'system',
          stability: StoryPromptStability.frozen,
          content: 'same contract',
        ),
        StoryPromptContribution(
          id: 'scene',
          stability: StoryPromptStability.epochStable,
          content: 'same scene',
        ),
        StoryPromptContribution(
          id: 'memory',
          stability: StoryPromptStability.volatile,
          content: 'memory A',
        ),
      ]);
      final second = StoryPromptCachePlan.compile(const [
        StoryPromptContribution(
          id: 'system',
          stability: StoryPromptStability.frozen,
          content: 'same contract',
        ),
        StoryPromptContribution(
          id: 'scene',
          stability: StoryPromptStability.epochStable,
          content: 'same scene',
        ),
        StoryPromptContribution(
          id: 'memory',
          stability: StoryPromptStability.volatile,
          content: 'memory B',
        ),
      ]);

      expect(first.hasSameStablePrefixAs(second), isTrue);
    });

    test('duplicate module ids are rejected', () {
      expect(
        () => StoryPromptCachePlan.compile(const [
          StoryPromptContribution(
            id: 'story-core',
            stability: StoryPromptStability.frozen,
            content: 'a',
          ),
          StoryPromptContribution(
            id: 'story-core',
            stability: StoryPromptStability.volatile,
            content: 'b',
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('Story agency policy', () {
    test('world can continue without manufacturing a SELF response', () {
      const policy = StoryAgencyPolicy();
      final result = policy.decide(
        const StoryAgencySignals(requiresSelfAction: false),
      );

      expect(result.kind, StoryAgencyDecisionKind.autoContinue);
    });

    test('balanced mode permits high-confidence low-risk inertia', () {
      const policy = StoryAgencyPolicy();
      final result = policy.decide(
        const StoryAgencySignals(
          requiresSelfAction: true,
          predictionConfidence: 0.94,
          consequentiality: 0.05,
          ambiguity: 0.04,
          reversibility: 0.98,
          novelty: 0.05,
        ),
      );

      expect(result.kind, StoryAgencyDecisionKind.autoSelfReaction);
    });

    test('worldline-impacting choice always returns control to the user', () {
      const policy = StoryAgencyPolicy(mode: StoryAgencyMode.cinematic);
      final result = policy.decide(
        const StoryAgencySignals(
          requiresSelfAction: true,
          hasStructuredChoices: true,
          predictionConfidence: 0.99,
          worldlineImpact: 0.9,
          consequentiality: 0.9,
        ),
      );

      expect(result.kind, StoryAgencyDecisionKind.choiceRequired);
      expect(result.requiresUserInput, isTrue);
    });
  });

  group('Story voice identity', () {
    test('character importance does not require provider migration', () {
      const profile = StoryCharacterVoiceProfile(
        characterId: 'char-shopkeeper',
        providerId: 'azure',
        voiceId: 'zh-CN-example-neural',
        personaDescription: '语速稍慢，停顿短，语气直接。',
      );

      expect(profile.lockContinuity, isTrue);
      expect(profile.providerId, 'azure');
      expect(profile.voiceId, 'zh-CN-example-neural');
    });
  });
}
