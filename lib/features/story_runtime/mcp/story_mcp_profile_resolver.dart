import '../skills/story_skill_models.dart';
import 'story_mcp_profile.dart';

final class StoryMcpProfileResolver {
  const StoryMcpProfileResolver();

  StoryMcpExposurePolicy resolve({
    required StoryMcpProfile profile,
    StoryResolvedSkillCapabilities? skills,
  }) {
    final allowedTools = <String>{...profile.toolNames};
    final allowedServers = <String>{...profile.serverIds};

    if (skills != null) {
      allowedTools.addAll(skills.toolIds);
      allowedServers.addAll(skills.mcpServerIds);
    }

    allowedTools.removeWhere((item) => item.trim().isEmpty);
    allowedServers.removeWhere((item) => item.trim().isEmpty);

    return StoryMcpExposurePolicy(
      profileId: profile.id,
      allowedToolNames: Set.unmodifiable(allowedTools),
      allowedServerIds: Set.unmodifiable(allowedServers),
      includeAssistantDefaults: profile.includeAssistantDefaults,
      requireApproval: profile.requireApproval,
    );
  }
}
