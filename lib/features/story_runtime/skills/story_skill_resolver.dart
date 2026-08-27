import '../cache/story_capability_epoch.dart';
import '../cache/story_prompt_cache_plan.dart';
import 'story_skill_models.dart';

/// Resolves assistant-bound Skills into one deterministic capability snapshot.
///
/// This resolver never grants permissions. It only computes what the Skill
/// requests; the existing Kelivo MCP/tool approval and permission layers remain
/// authoritative at execution time.
final class StorySkillResolver {
  const StorySkillResolver();

  StoryResolvedSkillCapabilities resolve({
    required Iterable<StorySkillManifest> manifests,
    required Iterable<StorySkillBinding> bindings,
    required StorySkillActivationContext context,
  }) {
    final manifestById = <String, StorySkillManifest>{
      for (final manifest in manifests) manifest.id: manifest,
    };
    final active = <StorySkillManifest>[];

    for (final binding in bindings) {
      if (binding.assistantId != context.assistantId || !binding.enabled) {
        continue;
      }
      final manifest = manifestById[binding.skillId];
      if (manifest == null) continue;
      if (_isActive(manifest, binding, context)) active.add(manifest);
    }

    active.sort((a, b) => a.id.compareTo(b.id));

    final instructions = <String>[];
    final worldBooks = <String>{};
    final mcpServers = <String>{};
    final tools = <String>{};
    final memoryReads = <String>{};
    final memoryWrites = <String>{};
    final permissions = <StorySkillPermission>{};
    var ttsPolicy = StorySkillTtsPolicy.inherit;

    for (final skill in active) {
      instructions.addAll(
        skill.instructions
            .map((text) => text.trim())
            .where((text) => text.isNotEmpty),
      );
      worldBooks.addAll(skill.worldBookIds);
      mcpServers.addAll(skill.mcpServerIds);
      tools.addAll(skill.toolIds);
      memoryReads.addAll(skill.memoryReadCategories);
      memoryWrites.addAll(skill.memoryWriteCategories);
      permissions.addAll(skill.permissions);
      if (skill.ttsPolicy == StorySkillTtsPolicy.disabled) {
        ttsPolicy = StorySkillTtsPolicy.disabled;
      } else if (skill.ttsPolicy == StorySkillTtsPolicy.preferEnabled &&
          ttsPolicy == StorySkillTtsPolicy.inherit) {
        ttsPolicy = StorySkillTtsPolicy.preferEnabled;
      }
    }

    List<String> sorted(Set<String> values) =>
        (values.toList(growable: false)..sort());

    return StoryResolvedSkillCapabilities(
      activeSkills: List.unmodifiable(active),
      instructions: List.unmodifiable(instructions),
      worldBookIds: List.unmodifiable(sorted(worldBooks)),
      mcpServerIds: List.unmodifiable(sorted(mcpServers)),
      toolIds: List.unmodifiable(sorted(tools)),
      memoryReadCategories: List.unmodifiable(sorted(memoryReads)),
      memoryWriteCategories: List.unmodifiable(sorted(memoryWrites)),
      permissions: Set.unmodifiable(permissions),
      ttsPolicy: ttsPolicy,
    );
  }

  bool _isActive(
    StorySkillManifest manifest,
    StorySkillBinding binding,
    StorySkillActivationContext context,
  ) {
    final modes = manifest.activationModes;

    if (modes.contains(StorySkillActivationMode.manual) &&
        context.manualEnabledSkillIds.contains(manifest.id)) {
      return true;
    }

    if (!binding.allowAutomaticActivation) return false;
    if (modes.contains(StorySkillActivationMode.always)) return true;

    if (modes.contains(StorySkillActivationMode.sceneTag) &&
        manifest.activationSceneTags.any(context.sceneTags.contains)) {
      return true;
    }
    if (modes.contains(StorySkillActivationMode.condition) &&
        manifest.activationConditionIds.any(context.conditionIds.contains)) {
      return true;
    }
    if (modes.contains(StorySkillActivationMode.director) &&
        context.directorRequestedSkillIds.contains(manifest.id)) {
      return true;
    }
    if (modes.contains(StorySkillActivationMode.serialDue) &&
        context.serialDueSkillIds.contains(manifest.id)) {
      return true;
    }
    return false;
  }
}

extension StoryResolvedSkillPromptProjection on StoryResolvedSkillCapabilities {
  /// Stable prompt contribution for an already-resolved capability epoch.
  StoryPromptContribution? toPromptContribution() {
    if (instructions.isEmpty) return null;
    final buffer = StringBuffer('[ACTIVE_STORY_SKILLS]\n');
    for (var index = 0; index < instructions.length; index++) {
      buffer.writeln('${index + 1}. ${instructions[index]}');
    }
    buffer.write('[/ACTIVE_STORY_SKILLS]');
    return StoryPromptContribution(
      id: 'story.skills.active',
      stability: StoryPromptStability.epochStable,
      content: buffer.toString(),
      order: 300,
    );
  }

  /// Builds the epoch only after the host has resolved raw Skill requests into
  /// one MCP profile, one WorldBook snapshot and one canonical tool schema.
  StoryCapabilityEpoch toCapabilityEpoch({
    required String epochId,
    required String sceneEpochId,
    required String worldlineId,
    String? mcpProfileId,
    String? worldBookSnapshotId,
    String? toolSchemaFingerprint,
  }) {
    return StoryCapabilityEpoch.canonical(
      epochId: epochId,
      sceneEpochId: sceneEpochId,
      worldlineId: worldlineId,
      activeSkillIds: [
        for (final skill in activeSkills) '${skill.id}@${skill.version}',
      ],
      toolIds: toolIds,
      mcpProfileId: mcpProfileId,
      worldBookSnapshotId: worldBookSnapshotId,
      toolSchemaFingerprint: toolSchemaFingerprint,
    );
  }
}
