import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/skills/story_skill_activation_policy.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_models.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_resolver.dart';

void main() {
  const resolver = StorySkillResolver();
  const defaultSkill = StorySkillManifest(
    id: 'human-writing',
    name: 'Human Writing',
    version: '1',
    activationModes: {StorySkillActivationMode.always},
    metadata: {'defaultEnabled': true},
  );
  const manualSkill = StorySkillManifest(
    id: 'visual-taste',
    name: 'Visual Taste',
    version: '1',
    activationModes: {StorySkillActivationMode.manual},
    metadata: {'defaultEnabled': false},
  );

  test('default-enabled Skill receives an effective binding when unset', () {
    final effective = StorySkillActivationPolicy.effectiveBindings(
      manifests: const [defaultSkill, manualSkill],
      bindings: const [],
      assistantId: 'assistant-1',
    );

    expect(effective, hasLength(1));
    expect(effective.single.skillId, 'human-writing');
    expect(effective.single.enabled, isTrue);
    expect(
      StorySkillActivationPolicy.isEnabled(
        manifest: defaultSkill,
        bindings: const [],
        assistantId: 'assistant-1',
      ),
      isTrue,
    );
  });

  test('explicit disabled binding overrides built-in default permanently', () {
    const bindings = [
      StorySkillBinding(
        assistantId: 'assistant-1',
        skillId: 'human-writing',
        enabled: false,
      ),
    ];
    final effective = StorySkillActivationPolicy.effectiveBindings(
      manifests: const [defaultSkill],
      bindings: bindings,
      assistantId: 'assistant-1',
    );

    expect(effective, hasLength(1));
    expect(effective.single.enabled, isFalse);
    expect(
      StorySkillActivationPolicy.isEnabled(
        manifest: defaultSkill,
        bindings: bindings,
        assistantId: 'assistant-1',
      ),
      isFalse,
    );
    final resolved = resolver.resolve(
      manifests: const [defaultSkill],
      bindings: effective,
      context: const StorySkillActivationContext(
        assistantId: 'assistant-1',
      ),
    );
    expect(resolved.activeSkills, isEmpty);
  });

  test('manual Skill activates only after explicit enable', () {
    const bindings = [
      StorySkillBinding(
        assistantId: 'assistant-1',
        skillId: 'visual-taste',
      ),
    ];
    final effective = StorySkillActivationPolicy.effectiveBindings(
      manifests: const [manualSkill],
      bindings: bindings,
      assistantId: 'assistant-1',
    );
    final enabledIds = <String>{
      for (final binding in effective)
        if (binding.enabled) binding.skillId,
    };
    final resolved = resolver.resolve(
      manifests: const [manualSkill],
      bindings: effective,
      context: StorySkillActivationContext(
        assistantId: 'assistant-1',
        manualEnabledSkillIds: enabledIds,
      ),
    );

    expect(resolved.activeSkills.map((skill) => skill.id), ['visual-taste']);
  });
}
