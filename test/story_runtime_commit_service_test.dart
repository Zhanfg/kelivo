import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/story_runtime/orchestration/story_runtime_commit_service.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_machine.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_state.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_store.dart';
import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_models.dart';
import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_projection.dart';
import 'package:Kelivo/features/story_runtime/world_tree/story_world_tree_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoryRuntimeCommitService', () {
    test('commits a successful finalized native reply into Story state', () async {
      final fixture = _Fixture();
      final service = fixture.service;
      final message = fixture.finalizedMessage();

      await service.commitPendingFinalizedTurn(<ChatMessage>[message]);

      final execution = fixture.execution.value!;
      expect(execution.phase, StoryRuntimePhase.awaitingUser);
      expect(execution.currentTurnId, 'assistant-1');
      expect(execution.runtimeStateVersion, 13);

      final session = fixture.sessions.states['conversation-1']!;
      expect(session.sceneRevision, 3);
      expect(session.worldlineId, 'worldline-1');

      final tree = fixture.worldTrees.state!;
      expect(tree.currentMessageId, 'assistant-1');
      expect(
        tree.currentNodeId,
        StoryWorldTreeProjection.nodeId('assistant-group', 0),
      );
      expect(tree.runtimeStateVersion, 5);
    });

    test('replaying finalized reconciliation is idempotent', () async {
      final fixture = _Fixture();
      final service = fixture.service;
      final message = fixture.finalizedMessage();

      await service.commitPendingFinalizedTurn(<ChatMessage>[message]);
      final firstSceneRevision =
          fixture.sessions.states['conversation-1']!.sceneRevision;
      final firstTreeRevision = fixture.worldTrees.state!.runtimeStateVersion;
      final firstExecutionRevision = fixture.execution.value!.runtimeStateVersion;

      await service.commitPendingFinalizedTurn(<ChatMessage>[message]);

      expect(
        fixture.sessions.states['conversation-1']!.sceneRevision,
        firstSceneRevision,
      );
      expect(fixture.worldTrees.state!.runtimeStateVersion, firstTreeRevision);
      expect(fixture.execution.value!.runtimeStateVersion, firstExecutionRevision);
    });

    test('does not commit a non-successful finalized-looking reply', () async {
      final fixture = _Fixture();
      final message = fixture.finalizedMessage(durationMs: null);

      await fixture.service.commitPendingFinalizedTurn(<ChatMessage>[message]);

      expect(fixture.execution.value!.phase, StoryRuntimePhase.awaitingModel);
      expect(fixture.execution.value!.runtimeStateVersion, 10);
      expect(
        fixture.sessions.states['conversation-1']!.sceneRevision,
        2,
      );
      expect(fixture.worldTrees.state!.runtimeStateVersion, 4);
    });
  });
}

final class _Fixture {
  _Fixture() {
    sessions.states['conversation-1'] = const StoryRuntimeSessionState(
      conversationId: 'conversation-1',
      enabled: true,
      worldlineId: 'worldline-1',
      sceneRevision: 2,
    );
    execution.value = const StoryRuntimeExecutionState(
      conversationId: 'conversation-1',
      phase: StoryRuntimePhase.awaitingModel,
      runtimeStateVersion: 10,
      memoryVersion: 7,
      worldTreeId: 'tree-1',
      worldlineId: 'worldline-1',
      currentTurnId: 'assistant-1',
    );
    worldTrees.state = StoryWorldTreeState(
      worldTreeId: 'tree-1',
      name: 'Story',
      rootContentHash: 'root-hash',
      headWorldlineId: 'worldline-1',
      currentNodeId: 'placeholder@0',
      currentMessageId: 'assistant-1',
      memoryVersion: 7,
      runtimeStateVersion: 4,
      worldlines: <StoryWorldline>[
        StoryWorldline(
          id: 'worldline-1',
          conversationId: 'conversation-1',
          createdAt: DateTime.utc(2026, 8, 27),
        ),
      ],
    );
  }

  final _SessionRepository sessions = _SessionRepository();
  final _ExecutionRepository execution = _ExecutionRepository();
  final _WorldTreeRepository worldTrees = _WorldTreeRepository();

  StoryRuntimeCommitService get service =>
      StoryRuntimeCommitService.withRepositories(
        sessionStore: sessions,
        executionStore: execution,
        worldTreeStore: worldTrees,
      );

  ChatMessage finalizedMessage({int? durationMs = 125}) => ChatMessage(
    id: 'assistant-1',
    role: 'assistant',
    content: 'The story continues.',
    conversationId: 'conversation-1',
    isStreaming: false,
    groupId: 'assistant-group',
    version: 0,
    durationMs: durationMs,
  );
}

final class _SessionRepository implements StoryRuntimeSessionRepository {
  final Map<String, StoryRuntimeSessionState> states =
      <String, StoryRuntimeSessionState>{};

  @override
  Future<StoryRuntimeSessionState?> readForConversation(
    String conversationId,
  ) async => states[conversationId];

  @override
  Future<StoryRuntimeSessionState> readOrDefault(String conversationId) async =>
      states[conversationId] ??
      StoryRuntimeSessionState(conversationId: conversationId);

  @override
  Future<void> upsert(StoryRuntimeSessionState state) async {
    states[state.conversationId] = state;
  }

  @override
  Future<void> setEnabled(String conversationId, bool enabled) async {
    final current = await readOrDefault(conversationId);
    states[conversationId] = current.copyWith(enabled: enabled);
  }

  @override
  Future<void> removeForConversation(String conversationId) async {
    states.remove(conversationId);
  }
}

final class _ExecutionRepository implements StoryRuntimeExecutionRepository {
  StoryRuntimeExecutionState? value;

  @override
  Future<StoryRuntimeExecutionState> readOrDefault(String conversationId) async =>
      value ?? StoryRuntimeExecutionState(conversationId: conversationId);

  @override
  Future<void> upsert(StoryRuntimeExecutionState state) async {
    value = state;
  }
}

final class _WorldTreeRepository implements StoryWorldTreeRepository {
  StoryWorldTreeState? state;

  @override
  Future<StoryWorldTreeState?> read(String worldTreeId) async =>
      state?.worldTreeId == worldTreeId ? state : null;

  @override
  Future<StoryWorldTreeState?> readForConversation(String conversationId) async {
    final value = state;
    if (value == null) return null;
    return value.worldlineForConversation(conversationId) == null ? null : value;
  }

  @override
  Future<void> upsert(StoryWorldTreeState value) async {
    state = value;
  }

  @override
  Future<void> remove(String worldTreeId) async {
    if (state?.worldTreeId == worldTreeId) state = null;
  }
}
