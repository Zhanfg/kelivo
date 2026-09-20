import '../skills/story_skill_models.dart';
import 'story_mcp_profile.dart';

final class StoryMcpProfileResolver {
  const StoryMcpProfileResolver();

  static const String automaticStoryProfileId = 'story:auto';

  /// Conservative default for normal Story turns.
  ///
  /// Assistant-level MCP selections are intentionally not inherited. Only
  /// capabilities declared by currently active Story Skills are exposed, and
  /// Kelivo's native approval gate remains authoritative.
  StoryMcpExposurePolicy resolveAutomaticStory({
    StoryResolvedSkillCapabilities? skills,
  }) {
    final allowedTools = <String>{
      ...?skills?.toolIds,
    }..removeWhere((item) => item.trim().isEmpty);
    final allowedServers = <String>{
      ...?skills?.mcpServerIds,
    }..removeWhere((item) => item.trim().isEmpty);

    return StoryMcpExposurePolicy(
      profileId: automaticStoryProfileId,
      allowedToolNames: Set.unmodifiable(allowedTools),
      allowedServerIds: Set.unmodifiable(allowedServers),
      includeAssistantDefaults: false,
      requireApproval: true,
    );
  }

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
