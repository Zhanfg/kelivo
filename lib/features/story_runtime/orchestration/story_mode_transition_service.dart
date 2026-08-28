import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/services/chat/chat_service.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import '../state/story_scene_runtime_state.dart';
import '../world_tree/story_world_tree_coordinator.dart';
import '../world_tree/story_world_tree_store.dart';

/// Performs the actual Chat <-> Story transition for a native Kelivo
/// conversation.
///
/// Chat -> Story is not a cosmetic boolean toggle. It bootstraps (or resumes)
/// a World Tree, binds the current native conversation to its worldline,
/// synchronizes the current native message head and initializes the scene
/// sidecar before Story Runtime is marked enabled.
///
/// Story -> Chat stops future Story orchestration but deliberately keeps those
/// sidecars intact so switching back to Story resumes the same continuity.
final class StoryModeTransitionService {
  StoryModeTransitionService({
    required BusinessPreferences preferences,
    required ChatService chatService,
  }) : _chatService = chatService,
       _runtimeStore = StoryRuntimeStore(preferences),
       _sceneStore = StorySceneRuntimeStore(preferences),
       _worldTreeStore = StoryWorldTreeStore(preferences),
       _worldTreeCoordinator = StoryWorldTreeCoordinator(
         repository: StoryWorldTreeStore(preferences),
       );

  final ChatService _chatService;
  final StoryRuntimeStore _runtimeStore;
  final StorySceneRuntimeStore _sceneStore;
  final StoryWorldTreeStore _worldTreeStore;
  final StoryWorldTreeCoordinator _worldTreeCoordinator;

  Future<StoryRuntimeSessionState> setMode({
    required String conversationId,
    required bool storyEnabled,
  }) async {
    final id = conversationId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(conversationId, 'conversationId');
    }

    final current = await _runtimeStore.readOrDefault(id);
    if (!storyEnabled) {
      final next = current.copyWith(
        enabled: false,
        modeSelectionCommitted: true,
      );
      await _runtimeStore.upsert(next);
      return next;
    }

    final conversation = _chatService.getConversation(id);
    if (conversation == null) {
      throw StateError('Cannot enter Story Mode for an unknown conversation.');
    }

    final messageIds = List<String>.of(conversation.messageIds);
    final currentMessageId = messageIds.isEmpty ? null : messageIds.last;
    final rootContentHash = sha256
        .convert(
          utf8.encode(
            <String>[
              id,
              conversation.createdAt.toUtc().toIso8601String(),
              ...messageIds,
            ].join('\n'),
          ),
        )
        .toString();

    var tree = await _worldTreeCoordinator.bootstrap(
      conversationId: id,
      name: conversation.title,
      rootContentHash: rootContentHash,
      currentMessageId: currentMessageId,
    );
    final line = tree.worldlineForConversation(id);
    if (line == null) {
      throw StateError('Story World Tree lost its conversation worldline.');
    }

    // Existing Story conversations may have advanced native chat history while
    // temporarily in Chat mode. Re-anchor the worldline to the native head
    // before enabling Story orchestration again.
    if (tree.currentMessageId != currentMessageId ||
        tree.headWorldlineId != line.id) {
      tree = await _worldTreeCoordinator.syncSelection(
        worldTreeId: tree.worldTreeId,
        worldlineId: line.id,
        currentNodeId: tree.currentNodeId,
        currentMessageId: currentMessageId,
      );
    }

    // Re-read by conversation to ensure the coordinator write is visible and
    // to protect against future coordinator implementations returning a copy.
    final persistedTree =
        await _worldTreeStore.readForConversation(id) ?? tree;
    final persistedLine = persistedTree.worldlineForConversation(id);
    if (persistedLine == null) {
      throw StateError('Story worldline binding was not persisted.');
    }

    final scene = await _sceneStore.readOrDefault(id);
    final nextScene = scene.copyWith(
      worldTreeId: persistedTree.worldTreeId,
      worldlineId: persistedLine.id,
      revision: scene.revision + 1,
      serialState: <String, Object?>{
        ...scene.serialState,
        'modeTransition': <String, Object?>{
          'source': 'native_chat',
          'messageCount': messageIds.length,
          if (currentMessageId != null) 'messageHeadId': currentMessageId,
          'transitionedAtMs': DateTime.now().millisecondsSinceEpoch,
        },
      },
    );
    await _sceneStore.upsert(nextScene);

    final next = current.copyWith(
      enabled: true,
      modeSelectionCommitted: true,
      worldlineId: persistedLine.id,
      sceneEpochId: nextScene.sceneId,
      sceneRevision: nextScene.revision,
    );
    await _runtimeStore.upsert(next);
    return next;
  }
}
