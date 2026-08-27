import '../../../core/database/business_preferences.dart';
import '../../../core/models/chat_message.dart';
import '../state/story_runtime_machine.dart';
import '../state/story_runtime_store.dart';
import '../world_tree/story_world_tree_coordinator.dart';
import '../world_tree/story_world_tree_projection.dart';
import '../world_tree/story_world_tree_store.dart';

/// Commits a successfully finalized native Kelivo assistant reply into the
/// Story Runtime sidecar state.
///
/// Story Mode currently asks providers for directly readable prose, not a JSON
/// response envelope. Consequently this service deliberately treats Kelivo's
/// finalized message revision as the authoritative turn boundary and advances
/// the World Tree cursor without rewriting the message body.
final class StoryRuntimeCommitService {
  StoryRuntimeCommitService(BusinessPreferences preferences)
    : _sessionStore = StoryRuntimeStore(preferences),
      _executionStore = StoryRuntimeExecutionStore(preferences),
      _worldTreeStore = StoryWorldTreeStore(preferences);

  final StoryRuntimeStore _sessionStore;
  final StoryRuntimeExecutionStore _executionStore;
  final StoryWorldTreeStore _worldTreeStore;

  Future<void> commitAssistantMessage(ChatMessage message) async {
    final conversationId = message.conversationId.trim();
    if (conversationId.isEmpty || message.role != 'assistant') return;

    final session = await _sessionStore.readOrDefault(conversationId);
    if (!session.enabled) return;

    final machine = StoryRuntimeStateMachine(_executionStore);
    var execution = await _executionStore.readOrDefault(conversationId);

    // Finalization callbacks can be replayed during UI/controller recovery.
    // Once this exact assistant revision reached awaitingUser, committing it a
    // second time would only create artificial World Tree/session revisions.
    if (execution.phase == StoryRuntimePhase.awaitingUser &&
        execution.currentTurnId == message.id) {
      return;
    }

    try {
      if (execution.phase != StoryRuntimePhase.awaitingModel &&
          execution.phase != StoryRuntimePhase.parsing &&
          execution.phase != StoryRuntimePhase.applying) {
        throw StateError(
          'story_finalize_out_of_phase:${execution.phase.name}',
        );
      }

      if (execution.phase == StoryRuntimePhase.awaitingModel) {
        execution = await machine.transition(
          conversationId: conversationId,
          to: StoryRuntimePhase.parsing,
          currentTurnId: message.id,
        );
      }
      if (execution.phase == StoryRuntimePhase.parsing) {
        execution = await machine.transition(
          conversationId: conversationId,
          to: StoryRuntimePhase.applying,
          currentTurnId: message.id,
        );
      }

      final tree = await _worldTreeStore.readForConversation(conversationId);
      if (tree == null) {
        throw StateError('story_world_tree_missing_on_finalize');
      }
      final worldline = tree.worldlineForConversation(conversationId);
      if (worldline == null) {
        throw StateError('story_worldline_missing_on_finalize');
      }

      final coordinator = StoryWorldTreeCoordinator(repository: _worldTreeStore);
      final committedTree = await coordinator.syncSelection(
        worldTreeId: tree.worldTreeId,
        worldlineId: worldline.id,
        currentNodeId: StoryWorldTreeProjection.nodeId(
          message.groupId ?? message.id,
          message.version,
        ),
        currentMessageId: message.id,
      );

      await _sessionStore.upsert(
        session.copyWith(
          worldlineId: worldline.id,
          sceneRevision: session.sceneRevision + 1,
        ),
      );

      await machine.transition(
        conversationId: conversationId,
        to: StoryRuntimePhase.awaitingUser,
        worldTreeId: committedTree.worldTreeId,
        worldlineId: worldline.id,
        currentTurnId: message.id,
        memoryVersion: committedTree.memoryVersion,
      );
    } catch (error) {
      await machine.fail(conversationId: conversationId, error: error);
      rethrow;
    }
  }
}
