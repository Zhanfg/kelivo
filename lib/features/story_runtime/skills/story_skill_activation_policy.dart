import 'story_skill_models.dart';

/// Resolves user bindings against built-in/default Skill activation.
///
/// An explicit binding always wins, including `enabled: false`. This is
/// important for built-in Skills whose metadata declares `defaultEnabled=true`:
/// once the user disables one for an Assistant it must stay disabled rather
/// than being silently re-created on the next Story turn.
final class StorySkillActivationPolicy {
  const StorySkillActivationPolicy._();

  static bool isEnabled({
    required StorySkillManifest manifest,
    required Iterable<StorySkillBinding> bindings,
    required String assistantId,
  }) {
    for (final binding in bindings) {
      if (binding.assistantId == assistantId && binding.skillId == manifest.id) {
        return binding.enabled;
      }
    }
    return manifest.metadata['defaultEnabled'] == true;
  }

  static List<StorySkillBinding> effectiveBindings({
    required Iterable<StorySkillManifest> manifests,
    required Iterable<StorySkillBinding> bindings,
    required String assistantId,
  }) {
    final result = <StorySkillBinding>[
      for (final binding in bindings)
        if (binding.assistantId == assistantId) binding,
    ];
    final explicitIds = <String>{for (final binding in result) binding.skillId};
    for (final manifest in manifests) {
      if (manifest.metadata['defaultEnabled'] == true &&
          !explicitIds.contains(manifest.id)) {
        result.add(
          StorySkillBinding(
            assistantId: assistantId,
            skillId: manifest.id,
          ),
        );
      }
    }
    result.sort((a, b) => a.skillId.compareTo(b.skillId));
    return List.unmodifiable(result);
  }
}
