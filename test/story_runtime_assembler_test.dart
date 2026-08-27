import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/orchestration/story_runtime_assembler.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_models.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_selection_store.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_store.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_binding_store.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_models.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_state.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_store.dart';

void main() {
  group('StoryRuntimeAssembler', () {
    test('Story-disabled conversation does not resolve capabilities or references', () async {
      var hostCalls = 0;
      var skillLoads = 0;
      final assembler = StoryRuntimeAssembler(
        sessionRepository: _SessionRepo(
          const StoryRuntimeSessionState(conversationId: 'conv-1'),
        ),
        skillBindingRepository: const _BindingRepo([]),
        loadSkillManifests: () async {
          skillLoads++;
          return const <StorySkillManifest>[];
        },
        referenceProfileRepository: const _ProfileRepo([]),
        referenceSelectionRepository: const _SelectionRepo([]),
        resolveHostCapabilities: (skills, session) async {
          hostCalls++;
          return const StoryHostCapabilityResolution();
        },
      );

      final result = await assembler.assemble(
        const StoryRuntimeAssemblyRequest(
          conversationId: 'conv-1',
          assistantId: 'assistant-1',
          storyCoreInstructions: 'Story core.',
        ),
      );

      expect(result, isNull);
      expect(hostCalls, 0);
      expect(skillLoads, 0);
    });

    test('ordinary Story turn omits serial Skill until SERIAL_DUE fires', () async {
      const baseSkill = StorySkillManifest(
        id: 'story.base',
        name: 'Base',
        version: '1',
        instructions: ['Base story behavior.'],
        activationModes: {StorySkillActivationMode.always},
      );
      const serialSkill = StorySkillManifest(
        id: 'story.github_serial',
        name: 'Serial',
        version: '1',
        mcpServerIds: ['mcp.github'],
        toolIds: ['tool.repo_status'],
        permissions: {StorySkillPermission.mcp},
        activationModes: {StorySkillActivationMode.serialDue},
      );
      const bindings = [
        StorySkillBinding(assistantId: 'assistant-1', skillId: 'story.base'),
        StorySkillBinding(
          assistantId: 'assistant-1',
          skillId: 'story.github_serial',
        ),
      ];
      final seenSkillIds = <List<String>>[];
      final assembler = StoryRuntimeAssembler(
        sessionRepository: _SessionRepo(
          const StoryRuntimeSessionState(
            conversationId: 'conv-1',
            enabled: true,
            worldlineId: 'wl-main',
            sceneEpochId: 'scene-1',
          ),
        ),
        skillBindingRepository: const _BindingRepo(bindings),
        loadSkillManifests: () async => const [serialSkill, baseSkill],
        referenceProfileRepository: const _ProfileRepo([]),
        referenceSelectionRepository: const _SelectionRepo([]),
        resolveHostCapabilities: (skills, session) async {
          seenSkillIds.add([for (final skill in skills.activeSkills) skill.id]);
          return StoryHostCapabilityResolution(
            mcpProfileId: skills.mcpServerIds.isEmpty ? null : 'profile.github',
            toolIds: skills.toolIds,
          );
        },
      );

      final ordinary = await assembler.assemble(
        const StoryRuntimeAssemblyRequest(
          conversationId: 'conv-1',
          assistantId: 'assistant-1',
          storyCoreInstructions: 'Story core.',
        ),
      );
      final due = await assembler.assemble(
        const StoryRuntimeAssemblyRequest(
          conversationId: 'conv-1',
          assistantId: 'assistant-1',
          storyCoreInstructions: 'Story core.',
          serialDueSkillIds: {'story.github_serial'},
        ),
      );

      expect(seenSkillIds[0], ['story.base']);
      expect(ordinary!.hostCapabilities.mcpProfileId, isNull);
      expect(ordinary.prompt.capabilityEpoch.toolIds, isEmpty);
      expect(seenSkillIds[1], ['story.base', 'story.github_serial']);
      expect(due!.hostCapabilities.mcpProfileId, 'profile.github');
      expect(due.prompt.capabilityEpoch.toolIds, ['tool.repo_status']);
    });

    test('persistent Reference is epoch-stable and turn override is volatile', () async {
      const profile = StoryReferenceStyleProfile(
        id: 'style-1',
        documentId: 'doc-1',
        name: 'Style',
        sourceContentHash: 'source-hash',
        createdAtMs: 1,
        aspects: {
          StoryReferenceAspect.dialogue,
          StoryReferenceAspect.description,
        },
        dialogueMethods: ['Use compact dialogue with subtext.'],
        descriptionMethods: ['Anchor space before sensory detail.'],
      );
      final assembler = StoryRuntimeAssembler(
        sessionRepository: _SessionRepo(
          const StoryRuntimeSessionState(
            conversationId: 'conv-1',
            enabled: true,
          ),
        ),
        skillBindingRepository: const _BindingRepo([]),
        loadSkillManifests: () async => const [],
        referenceProfileRepository: const _ProfileRepo([profile]),
        referenceSelectionRepository: const _SelectionRepo([
          StoryReferenceInvocation(
            profileId: 'style-1',
            strength: 0.5,
            enabledAspects: {StoryReferenceAspect.dialogue},
          ),
        ]),
        resolveHostCapabilities: (skills, session) async =>
            const StoryHostCapabilityResolution(),
      );

      final persistent = await assembler.assemble(
        const StoryRuntimeAssemblyRequest(
          conversationId: 'conv-1',
          assistantId: 'assistant-1',
          storyCoreInstructions: 'Story core.',
        ),
      );
      final turnOverride = await assembler.assemble(
        const StoryRuntimeAssemblyRequest(
          conversationId: 'conv-1',
          assistantId: 'assistant-1',
          storyCoreInstructions: 'Story core.',
          turnScopedReferences: [
            StoryReferenceInvocation(
              profileId: 'style-1',
              strength: 0.9,
              enabledAspects: {StoryReferenceAspect.description},
              turnScoped: true,
            ),
          ],
        ),
      );

      expect(
        persistent!.references.single.contribution.stability.name,
        'epochStable',
      );
      expect(
        persistent.prompt.capabilityEpoch.referenceProfileFingerprints,
        hasLength(1),
      );
      expect(turnOverride!.references.single.contribution.stability.name, 'volatile');
      expect(
        turnOverride.prompt.capabilityEpoch.referenceProfileFingerprints,
        isEmpty,
      );
      expect(
        persistent.prompt.stablePrefixFingerprint,
        isNot(turnOverride.prompt.stablePrefixFingerprint),
      );
    });
  });
}

final class _SessionRepo implements StoryRuntimeSessionRepository {
  _SessionRepo(this.state);
  StoryRuntimeSessionState state;

  @override
  Future<StoryRuntimeSessionState?> readForConversation(String conversationId) async =>
      state.conversationId == conversationId ? state : null;

  @override
  Future<StoryRuntimeSessionState> readOrDefault(String conversationId) async =>
      state.conversationId == conversationId
          ? state
          : StoryRuntimeSessionState(conversationId: conversationId);

  @override
  Future<void> upsert(StoryRuntimeSessionState state) async => this.state = state;

  @override
  Future<void> setEnabled(String conversationId, bool enabled) async {
    if (state.conversationId == conversationId) {
      state = state.copyWith(enabled: enabled);
    }
  }

  @override
  Future<void> removeForConversation(String conversationId) async {}
}

final class _BindingRepo implements StorySkillBindingRepository {
  const _BindingRepo(this.bindings);
  final List<StorySkillBinding> bindings;

  @override
  Future<List<StorySkillBinding>> readForAssistant(String assistantId) async =>
      bindings.where((item) => item.assistantId == assistantId).toList();

  @override
  Future<void> upsert(StorySkillBinding binding) async =>
      throw UnsupportedError('test');

  @override
  Future<void> remove({required String assistantId, required String skillId}) async =>
      throw UnsupportedError('test');
}

final class _ProfileRepo implements StoryReferenceProfileRepository {
  const _ProfileRepo(this.profiles);
  final List<StoryReferenceStyleProfile> profiles;

  @override
  Future<List<StoryReferenceStyleProfile>> readAll() async => profiles;

  @override
  Future<StoryReferenceStyleProfile?> readById(String id) async {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  @override
  Future<List<StoryReferenceStyleProfile>> readForDocument(String documentId) async =>
      profiles.where((item) => item.documentId == documentId).toList();

  @override
  Future<void> upsert(StoryReferenceStyleProfile profile) async =>
      throw UnsupportedError('test');

  @override
  Future<void> remove(String id) async => throw UnsupportedError('test');
}

final class _SelectionRepo implements StoryReferenceSelectionRepository {
  const _SelectionRepo(this.invocations);
  final List<StoryReferenceInvocation> invocations;

  @override
  Future<StoryReferenceSelection> readForConversation(String conversationId) async =>
      StoryReferenceSelection(
        conversationId: conversationId,
        invocations: invocations,
      );

  @override
  Future<void> writeForConversation(
    String conversationId,
    Iterable<StoryReferenceInvocation> invocations,
  ) async => throw UnsupportedError('test');
}
