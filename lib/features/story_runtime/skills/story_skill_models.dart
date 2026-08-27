/// Story Skill domain models.
///
/// A Skill is a versioned capability package, not a free-form prompt. It may
/// contribute instructions and request existing Kelivo subsystems (WorldBook,
/// MCP/tools, Memory and TTS), but it never bypasses their native permission or
/// approval paths.
library;

enum StorySkillActivationMode {
  manual,
  always,
  sceneTag,
  condition,
  director,
  serialDue,
}

enum StorySkillPermission {
  memoryRead,
  memoryWrite,
  mcp,
  localTools,
  network,
  filesystemRead,
  filesystemWrite,
  tts,
}

enum StorySkillTtsPolicy { inherit, preferEnabled, disabled }

final class StorySkillCompatibility {
  const StorySkillCompatibility({
    this.minKelivoVersion,
    this.maxKelivoVersion,
    this.minStoryProtocol = 1,
    this.platforms = const <String>{},
  });

  final String? minKelivoVersion;
  final String? maxKelivoVersion;
  final int minStoryProtocol;
  final Set<String> platforms;
}

final class StorySkillHook {
  const StorySkillHook({
    required this.event,
    required this.handler,
    this.localOnly = true,
  });

  /// Stable lifecycle event name, e.g. `before_story_turn`.
  final String event;

  /// Handler id resolved by the host runtime. This is not executable source.
  final String handler;

  /// Remote hook execution is not part of the foundation contract.
  final bool localOnly;
}

final class StorySkillManifest {
  const StorySkillManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description = '',
    this.instructions = const <String>[],
    this.worldBookIds = const <String>[],
    this.mcpServerIds = const <String>[],
    this.toolIds = const <String>[],
    this.memoryReadCategories = const <String>[],
    this.memoryWriteCategories = const <String>[],
    this.ttsPolicy = StorySkillTtsPolicy.inherit,
    this.activationModes = const <StorySkillActivationMode>{
      StorySkillActivationMode.manual,
    },
    this.activationSceneTags = const <String>{},
    this.activationConditionIds = const <String>{},
    this.permissions = const <StorySkillPermission>{},
    this.hooks = const <StorySkillHook>[],
    this.compatibility = const StorySkillCompatibility(),
    this.assets = const <String>[],
    this.templates = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String name;
  final String version;
  final String description;

  /// Stable instruction blocks loaded from SKILL.md/prompts. These are resolved
  /// at an explicit capability epoch, not appended ad-hoc every turn.
  final List<String> instructions;

  final List<String> worldBookIds;
  final List<String> mcpServerIds;
  final List<String> toolIds;
  final List<String> memoryReadCategories;
  final List<String> memoryWriteCategories;
  final StorySkillTtsPolicy ttsPolicy;
  final Set<StorySkillActivationMode> activationModes;
  final Set<String> activationSceneTags;
  final Set<String> activationConditionIds;
  final Set<StorySkillPermission> permissions;
  final List<StorySkillHook> hooks;
  final StorySkillCompatibility compatibility;
  final List<String> assets;
  final List<String> templates;
  final Map<String, Object?> metadata;
}

/// Per-assistant user control. Binding does not itself activate a Skill.
final class StorySkillBinding {
  const StorySkillBinding({
    required this.assistantId,
    required this.skillId,
    this.enabled = true,
    this.allowAutomaticActivation = true,
  });

  final String assistantId;
  final String skillId;
  final bool enabled;
  final bool allowAutomaticActivation;
}

final class StorySkillActivationContext {
  const StorySkillActivationContext({
    required this.assistantId,
    this.sceneTags = const <String>{},
    this.conditionIds = const <String>{},
    this.directorRequestedSkillIds = const <String>{},
    this.serialDueSkillIds = const <String>{},
    this.manualEnabledSkillIds = const <String>{},
  });

  final String assistantId;
  final Set<String> sceneTags;
  final Set<String> conditionIds;
  final Set<String> directorRequestedSkillIds;
  final Set<String> serialDueSkillIds;
  final Set<String> manualEnabledSkillIds;
}

final class StoryResolvedSkillCapabilities {
  const StoryResolvedSkillCapabilities({
    required this.activeSkills,
    required this.instructions,
    required this.worldBookIds,
    required this.mcpServerIds,
    required this.toolIds,
    required this.memoryReadCategories,
    required this.memoryWriteCategories,
    required this.permissions,
    required this.ttsPolicy,
  });

  final List<StorySkillManifest> activeSkills;
  final List<String> instructions;
  final List<String> worldBookIds;
  final List<String> mcpServerIds;
  final List<String> toolIds;
  final List<String> memoryReadCategories;
  final List<String> memoryWriteCategories;
  final Set<StorySkillPermission> permissions;
  final StorySkillTtsPolicy ttsPolicy;
}
