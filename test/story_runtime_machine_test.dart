import 'package:Kelivo/features/story_runtime/state/story_runtime_machine.dart';
import 'package:flutter_test/flutter_test.dart';

final class MemoryExecutionRepository
    implements StoryRuntimeExecutionRepository {
  StoryRuntimeExecutionState? value;

  @override
  Future<StoryRuntimeExecutionState> readOrDefault(String conversationId) async =>
      value ?? StoryRuntimeExecutionState(conversationId: conversationId);

  @override
  Future<void> upsert(StoryRuntimeExecutionState state) async {
    value = state;
  }
}

void main() {
  test('runtime state machine accepts the normal turn lifecycle', () async {
    final repo = MemoryExecutionRepository();
    final machine = StoryRuntimeStateMachine(repo);
    for (final phase in <StoryRuntimePhase>[
      StoryRuntimePhase.assembling,
      StoryRuntimePhase.awaitingModel,
      StoryRuntimePhase.parsing,
      StoryRuntimePhase.applying,
      StoryRuntimePhase.awaitingUser,
      StoryRuntimePhase.idle,
    ]) {
      await machine.transition(conversationId: 'c', to: phase);
    }
    expect(repo.value?.phase, StoryRuntimePhase.idle);
    expect(repo.value?.runtimeStateVersion, 6);
  });

  test('invalid phase jump is rejected', () async {
    final repo = MemoryExecutionRepository();
    final machine = StoryRuntimeStateMachine(repo);
    expect(
      () => machine.transition(
        conversationId: 'c',
        to: StoryRuntimePhase.parsing,
      ),
      throwsStateError,
    );
  });

  test('failure can recover into a fresh assembly', () async {
    final repo = MemoryExecutionRepository();
    final machine = StoryRuntimeStateMachine(repo);
    await machine.transition(
      conversationId: 'c',
      to: StoryRuntimePhase.assembling,
    );
    await machine.fail(conversationId: 'c', error: StateError('boom'));
    await machine.transition(
      conversationId: 'c',
      to: StoryRuntimePhase.assembling,
    );
    expect(repo.value?.phase, StoryRuntimePhase.assembling);
    expect(repo.value?.recentFailure, isNull);
  });
}
