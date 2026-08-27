import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/cache/story_capability_epoch.dart';
import 'package:Kelivo/features/story_runtime/cache/story_prompt_cache_plan.dart';
import 'package:Kelivo/features/story_runtime/cache/story_prompt_compiler.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_models.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_profile_compiler.dart';

void main() {
  const compiler = StoryPromptCompiler();

  test('orders frozen and epoch-stable material before volatile runtime data', () {
    final referenceProfile = const StoryReferenceProfileCompiler().compile(
      profiles: const [
        StoryReferenceStyleProfile(
          id: 'style-1',
          documentId: 'doc-1',
          name: 'Style',
          sourceContentHash: 'hash',
          createdAtMs: 1,
          aspects: {StoryReferenceAspect.dialogue},
          dialogueMethods: ['Keep dialogue concise and indirect.'],
        ),
      ],
      invocations: const [
        StoryReferenceInvocation(profileId: 'style-1'),
      ],
    );
    final epoch = StoryCapabilityEpoch.canonical(
      epochId: 'epoch-1',
      worldlineId: 'wl-main',
      sceneEpochId: 'scene-1',
      activeSkillIds: const ['skill.base@1'],
      referenceProfileFingerprints: [referenceProfile.single.fingerprint],
    );

    final result = compiler.compile(
      capabilityEpoch: epoch,
      storyCoreInstructions: 'Second-person story core.',
      sceneBaseline: 'Scene: station platform at night.',
      skillContributions: const [
        StoryPromptContribution(
          id: 'story.skills.active',
          stability: StoryPromptStability.epochStable,
          content: 'Skill instructions.',
          order: 300,
        ),
      ],
      referenceProfiles: referenceProfile,
      volatile: const [
        StoryPromptContribution(
          id: 'story.runtime.delta',
          stability: StoryPromptStability.volatile,
          content: 'Current transient runtime delta.',
        ),
      ],
      localOnly: const [
        StoryPromptContribution(
          id: 'story.local.voice',
          stability: StoryPromptStability.localOnly,
          content: 'Never send this voice cache.',
        ),
      ],
    );

    final ids = result.plan.providerSections.map((section) => section.id).toList();
    expect(ids.indexOf('story.core.v1'), lessThan(ids.indexOf('story.scene.baseline')));
    expect(
      ids.indexOf('story.reference.style-1'),
      lessThan(ids.indexOf('story.runtime.delta')),
    );
    expect(result.providerText, isNot(contains('Never send this voice cache.')));
    expect(result.stablePrefixText, isNot(contains('Current transient runtime delta.')));
  });

  test('volatile changes keep the stable prefix fingerprint reusable', () {
    final epoch = StoryCapabilityEpoch.canonical(
      epochId: 'epoch-a',
      worldlineId: 'wl-main',
      sceneEpochId: 'scene-1',
    );
    StoryPromptCompilation build(String delta) => compiler.compile(
      capabilityEpoch: epoch,
      storyCoreInstructions: 'Stable story core.',
      volatile: [
        StoryPromptContribution(
          id: 'runtime',
          stability: StoryPromptStability.volatile,
          content: delta,
        ),
      ],
    );

    final first = build('delta A');
    final second = build('delta B');

    expect(first.stablePrefixFingerprint, second.stablePrefixFingerprint);
    expect(first.providerText, isNot(second.providerText));
  });

  test('reference invocation change rolls stable prefix fingerprint', () {
    const profile = StoryReferenceStyleProfile(
      id: 'style-1',
      documentId: 'doc-1',
      name: 'Style',
      sourceContentHash: 'hash',
      createdAtMs: 1,
      aspects: {StoryReferenceAspect.description},
      descriptionMethods: ['Use spatial anchors before sensory details.'],
    );
    const refCompiler = StoryReferenceProfileCompiler();
    final referenceA = refCompiler.compile(
      profiles: const [profile],
      invocations: const [
        StoryReferenceInvocation(profileId: 'style-1', strength: 0.4),
      ],
    );
    final referenceB = refCompiler.compile(
      profiles: const [profile],
      invocations: const [
        StoryReferenceInvocation(profileId: 'style-1', strength: 0.9),
      ],
    );

    StoryPromptCompilation build(List<StoryCompiledReferenceProfile> refs) {
      final epoch = StoryCapabilityEpoch.canonical(
        epochId: 'epoch',
        worldlineId: 'wl',
        sceneEpochId: 'scene',
        referenceProfileFingerprints: [for (final ref in refs) ref.fingerprint],
      );
      return compiler.compile(
        capabilityEpoch: epoch,
        storyCoreInstructions: 'Core.',
        referenceProfiles: refs,
      );
    }

    expect(
      build(referenceA).stablePrefixFingerprint,
      isNot(build(referenceB).stablePrefixFingerprint),
    );
  });

  test('wrong module stability is rejected at the compiler boundary', () {
    final epoch = StoryCapabilityEpoch.canonical(
      epochId: 'epoch',
      worldlineId: 'wl',
      sceneEpochId: 'scene',
    );

    expect(
      () => compiler.compile(
        capabilityEpoch: epoch,
        storyCoreInstructions: 'Core.',
        skillContributions: const [
          StoryPromptContribution(
            id: 'bad-skill',
            stability: StoryPromptStability.volatile,
            content: 'wrong class',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
