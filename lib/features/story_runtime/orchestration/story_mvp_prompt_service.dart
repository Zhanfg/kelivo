import '../../../core/database/business_preferences.dart';
import '../reference/story_reference_profile_compiler.dart';
import '../reference/story_reference_selection_store.dart';
import '../reference/story_reference_store.dart';
import '../skills/story_skill_activation_policy.dart';
import '../skills/story_skill_binding_store.dart';
import '../skills/story_skill_library.dart';
import '../skills/story_skill_models.dart';
import '../skills/story_skill_package_store.dart';
import '../skills/story_skill_resolver.dart';
import '../state/story_runtime_store.dart';

/// Release-MVP Story prompt bridge.
///
/// The dedicated structured Story timeline renderer is intentionally deferred
/// from the first publishable build. Until it lands, Story Mode must emit plain,
/// directly readable chat prose instead of exposing STORY_OUTPUT JSON to users.
final class StoryMvpPromptService {
  StoryMvpPromptService(BusinessPreferences preferences)
    : _sessionStore = StoryRuntimeStore(preferences),
      _skillBindingStore = StorySkillBindingStore(preferences),
      _skillLibrary = StorySkillLibrary(
        repository: StorySkillPackageStore(preferences),
      ),
      _referenceProfileStore = StoryReferenceProfileStore(preferences),
      _referenceSelectionStore = StoryReferenceSelectionStore(preferences);

  final StoryRuntimeStore _sessionStore;
  final StorySkillBindingStore _skillBindingStore;
  final StorySkillLibrary _skillLibrary;
  final StoryReferenceProfileStore _referenceProfileStore;
  final StoryReferenceSelectionStore _referenceSelectionStore;

  static const StorySkillResolver _skillResolver = StorySkillResolver();
  static const StoryReferenceProfileCompiler _referenceCompiler =
      StoryReferenceProfileCompiler();

  Future<String?> build({
    required String conversationId,
    required String assistantId,
  }) async {
    final cid = conversationId.trim();
    final aid = assistantId.trim();
    if (cid.isEmpty || aid.isEmpty) return null;

    final session = await _sessionStore.readOrDefault(cid);
    if (!session.enabled) return null;

    final manifestsFuture = _skillLibrary.loadAll();
    final bindingsFuture = _skillBindingStore.readForAssistant(aid);
    final profilesFuture = _referenceProfileStore.readAll();
    final selectionFuture = _referenceSelectionStore.readForConversation(cid);

    final manifests = await manifestsFuture;
    final bindings = await bindingsFuture;
    final effectiveBindings = StorySkillActivationPolicy.effectiveBindings(
      manifests: manifests,
      bindings: bindings,
      assistantId: aid,
    );
    final enabledBindingIds = <String>{
      for (final binding in effectiveBindings)
        if (binding.enabled) binding.skillId,
    };
    final skills = _skillResolver.resolve(
      manifests: manifests,
      bindings: effectiveBindings,
      context: StorySkillActivationContext(
        assistantId: aid,
        manualEnabledSkillIds: enabledBindingIds,
      ),
    );

    final profiles = await profilesFuture;
    final selection = await selectionFuture;
    final references = _referenceCompiler.compile(
      profiles: profiles,
      invocations: selection.invocations,
    );

    final buffer = StringBuffer();
    buffer.writeln('[KELIVO_STORY_MVP_V1]');
    buffer.writeln(
      'This conversation is in Story Mode. Write polished original fiction that is directly readable in the normal chat UI.',
    );
    buffer.writeln(
      'For this MVP, output only the story prose and any concise in-world choices that are genuinely useful. Do not output JSON, XML, schema objects, STORY_OUTPUT envelopes, implementation notes, or analysis.',
    );
    buffer.writeln(
      'SELF is always the real user. Address SELF in second person when narration refers to them. Never rename SELF into an NPC or silently transfer control of SELF to another character.',
    );
    buffer.writeln(_agencyInstruction(session.agencyMode.name));
    buffer.writeln(
      'Preserve continuity with the visible conversation, established world facts, character identities, injuries, inventory, relationships, location, time, and unresolved consequences. Do not reset the scene unless the user asks.',
    );
    buffer.writeln(
      'Reference profiles below are craft guidance only. Produce new prose; never copy source passages, source-specific names, plot events, or distinctive phrases.',
    );

    if (skills.instructions.isNotEmpty) {
      buffer.writeln('[ACTIVE_STORY_SKILLS]');
      for (final instruction in skills.instructions) {
        final text = instruction.trim();
        if (text.isNotEmpty) buffer.writeln(text);
      }
      buffer.writeln('[/ACTIVE_STORY_SKILLS]');
    }

    for (final reference in references) {
      final text = reference.contribution.content.trim();
      if (text.isNotEmpty) buffer.writeln(text);
    }

    buffer.write('[/KELIVO_STORY_MVP_V1]');
    return buffer.toString();
  }
}

String _agencyInstruction(String mode) => switch (mode) {
  'manual' =>
    'Agency mode: manual. Never invent SELF actions, dialogue, decisions, or internal conclusions. Advance NPCs and the environment, then leave consequential SELF choices to the user.',
  'cinematic' =>
    'Agency mode: cinematic. You may infer small low-impact connective motions for flow, but never choose major goals, consent, commitments, irreversible actions, or consequential dialogue for SELF.',
  _ =>
    'Agency mode: balanced. You may infer trivial connective behavior when strongly implied, but pause before meaningful choices, commitments, consent, irreversible actions, or high-impact SELF dialogue.',
};