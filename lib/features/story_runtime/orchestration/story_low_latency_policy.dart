import '../skills/story_skill_models.dart';

/// Request-level gate for Story's normal low-latency (R0) path.
///
/// Story continuity is already supplied by the stable Story prompt, Scene
/// Runtime and worldline memory. Native subsystems that can add latency or
/// destabilize the prompt shape stay off unless an active Skill explicitly
/// requests the corresponding capability.
final class StoryLowLatencyPolicy {
  const StoryLowLatencyPolicy({
    required this.allowNativeMemory,
    required this.allowNativeSearch,
    required this.allowNativeWorldBook,
    required this.allowNativeInstructionInjection,
    required this.requestedWorldBookIds,
  });

  const StoryLowLatencyPolicy.chatCompatibility()
    : allowNativeMemory = true,
      allowNativeSearch = true,
      allowNativeWorldBook = true,
      allowNativeInstructionInjection = true,
      requestedWorldBookIds = const <String>{};

  final bool allowNativeMemory;
  final bool allowNativeSearch;
  final bool allowNativeWorldBook;
  final bool allowNativeInstructionInjection;

  /// In Story mode this is an allow-list, not merely a hint. An empty set with
  /// [allowNativeWorldBook] false means no normal WorldBook scan for the turn.
  final Set<String> requestedWorldBookIds;

  factory StoryLowLatencyPolicy.fromSkills(
    StoryResolvedSkillCapabilities skills,
  ) {
    final permissions = skills.permissions;
    final toolIds = skills.toolIds.map((id) => id.toLowerCase()).toSet();
    final asksNetwork = permissions.contains(StorySkillPermission.network);
    final asksSearchTool = toolIds.any(
      (id) =>
          id.contains('search') ||
          id.contains('browse') ||
          id.contains('web') ||
          id.contains('research'),
    );
    final asksMemory =
        permissions.contains(StorySkillPermission.memoryRead) ||
        permissions.contains(StorySkillPermission.memoryWrite) ||
        skills.memoryReadCategories.isNotEmpty ||
        skills.memoryWriteCategories.isNotEmpty;
    final worldBooks = skills.worldBookIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    return StoryLowLatencyPolicy(
      allowNativeMemory: asksMemory,
      allowNativeSearch: asksNetwork || asksSearchTool,
      allowNativeWorldBook: worldBooks.isNotEmpty,
      // Story Skill instructions are already compiled into the stable Story
      // capability epoch. Generic Assistant instruction injections would be a
      // second uncontrolled prompt surface, so R0 keeps them out.
      allowNativeInstructionInjection: false,
      requestedWorldBookIds: Set.unmodifiable(worldBooks),
    );
  }
}
