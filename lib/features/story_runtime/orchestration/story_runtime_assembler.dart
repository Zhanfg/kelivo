import '../cache/story_capability_epoch.dart';
import '../cache/story_prompt_cache_plan.dart';
import '../cache/story_prompt_compiler.dart';
import '../parsing/story_response_contract.dart';
import '../reference/story_reference_models.dart';
import '../reference/story_reference_profile_compiler.dart';
import '../reference/story_reference_selection_store.dart';
import '../reference/story_reference_store.dart';
import '../skills/story_skill_binding_store.dart';
import '../skills/story_skill_models.dart';
import '../skills/story_skill_resolver.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';

typedef StorySkillManifestLoader = Future<List<StorySkillManifest>> Function();

typedef StoryHostCapabilityResolver =
    Future<StoryHostCapabilityResolution> Function(
      StoryResolvedSkillCapabilities skills,
      StoryRuntimeSessionState session,
    );

/// Result from the Kelivo host after it resolves Skill requests through the
/// existing WorldBook/MCP/tool systems. These ids describe what will actually
/// be visible to the model, not merely what a Skill requested.
final class StoryHostCapabilityResolution {
  const StoryHostCapabilityResolution({
    this.toolIds = const <String>[],
    this.mcpProfileId,
    this.worldBookSnapshotId,
    this.toolSchemaFingerprint,
    this.summary = '',
  });

  final List<String> toolIds;
  final String? mcpProfileId;
  final String? worldBookSnapshotId;
  final String? toolSchemaFingerprint;
  final String summary;
}

final class StoryRuntimeAssemblyRequest {
  const StoryRuntimeAssemblyRequest({
    required this.conversationId,
    required this.assistantId,
    required this.storyCoreInstructions,
    this.sceneBaseline = '',
    this.sceneTags = const <String>{},
    this.conditionIds = const <String>{},
    this.directorRequestedSkillIds = const <String>{},
    this.serialDueSkillIds = const <String>{},
    this.manualEnabledSkillIds = const <String>{},
    this.turnScopedReferences = const <StoryReferenceInvocation>[],
    this.additionalStable = const <StoryPromptContribution>[],
    this.appendOnly = const <StoryPromptContribution>[],
    this.volatile = const <StoryPromptContribution>[],
    this.localOnly = const <StoryPromptContribution>[],
  });

  final String conversationId;
  final String assistantId;
  final String storyCoreInstructions;
  final String sceneBaseline;
  final Set<String> sceneTags;
  final Set<String> conditionIds;
  final Set<String> directorRequestedSkillIds;
  final Set<String> serialDueSkillIds;
  final Set<String> manualEnabledSkillIds;

  /// Ephemeral invocation overrides for this single request. They are never
  /// written back to the persistent Reference selection store.
  final List<StoryReferenceInvocation> turnScopedReferences;

  final List<StoryPromptContribution> additionalStable;
  final List<StoryPromptContribution> appendOnly;
  final List<StoryPromptContribution> volatile;
  final List<StoryPromptContribution> localOnly;
}

final class StoryRuntimeAssembly {
  const StoryRuntimeAssembly({
    required this.session,
    required this.skills,
    required this.references,
    required this.hostCapabilities,
    required this.prompt,
  });

  final StoryRuntimeSessionState session;
  final StoryResolvedSkillCapabilities skills;
  final List<StoryCompiledReferenceProfile> references;
  final StoryHostCapabilityResolution hostCapabilities;
  final StoryPromptCompilation prompt;
}

/// Single runtime assembly boundary for Story Mode.
///
/// Normal Chat Mode never calls this. When Story Mode is enabled, this resolves
/// persistent state and produces one immutable prompt/capability snapshot for
/// the request. Low-frequency Skill capabilities remain absent unless their
/// activation rule fired for this turn.
final class StoryRuntimeAssembler {
  const StoryRuntimeAssembler({
    required this.sessionRepository,
    required this.skillBindingRepository,
    required this.loadSkillManifests,
    required this.referenceProfileRepository,
    required this.referenceSelectionRepository,
    required this.resolveHostCapabilities,
    this.skillResolver = const StorySkillResolver(),
    this.referenceCompiler = const StoryReferenceProfileCompiler(),
    this.promptCompiler = const StoryPromptCompiler(),
  });

  final StoryRuntimeSessionRepository sessionRepository;
  final StorySkillBindingRepository skillBindingRepository;
  final StorySkillManifestLoader loadSkillManifests;
  final StoryReferenceProfileRepository referenceProfileRepository;
  final StoryReferenceSelectionRepository referenceSelectionRepository;
  final StoryHostCapabilityResolver resolveHostCapabilities;
  final StorySkillResolver skillResolver;
  final StoryReferenceProfileCompiler referenceCompiler;
  final StoryPromptCompiler promptCompiler;

  /// Returns null when the conversation has not opted into Story Mode.
  Future<StoryRuntimeAssembly?> assemble(
    StoryRuntimeAssemblyRequest request,
  ) async {
    final conversationId = _required(request.conversationId, 'conversationId');
    final assistantId = _required(request.assistantId, 'assistantId');
    final session = await sessionRepository.readOrDefault(conversationId);
    if (!session.enabled) return null;

    final manifestsFuture = loadSkillManifests();
    final bindingsFuture = skillBindingRepository.readForAssistant(assistantId);
    final profilesFuture = referenceProfileRepository.readAll();
    final selectionFuture = referenceSelectionRepository.readForConversation(
      conversationId,
    );

    final manifests = await manifestsFuture;
    final bindings = await bindingsFuture;
    final skills = skillResolver.resolve(
      manifests: manifests,
      bindings: bindings,
      context: StorySkillActivationContext(
        assistantId: assistantId,
        sceneTags: request.sceneTags,
        conditionIds: request.conditionIds,
        directorRequestedSkillIds: request.directorRequestedSkillIds,
        serialDueSkillIds: request.serialDueSkillIds,
        manualEnabledSkillIds: request.manualEnabledSkillIds,
      ),
    );

    final profiles = await profilesFuture;
    final selection = await selectionFuture;
    final referenceInvocations = _mergeReferenceInvocations(
      selection.invocations,
      request.turnScopedReferences,
    );
    final references = referenceCompiler.compile(
      profiles: profiles,
      invocations: referenceInvocations,
    );

    final hostCapabilities = await resolveHostCapabilities(skills, session);
    final epochStableReferenceFingerprints = <String>[
      for (final reference in references)
        if (reference.contribution.stability ==
            StoryPromptStability.epochStable)
          reference.fingerprint,
    ];
    final worldlineId = session.worldlineId ?? 'story.default.worldline';
    final sceneEpochId = session.sceneEpochId ?? 'story.bootstrap.scene';
    final capabilityEpoch = StoryCapabilityEpoch.canonical(
      epochId: '$sceneEpochId:r${session.sceneRevision}',
      worldlineId: worldlineId,
      sceneEpochId: sceneEpochId,
      activeSkillIds: [
        for (final skill in skills.activeSkills) '${skill.id}@${skill.version}',
      ],
      referenceProfileFingerprints: epochStableReferenceFingerprints,
      toolIds: hostCapabilities.toolIds,
      mcpProfileId: hostCapabilities.mcpProfileId,
      worldBookSnapshotId: hostCapabilities.worldBookSnapshotId,
      toolSchemaFingerprint: hostCapabilities.toolSchemaFingerprint,
    );

    final skillContribution = skills.toPromptContribution();
    final prompt = promptCompiler.compile(
      capabilityEpoch: capabilityEpoch,
      storyCoreInstructions: request.storyCoreInstructions,
      sceneBaseline: request.sceneBaseline,
      capabilitySummary: hostCapabilities.summary,
      skillContributions: [if (skillContribution != null) skillContribution],
      referenceProfiles: references,
      additionalStable: <StoryPromptContribution>[
        storyResponseContractContributionV1,
        ...request.additionalStable,
      ],
      appendOnly: request.appendOnly,
      volatile: request.volatile,
      localOnly: request.localOnly,
    );

    return StoryRuntimeAssembly(
      session: session,
      skills: skills,
      references: references,
      hostCapabilities: hostCapabilities,
      prompt: prompt,
    );
  }
}

List<StoryReferenceInvocation> _mergeReferenceInvocations(
  Iterable<StoryReferenceInvocation> persistent,
  Iterable<StoryReferenceInvocation> turnScoped,
) {
  final byId = <String, StoryReferenceInvocation>{};
  for (final invocation in persistent) {
    if (invocation.turnScoped) {
      throw StateError('persistent_reference_marked_turn_scoped');
    }
    byId[invocation.profileId] = invocation;
  }
  for (final invocation in turnScoped) {
    if (!invocation.turnScoped) {
      throw ArgumentError.value(
        invocation.profileId,
        'turnScopedReferences',
        'ephemeral override must set turnScoped=true',
      );
    }
    byId[invocation.profileId] = invocation;
  }
  final result = byId.values.toList(growable: false)
    ..sort((a, b) => a.profileId.compareTo(b.profileId));
  return result;
}

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, field);
  return normalized;
}
