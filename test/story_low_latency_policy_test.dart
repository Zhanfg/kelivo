import 'package:Kelivo/features/story_runtime/orchestration/story_low_latency_policy.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default Story policy omits optional native capability surfaces', () {
    const skills = StoryResolvedSkillCapabilities(
      activeSkills: <StorySkillManifest>[],
      instructions: <String>[],
      worldBookIds: <String>[],
      mcpServerIds: <String>[],
      toolIds: <String>[],
      memoryReadCategories: <String>[],
      memoryWriteCategories: <String>[],
      permissions: <StorySkillPermission>{},
      ttsPolicy: StorySkillTtsPolicy.inherit,
    );

    final policy = StoryLowLatencyPolicy.fromSkills(skills);
    expect(policy.allowNativeMemory, isFalse);
    expect(policy.allowNativeSearch, isFalse);
    expect(policy.allowNativeWorldBook, isFalse);
    expect(policy.allowNativeInstructionInjection, isFalse);
  });

  test('requested Skill capabilities are represented in the policy', () {
    const skills = StoryResolvedSkillCapabilities(
      activeSkills: <StorySkillManifest>[],
      instructions: <String>[],
      worldBookIds: <String>['lore-main'],
      mcpServerIds: <String>[],
      toolIds: <String>['research_search'],
      memoryReadCategories: <String>['character'],
      memoryWriteCategories: <String>[],
      permissions: <StorySkillPermission>{
        StorySkillPermission.memoryRead,
        StorySkillPermission.network,
      },
      ttsPolicy: StorySkillTtsPolicy.inherit,
    );

    final policy = StoryLowLatencyPolicy.fromSkills(skills);
    expect(policy.allowNativeMemory, isTrue);
    expect(policy.allowNativeSearch, isTrue);
    expect(policy.allowNativeWorldBook, isTrue);
    expect(policy.requestedWorldBookIds, {'lore-main'});
    expect(policy.allowNativeInstructionInjection, isFalse);
  });

  test('Chat compatibility policy preserves existing behavior', () {
    const policy = StoryLowLatencyPolicy.chatCompatibility();
    expect(policy.allowNativeMemory, isTrue);
    expect(policy.allowNativeSearch, isTrue);
    expect(policy.allowNativeWorldBook, isTrue);
    expect(policy.allowNativeInstructionInjection, isTrue);
  });
}
