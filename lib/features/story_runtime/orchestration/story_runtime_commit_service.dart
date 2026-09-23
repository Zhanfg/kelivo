// ignore_for_file: prefer_initializing_formals

import '../../../core/database/business_preferences.dart';
import '../../../core/models/chat_message.dart';
import '../models/story_runtime_models.dart';
import '../parsing/story_message_event_store.dart';
import '../parsing/story_response_parser.dart';
import '../state/story_runtime_machine.dart';
import '../state/story_runtime_store.dart';
import '../state/story_scene_runtime_reducer.dart';
import '../state/story_scene_runtime_state.dart';
import '../voice/story_voice_context_store.dart';
import '../world_tree/story_world_tree_coordinator.dart';
import '../world_tree/story_world_tree_projection.dart';
import '../world_tree/story_world_tree_store.dart';

final class StoryFinalizedCommitResult {
  const StoryFinalizedCommitResult({
    required this.structured,
    this.visibleText,
  });

  final bool structured;
  final String? visibleText;
}

/// Commits a successfully finalized native Kelivo assistant reply into Story
/// sidecar state without changing Kelivo's ChatMessage schema.
///
/// Structured Story responses keep normal reader-visible Markdown in the
/// native message and append a hidden event trailer. The trailer is parsed into
/// sidecar state; callers may then replace ChatMessage.content with [visibleText].
/// Plain prose or malformed trailers remain readable compatibility fallbacks.
final class StoryRuntimeCommitService {
  StoryRuntimeCommitService(BusinessPreferences preferences)
    : this.withRepositories(
        sessionStore: StoryRuntimeStore(preferences),
        executionStore: StoryRuntimeExecutionStore(preferences),
        worldTreeStore: StoryWorldTreeStore(preferences),
        sceneRuntimeStore: StorySceneRuntimeStore(preferences),
        messageEventStore: StoryMessageEventStore(preferences),
        voiceContextStore: StoryVoiceContextHistoryStore(preferences),
      );

  StoryRuntimeCommitService.withRepositories({
    required StoryRuntimeSessionRepository sessionStore,
    required StoryRuntimeExecutionRepository executionStore,
    required StoryWorldTreeRepository worldTreeStore,
    StorySceneRuntimeRepository? sceneRuntimeStore,
    StoryMessageEventStore? messageEventStore,
    StoryVoiceContextHistoryStore? voiceContextStore,
  }) : _sessionStore = sessionStore,
       _executionStore = executionStore,
       _worldTreeStore = worldTreeStore,
       _sceneRuntimeStore = sceneRuntimeStore,
       _messageEventStore = messageEventStore,
       _voiceContextStore = voiceContextStore;

  final StoryRuntimeSessionRepository _sessionStore;
  final StoryRuntimeExecutionRepository _executionStore;
  final StoryWorldTreeRepository _worldTreeStore;
  final StorySceneRuntimeRepository? _sceneRuntimeStore;
  final StoryMessageEventStore? _messageEventStore;
  final StoryVoiceContextHistoryStore? _voiceContextStore;

  /// Recovery-safe bridge for the current Kelivo lifecycle.
  Future<void> commitPendingFinalizedTurn(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final conversationId = messages.last.conversationId.trim();
    if (conversationId.isEmpty) return;
    final execution = await _executionStore.readOrDefault(conversationId);
    if (execution.phase != StoryRuntimePhase.awaitingModel &&
        execution.phase != StoryRuntimePhase.parsing &&
        execution.phase != StoryRuntimePhase.applying) {
      return;
    }
    final turnId = execution.currentTurnId?.trim();
    if (turnId == null || turnId.isEmpty) return;

    ChatMessage? finalized;
    for (final message in messages.reversed) {
      if (message.id != turnId) continue;
      if (message.role != 'assistant' || message.isStreaming) return;
      if (message.durationMs == null) return;
      finalized = message;
      break;
    }
    if (finalized == null) return;
    await commitAssistantMessage(finalized);
  }

  Future<StoryFinalizedCommitResult?> commitAssistantMessage(
    ChatMessage message,
  ) async {
    final conversationId = message.conversationId.trim();
    if (conversationId.isEmpty || message.role != 'assistant') return null;

    final session = await _sessionStore.readOrDefault(conversationId);
    if (!session.enabled) return null;

    final machine = StoryRuntimeStateMachine(_executionStore);
    var execution = await _executionStore.readOrDefault(conversationId);

    if (execution.phase == StoryRuntimePhase.awaitingUser &&
        execution.currentTurnId == message.id) {
      final existing = await _messageEventStore?.readForMessage(message.id);
      final visible = _visibleTextIfTrailerPresent(message.content);
      await _recordVoiceContext(message, visible ?? message.content);
      return StoryFinalizedCommitResult(
        structured: existing != null,
        visibleText: visible,
      );
    }

    try {
      if (execution.phase != StoryRuntimePhase.awaitingModel &&
          execution.phase != StoryRuntimePhase.parsing &&
          execution.phase != StoryRuntimePhase.applying) {
        throw StateError('story_finalize_out_of_phase:${execution.phase.name}');
      }
      final expectedTurnId = execution.currentTurnId?.trim();
      if (expectedTurnId != null &&
          expectedTurnId.isNotEmpty &&
          expectedTurnId != message.id) {
        throw StateError('story_finalize_message_mismatch');
      }

      if (execution.phase == StoryRuntimePhase.awaitingModel) {
        execution = await machine.transition(
          conversationId: conversationId,
          to: StoryRuntimePhase.parsing,
          currentTurnId: message.id,
        );
      }

      StoryParsedResponse? parsed;
      StoryTurn? parsedTurn;
      if (execution.phase == StoryRuntimePhase.parsing ||
          execution.phase == StoryRuntimePhase.applying) {
        try {
          parsed = const StoryResponseParser().parseEmbedded(
            message.content,
            turnId: message.id,
          );
          parsedTurn = parsed.turn;
          final eventStore = _messageEventStore;
          if (eventStore != null) {
            await eventStore.upsertRecord(
              StoryMessageEventRecord(
                conversationId: conversationId,
                messageId: message.id,
                turn: parsedTurn,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          }
        } on StoryResponseParseException {
          parsed = null;
          parsedTurn = null;
        } on FormatException {
          parsed = null;
          parsedTurn = null;
        }
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

      final coordinator = StoryWorldTreeCoordinator(
        repository: _worldTreeStore,
      );
      final committedTree = await coordinator.syncSelection(
        worldTreeId: tree.worldTreeId,
        worldlineId: worldline.id,
        currentNodeId: StoryWorldTreeProjection.nodeId(
          message.groupId ?? message.id,
          message.version,
        ),
        currentMessageId: message.id,
      );

      final sceneStore = _sceneRuntimeStore;
      if (sceneStore != null && parsedTurn != null) {
        final currentScene = await sceneStore.readOrDefault(conversationId);
        final nextScene = reduceStoryTurnIntoScene(
          current: currentScene,
          turn: parsedTurn,
          worldTreeId: committedTree.worldTreeId,
          worldlineId: worldline.id,
        );
        if (nextScene.revision != currentScene.revision ||
            nextScene.worldTreeId != currentScene.worldTreeId ||
            nextScene.worldlineId != currentScene.worldlineId) {
          await sceneStore.upsert(nextScene);
        }
      }

      await _recordVoiceContext(
        message,
        parsed?.visibleText ?? message.content,
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
      return StoryFinalizedCommitResult(
        structured: parsedTurn != null,
        visibleText: parsed?.visibleText,
      );
    } catch (error) {
      await machine.fail(conversationId: conversationId, error: error);
      rethrow;
    }
  }

  Future<void> _recordVoiceContext(ChatMessage message, String text) async {
    final store = _voiceContextStore;
    if (store == null) return;
    final clean = _stripEmbeddedTrailerBestEffort(text).trim();
    if (clean.isEmpty) return;
    await store.record(
      conversationId: message.conversationId,
      messageId: message.id,
      text: clean,
    );
  }
}

String? _visibleTextIfTrailerPresent(String content) {
  try {
    return const StoryResponseParser()
        .parseEmbedded(content, turnId: 'recovery')
        .visibleText;
  } on Object {
    return null;
  }
}

String _stripEmbeddedTrailerBestEffort(String content) =>
    _visibleTextIfTrailerPresent(content) ??
    content.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').trimRight();
