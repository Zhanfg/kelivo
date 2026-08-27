import 'package:Kelivo/features/story_runtime/mcp/story_mcp_profile.dart';
import 'package:Kelivo/features/story_runtime/mcp/story_mcp_profile_resolver.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile and active Skill capabilities merge into one allow-list', () {
    const profile = StoryMcpProfile(
      id: 'story-default',
      name: 'Story',
      serverIds: <String>['server-a'],
      toolNames: <String>['lookup_lore'],
    );
    const skills = StoryResolvedSkillCapabilities(
      activeSkills: <StorySkillManifest>[],
      instructions: <String>[],
      worldBookIds: <String>[],
      mcpServerIds: <String>['server-b'],
      toolIds: <String>['serialize_story'],
      memoryReadCategories: <String>[],
      memoryWriteCategories: <String>[],
      permissions: <StorySkillPermission>{StorySkillPermission.mcp},
      ttsPolicy: StorySkillTtsPolicy.inherit,
    );

    final policy = const StoryMcpProfileResolver().resolve(
      profile: profile,
      skills: skills,
    );

    expect(policy.allowedServerIds, {'server-a', 'server-b'});
    expect(policy.allowedToolNames, {'lookup_lore', 'serialize_story'});
    expect(policy.includeAssistantDefaults, isFalse);
    expect(policy.requireApproval, isTrue);
  });
}
