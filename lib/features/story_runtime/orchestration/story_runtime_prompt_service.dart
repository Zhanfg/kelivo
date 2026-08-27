import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/memory_entry.dart';
import '../../../core/services/memory/memory_repository.dart';
import '../cache/story_prompt_cache_plan.dart';
import '../mcp/story_mcp_profile.dart';
import '../mcp/story_mcp_profile_resolver.dart';
import '../mcp/story_mcp_profile_store.dart';
import '../memory/story_worldline_memory.dart';
import '../memory/story_worldline_memory_store.dart';
import '../reference/story_reference_selection_store.dart';
import '../reference/story_reference_store.dart';
import '../skills/story_skill_binding_store.dart';
import '../skills/story_skill_library.dart';
import '../skills/story_skill_package_store.dart';
import '../state/story_runtime_machine.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import '../state/story_scene_runtime_state.dart';
import '../world_tree/story_world_tree_coordinator.dart';
import '../world_tree/story_world_tree_models.dart';
import '../world_tree/story_world_tree_projection.dart';
import '../world_tree/story_world_tree_store.dart';
import 'story_runtime_assembler.dart';
import 'story_runtime_commit_service.dart';

final class StoryRuntimePromptResult {
  const StoryRuntimePromptResult({
    required this.providerText,
    required this.stablePrefixFingerprint,
    required this.stablePrefixRatio,
    required this.worldTreeId,
    required this.worldlineId,
    required this.currentNodeId,
    required this.runtimeStateVersion,
    required this.memoryVersion,
    required this.visibleStoryMemoryCount,
    required this.activeSkillIds,
    required this.mcpProfileId,
    required this.allowedMcpToolNames,
    required this.allowedMcpServerIds,
    required this.includeAssistantMcpDefaults,
    required this.requireMcpApproval,
    this.sceneId,
    this.sceneRevision = 0,
  });

  final String providerText;
  final String stablePrefixFingerprint;
  final double stablePrefixRatio;
  final String worldTreeId;
  final String worldlineId;
  final String? currentNodeId;
  final int runtimeStateVersion;
  final int memoryVersion;
  final int visibleStoryMemoryCount;
  final Set<String> activeSkillIds;
  final String? mcpProfileId;
  final Set<String> allowedMcpToolNames;
  final Set<String> allowedMcpServerIds;
  final bool includeAssistantMcpDefaults;
  final bool requireMcpApproval;
  final String? sceneId;
  final int sceneRevision;
}

/// Production Story prompt bridge used by the normal Kelivo send path.
///
/// The bridge is opt-in per conversation. It projects Kelivo's native message
/// revisions into World Tree metadata, resolves worldline-aware memory as a
/// sidecar over the native MemoryEntry store, and delegates final prompt
/// ordering/cache stability to StoryRuntimeAssembler -> StoryPromptCompiler.
final class StoryRuntimePromptService {
  StoryRuntimePromptService(BusinessPreferences preferences)
    : _sessionStore = StoryRuntimeStore(preferences),
      _sceneStore = StorySceneRuntimeStore(preferences),
      _worldTreeStore = StoryWorldTreeStore(preferences),
      _worldlineMemoryStore = StoryWorldlineMemoryStore(preferences),
      _executionStore = StoryRuntimeExecutionStore(preferences),
      _memoryRepository = MemoryRepository(preferences),
      _skillBindingStore = StorySkillBindingStore(preferences),
      _skillLibrary = StorySkillLibrary(
        repository: StorySkillPackageStore(preferences),
      ),
      _referenceProfileStore = StoryReferenceProfileStore(preferences),
      _referenceSelectionStore = StoryReferenceSelectionStore(preferences),
      _mcpProfileStore = StoryMcpProfileStore(preferences),
      _mcpSelectionStore = StoryMcpProfileSelectionStore(preferences),
      _commitService = StoryRuntimeCommitService(preferences);

  final StoryRuntimeStore _sessionStore;
  final StorySceneRuntimeStore _sceneStore;
  final StoryWorldTreeStore _worldTreeStore;
  final StoryWorldlineMemoryStore _worldlineMemoryStore;
  final StoryRuntimeExecutionStore _executionStore;
  final MemoryRepository _memoryRepository;
  final StorySkillBindingStore _skillBindingStore;
  final StorySkillLibrary _skillLibrary;
  final StoryReferenceProfileStore _referenceProfileStore;
  final StoryReferenceSelectionStore _referenceSelectionStore;
  final StoryMcpProfileStore _mcpProfileStore;
  final StoryMcpProfileSelectionStore _mcpSelectionStore;
  final StoryRuntimeCommitService _commitService;

  static const StoryWorldlineMemoryResolver _memoryResolver =
      StoryWorldlineMemoryResolver();
  static const StoryMcpProfileResolver _mcpResolver = StoryMcpProfileResolver();

  Future<StoryRuntimePromptResult?> build({
    required Conversation conversation,
    required List<ChatMessage> messages,
    required String assistantId,
  }) async {
    var session = await _sessionStore.readOrDefault(conversation.id);
    if (!session.enabled) return null;

    // Close the previous native Kelivo assistant turn before this request starts
    // a new Story transaction. The commit service matches the exact persisted
    // placeholder id recorded by the execution state, so this is deterministic
    // and recovery-safe rather than a "last assistant message" heuristic.
    await _commitService.commitPendingFinalizedTurn(messages);
    session = await _sessionStore.readOrDefault(conversation.id);

    final machine = StoryRuntimeStateMachine(_executionStore);
    try {
      await _beginAssembly(machine, conversation.id);
      final projection = StoryWorldTreeProjection.fromKelivoTimeline(
        conversation: conversation,
        messages: messages,
      );
      var tree = await _worldTreeStore.readForConversation(conversation.id);
      final coordinator = StoryWorldTreeCoordinator(repository: _worldTreeStore);
      tree ??= await coordinator.bootstrap(
        conversationId: conversation.id,
        name: conversation.title,
        rootContentHash: _rootContentHash(projection, messages),
        currentNodeId: projection.currentNode?.nodeId,
        currentMessageId: projection.currentNode?.messageId,
      );
      final worldline = tree.worldlineForConversation(conversation.id);
      if (worldline == null) {
        throw StateError('story_worldline_missing_for_conversation');
      }
      if (tree.currentNodeId != projection.currentNode?.nodeId ||
          tree.currentMessageId != projection.currentNode?.messageId ||
          tree.headWorldlineId != worldline.id) {
        tree = await coordinator.syncSelection(
          worldTreeId: tree.worldTreeId,
          worldlineId: worldline.id,
          currentNodeId: projection.currentNode?.nodeId,
          currentMessageId: projection.currentNode?.messageId,
        );
      }

      var effectiveSession = session;
      if (session.worldlineId != worldline.id) {
        effectiveSession = session.copyWith(worldlineId: worldline.id);
        await _sessionStore.upsert(effectiveSession);
      }

      var scene = await _sceneStore.readOrDefault(conversation.id);
      if (scene.worldTreeId != tree.worldTreeId ||
          scene.worldlineId != worldline.id) {
        scene = scene.copyWith(
          worldTreeId: tree.worldTreeId,
          worldlineId: worldline.id,
          revision: scene.revision + 1,
        );
        await _sceneStore.upsert(scene);
      }

      final memoryLinks = await _worldlineMemoryStore.readForTree(
        tree.worldTreeId,
      );
      final baseMemories = (await _memoryRepository.readAll())
          .where(
            (entry) =>
                entry.status == MemoryStatus.active &&
                (entry.scope == MemoryScope.global ||
                    (entry.scope == MemoryScope.assistant &&
                        entry.assistantId == assistantId)),
          )
          .toList(growable: false);
      final resolvedMemory = _memoryResolver.resolve(
        tree: tree,
        currentWorldlineId: worldline.id,
        baseMemories: baseMemories,
        links: memoryLinks,
      );
      final storyScopedMemory = resolvedMemory
          .where((item) => item.sourceWorldlineId != null)
          .toList(growable: false);

      final mcpSelection = await _mcpSelectionStore.readForConversation(
        conversation.id,
      );
      final selectedMcpProfile = mcpSelection.profileId == null
          ? null
          : await _mcpProfileStore.readById(mcpSelection.profileId!);
      StoryMcpExposurePolicy? mcpExposure;

      final assembler = StoryRuntimeAssembler(
        sessionRepository: _sessionStore,
        skillBindingRepository: _skillBindingStore,
        loadSkillManifests: _skillLibrary.loadAll,
        referenceProfileRepository: _referenceProfileStore,
        referenceSelectionRepository: _referenceSelectionStore,
        resolveHostCapabilities: (skills, _) async {
          if (selectedMcpProfile == null) {
            return const StoryHostCapabilityResolution(
              summary:
                  'No Story MCP profile is selected; Kelivo Assistant tool exposure remains unchanged.',
            );
          }
          mcpExposure = _mcpResolver.resolve(
            profile: selectedMcpProfile,
            skills: skills,
          );
          final toolIds = mcpExposure!.allowedToolNames.toList()..sort();
          return StoryHostCapabilityResolution(
            toolIds: toolIds,
            mcpProfileId: mcpExposure!.profileId,
            summary:
                'Story MCP profile ${mcpExposure!.profileId} narrows model-visible native MCP routes; execution and approval remain in Kelivo.',
          );
        },
      );
      final assembly = await assembler.assemble(
        StoryRuntimeAssemblyRequest(
          conversationId: conversation.id,
          assistantId: assistantId,
          storyCoreInstructions: _storyCoreInstructions(effectiveSession),
          sceneBaseline: _sceneBaseline(scene),
          manualEnabledSkillIds: scene.activeSkillIds.toSet(),
          additionalStable: <StoryPromptContribution>[
            StoryPromptContribution(
              id: 'story.worldline.ancestry',
              stability: StoryPromptStability.epochStable,
              order: 300,
              content: _ancestryText(tree, worldline.id),
            ),
          ],
          volatile: <StoryPromptContribution>[
            StoryPromptContribution(
              id: 'story.worldline.cursor',
              stability: StoryPromptStability.volatile,
              order: 800,
              content: _cursorText(tree),
            ),
            if (storyScopedMemory.isNotEmpty)
              StoryPromptContribution(
                id: 'story.worldline.memory',
                stability: StoryPromptStability.volatile,
                order: 820,
                content: _memoryText(storyScopedMemory),
              ),
            if (scene.openLoops.isNotEmpty ||
                scene.continuityState.isNotEmpty ||
                scene.serialState.isNotEmpty)
              StoryPromptContribution(
                id: 'story.scene.dynamic',
                stability: StoryPromptStability.volatile,
                order: 840,
                content: _sceneDynamicText(scene),
              ),
          ],
          localOnly: <StoryPromptContribution>[
            StoryPromptContribution(
              id: 'story.runtime.local-diagnostics',
              stability: StoryPromptStability.localOnly,
              order: 1000,
              content:
                  'worldTree=${tree.worldTreeId};memoryVersion=${tree.memoryVersion};runtimeStateVersion=${tree.runtimeStateVersion};sceneRevision=${scene.revision}',
            ),
          ],
        ),
      );
      if (assembly == null) return null;

      final resolvedSkillIds = <String>{
        for (final skill in assembly.skills.activeSkills) skill.id,
      };
      if (!_sameStringSet(scene.activeSkillIds, resolvedSkillIds)) {
        scene = scene.copyWith(
          activeSkillIds: resolvedSkillIds.toList()..sort(),
          revision: scene.revision + 1,
        );
        await _sceneStore.upsert(scene);
      }

      final execution = await machine.transition(
        conversationId: conversation.id,
        to: StoryRuntimePhase.awaitingModel,
        worldTreeId: tree.worldTreeId,
        worldlineId: worldline.id,
        currentTurnId: tree.currentMessageId,
        memoryVersion: tree.memoryVersion,
      );
      return StoryRuntimePromptResult(
        providerText: assembly.prompt.providerText,
        stablePrefixFingerprint: assembly.prompt.stablePrefixFingerprint,
        stablePrefixRatio: assembly.prompt.diagnostics.stablePrefixRatio,
        worldTreeId: tree.worldTreeId,
        worldlineId: worldline.id,
        currentNodeId: tree.currentNodeId,
        runtimeStateVersion: execution.runtimeStateVersion,
        memoryVersion: tree.memoryVersion,
        visibleStoryMemoryCount: storyScopedMemory.length,
        activeSkillIds: Set.unmodifiable(resolvedSkillIds),
        mcpProfileId: mcpExposure?.profileId,
        allowedMcpToolNames: mcpExposure?.allowedToolNames ?? const <String>{},
        allowedMcpServerIds: mcpExposure?.allowedServerIds ?? const <String>{},
        includeAssistantMcpDefaults:
            mcpExposure?.includeAssistantDefaults ?? true,
        requireMcpApproval: mcpExposure?.requireApproval ?? false,
        sceneId: scene.sceneId,
        sceneRevision: scene.revision,
      );
    } catch (error) {
      await machine.fail(conversationId: conversation.id, error: error);
      rethrow;
    }
  }

  Future<void> _beginAssembly(
    StoryRuntimeStateMachine machine,
    String conversationId,
  ) async {
    final current = await _executionStore.readOrDefault(conversationId);
    if (current.phase == StoryRuntimePhase.awaitingModel ||
        current.phase == StoryRuntimePhase.parsing ||
        current.phase == StoryRuntimePhase.applying) {
      await _executionStore.upsert(
        current.copyWith(
          phase: StoryRuntimePhase.awaitingUser,
          runtimeStateVersion: current.runtimeStateVersion + 1,
        ),
      );
    }
    await machine.transition(
      conversationId: conversationId,
      to: StoryRuntimePhase.assembling,
    );
  }

  String _rootContentHash(
    StoryWorldTreeProjection projection,
    List<ChatMessage> messages,
  ) {
    final first = projection.selectedPath.isEmpty
        ? null
        : projection.selectedPath.first;
    String rootContent = '';
    if (first != null) {
      for (final message in messages) {
        if (message.id == first.messageId) {
          rootContent = message.content;
          break;
        }
      }
    }
    return sha256
        .convert(utf8.encode('${conversationIdSeed(projection)}\n$rootContent'))
        .toString();
  }

  String conversationIdSeed(StoryWorldTreeProjection projection) =>
      projection.selectedPath.isEmpty
      ? 'empty-story-root'
      : '${projection.selectedPath.first.groupId}@${projection.selectedPath.first.version}';

  String _ancestryText(StoryWorldTreeState tree, String worldlineId) {
    final ancestry = tree.ancestryOf(worldlineId);
    return '[STORY_WORLDLINE]\n'
        'tree=${tree.worldTreeId}\n'
        'worldline=$worldlineId\n'
        'mainline=${tree.mainlineWorldlineId ?? ''}\n'
        'ancestry=${ancestry.join('>')}\n'
        '[/STORY_WORLDLINE]';
  }

  String _cursorText(StoryWorldTreeState tree) =>
      '[STORY_CURSOR]\n'
      'current_node=${tree.currentNodeId ?? ''}\n'
      'current_message=${tree.currentMessageId ?? ''}\n'
      'runtime_state_version=${tree.runtimeStateVersion}\n'
      'memory_version=${tree.memoryVersion}\n'
      '[/STORY_CURSOR]';

  String _sceneBaseline(StorySceneRuntimeState scene) {
    final participants = scene.participantCharacterIds.join(',');
    return '[STORY_SCENE_BASELINE]\n'
        'scene=${scene.sceneId ?? ''}\n'
        'location=${scene.location ?? ''}\n'
        'time=${scene.timeLabel ?? ''}\n'
        'participants=$participants\n'
        'pov=${scene.pov}\n'
        '[/STORY_SCENE_BASELINE]';
  }

  String _sceneDynamicText(StorySceneRuntimeState scene) {
    final buffer = StringBuffer('[STORY_SCENE_DYNAMIC]\n');
    if (scene.openLoops.isNotEmpty) {
      buffer.writeln('open_loops=${scene.openLoops.join(' | ')}');
    }
    if (scene.continuityState.isNotEmpty) {
      buffer.writeln('continuity=${jsonEncode(scene.continuityState)}');
    }
    if (scene.serialState.isNotEmpty) {
      buffer.writeln('serial=${jsonEncode(scene.serialState)}');
    }
    buffer.write('[/STORY_SCENE_DYNAMIC]');
    return buffer.toString();
  }

  String _memoryText(List<StoryResolvedMemory> memories) {
    final buffer = StringBuffer('[STORY_WORLDLINE_MEMORY]\n');
    for (final item in memories) {
      buffer.writeln(
        'source=${item.sourceWorldlineId};inherited=${item.inherited};type=${item.entry.type.name};source_kind=${item.sourceKind.name};valid_from_message=${item.validFromMessageId ?? ''};checkpoint=${item.sourceCheckpointId ?? ''}',
      );
      buffer.writeln(item.entry.content.trim());
    }
    buffer.write('[/STORY_WORLDLINE_MEMORY]');
    return buffer.toString();
  }

  String _storyCoreInstructions(StoryRuntimeSessionState session) =>
      '[KELIVO_STORY_RUNTIME_V1]\n'
      'This conversation is in Story Mode. Produce polished original fiction directly readable in Kelivo.\n'
      'SELF is always the real user. Never silently rename SELF, transfer control of SELF to an NPC, or decide consequential SELF choices.\n'
      'Preserve established world facts, identity, injury, inventory, relationships, location, time, and unresolved consequences.\n'
      'Use World Tree and worldline memory only as continuity context. Do not expose internal runtime tags, ids, cache data, schemas, tool routing, or implementation notes to the user.\n'
      'Agency mode: ${session.agencyMode.name}. Manual forbids invented SELF action/dialogue; balanced permits only trivial connective behavior; cinematic still forbids major goals, consent, commitments, irreversible actions, and consequential SELF dialogue.\n'
      '[/KELIVO_STORY_RUNTIME_V1]';
}

bool _sameStringSet(Iterable<String> left, Set<String> right) {
  final leftSet = left.toSet();
  return leftSet.length == right.length && leftSet.containsAll(right);
}
