// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/models/conversation_kind.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import '../state/story_scene_runtime_state.dart';
import '../world_tree/story_world_tree_coordinator.dart';
import '../world_tree/story_world_tree_store.dart';

/// Performs the one-way Chat -> Story promotion for a native Kelivo
/// conversation.
///
/// Promotion bootstraps (or resumes) World Tree/scene sidecars before committing
/// ConversationKind.story. Story -> Chat is intentionally not a state
/// transition: leaving the Story workspace never destroys or disables Story
/// continuity.
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

  /// Compatibility entry point for older callers.
  ///
  /// Story promotion is one-way. Passing storyEnabled=false never demotes an
  /// existing Story conversation; workspace navigation is handled separately.
  Future<StoryRuntimeSessionState> setMode({
    required String conversationId,
    required bool storyEnabled,
  }) async {
    final id = conversationId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(conversationId, 'conversationId');
    }
    if (!storyEnabled) {
      return _runtimeStore.readOrDefault(id);
    }
    return promoteToStory(id);
  }

  /// Irreversibly promotes a native Chat conversation into Story.
  ///
  /// Runtime sidecars are prepared first. ConversationKind.story is written
  /// last as the commit point, so a failed bootstrap remains a recoverable Chat.
  Future<StoryRuntimeSessionState> promoteToStory(
    String conversationId,
  ) async {
    final id = conversationId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(conversationId, 'conversationId');
    }

    final current = await _runtimeStore.readOrDefault(id);
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
    final persistedTree = await _worldTreeStore.readForConversation(id) ?? tree;
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

    // Commit point: once marked Story, the conversation never becomes Chat
    // again. Legacy callers that "switch to Chat" only leave the Story
    // workspace; they do not mutate this ownership.
    await _chatService.updateConversationExtras(
      id,
      (extras) => conversationExtrasWithKind(extras, ConversationKind.story),
    );
    return next;
  }
}
