import 'package:uuid/uuid.dart';

import 'story_world_tree_models.dart';
import 'story_world_tree_store.dart';

final class StoryWorldTreeCoordinator {
  StoryWorldTreeCoordinator({
    required StoryWorldTreeRepository repository,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) :
       // Keep the public constructor parameter names stable for callers while
       // retaining private implementation fields.
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _uuid = uuid,
       _now = now ?? DateTime.now;

  final StoryWorldTreeRepository _repository;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<StoryWorldTreeState> bootstrap({
    required String conversationId,
    required String name,
    required String rootContentHash,
    String? currentNodeId,
    String? currentMessageId,
  }) async {
    final existing = await _repository.readForConversation(conversationId);
    if (existing != null) return existing;
    final worldlineId = _uuid.v4();
    final state = StoryWorldTreeState(
      worldTreeId: _uuid.v4(),
      name: name.trim().isEmpty ? 'Story' : name.trim(),
      rootContentHash: rootContentHash,
      headWorldlineId: worldlineId,
      currentNodeId: currentNodeId,
      currentMessageId: currentMessageId,
      worldlines: <StoryWorldline>[
        StoryWorldline(
          id: worldlineId,
          conversationId: _required(conversationId, 'conversationId'),
          createdAt: _now(),
        ),
      ],
    );
    await _repository.upsert(state);
    return state;
  }

  Future<StoryWorldTreeState> fork({
    required String worldTreeId,
    required String sourceWorldlineId,
    required String childConversationId,
    required String branchPointMessageId,
    required String baseSnapshotId,
  }) async {
    final state = await _requiredTree(worldTreeId);
    final source = state.worldlineById(sourceWorldlineId);
    if (source == null) {
      throw StateError('Unknown source worldline: $sourceWorldlineId');
    }
    if (state.worldlineForConversation(childConversationId) != null) {
      throw StateError('Conversation is already bound to this World Tree.');
    }
    final child = StoryWorldline(
      id: _uuid.v4(),
      conversationId: _required(childConversationId, 'childConversationId'),
      createdAt: _now(),
      parentWorldlineId: source.id,
      branchPointMessageId: _required(
        branchPointMessageId,
        'branchPointMessageId',
      ),
      baseSnapshotId: _required(baseSnapshotId, 'baseSnapshotId'),
    );
    final next = state.copyWith(
      headWorldlineId: child.id,
      worldlines: <StoryWorldline>[...state.worldlines, child],
      runtimeStateVersion: state.runtimeStateVersion + 1,
    );
    await _repository.upsert(next);
    return next;
  }

  Future<StoryWorldTreeState> replay({
    required String worldTreeId,
    required String sourceWorldlineId,
    required String childConversationId,
    required String branchPointMessageId,
    required String baseSnapshotId,
  }) async {
    final forked = await fork(
      worldTreeId: worldTreeId,
      sourceWorldlineId: sourceWorldlineId,
      childConversationId: childConversationId,
      branchPointMessageId: branchPointMessageId,
      baseSnapshotId: baseSnapshotId,
    );
    final replayLine = forked.worldlineForConversation(childConversationId)!;
    final lines = <StoryWorldline>[
      for (final line in forked.worldlines)
        if (line.id == replayLine.id)
          line.copyWith(
            metadata: <String, Object?>{
              ...line.metadata,
              'operation': 'replay',
              'replayOfWorldlineId': sourceWorldlineId,
            },
          )
        else
          line,
    ];
    final next = forked.copyWith(worldlines: lines);
    await _repository.upsert(next);
    return next;
  }

  Future<StoryWorldTreeState> merge({
    required String worldTreeId,
    required String sourceWorldlineId,
    required String targetWorldlineId,
    String strategy = 'manual',
  }) async {
    if (sourceWorldlineId == targetWorldlineId) {
      throw ArgumentError('A worldline cannot merge into itself.');
    }
    final state = await _requiredTree(worldTreeId);
    if (state.worldlineById(sourceWorldlineId) == null ||
        state.worldlineById(targetWorldlineId) == null) {
      throw StateError('Merge references an unknown worldline.');
    }
    final lines = <StoryWorldline>[
      for (final line in state.worldlines)
        if (line.id == sourceWorldlineId)
          line.copyWith(status: StoryWorldlineStatus.merged)
        else
          line,
    ];
    final record = StoryWorldMergeRecord(
      id: _uuid.v4(),
      sourceWorldlineId: sourceWorldlineId,
      targetWorldlineId: targetWorldlineId,
      createdAt: _now(),
      strategy: strategy,
    );
    final next = state.copyWith(
      headWorldlineId: targetWorldlineId,
      worldlines: lines,
      merges: <StoryWorldMergeRecord>[...state.merges, record],
      runtimeStateVersion: state.runtimeStateVersion + 1,
    );
    await _repository.upsert(next);
    return next;
  }

  Future<StoryWorldTreeState> syncSelection({
    required String worldTreeId,
    required String worldlineId,
    required String? currentNodeId,
    required String? currentMessageId,
  }) async {
    final state = await _requiredTree(worldTreeId);
    if (state.worldlineById(worldlineId) == null) {
      throw StateError('Unknown worldline: $worldlineId');
    }
    final next = state.copyWith(
      headWorldlineId: worldlineId,
      currentNodeId: currentNodeId,
      currentMessageId: currentMessageId,
      clearCurrentNodeId: currentNodeId == null,
      clearCurrentMessageId: currentMessageId == null,
      runtimeStateVersion: state.runtimeStateVersion + 1,
    );
    await _repository.upsert(next);
    return next;
  }

  Future<StoryWorldTreeState> _requiredTree(String worldTreeId) async {
    final state = await _repository.read(_required(worldTreeId, 'worldTreeId'));
    if (state == null) throw StateError('Unknown World Tree: $worldTreeId');
    return state;
  }
}

String _required(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name);
  return normalized;
}
