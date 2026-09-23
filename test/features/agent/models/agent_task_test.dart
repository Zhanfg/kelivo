import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/agent/models/agent_task.dart';

void main() {
  test('agent task round-trips persistent execution bindings', () {
    final createdAt = DateTime.utc(2026, 9, 20, 1, 2, 3);
    final task = AgentTask(
      id: 'task-1',
      title: 'Build app',
      goal: 'Fix the project and build an APK',
      workspaceId: 'workspace-1',
      environmentId: 'env-1',
      conversationId: 'conversation-1',
      assistantId: 'assistant-1',
      worktreeId: 'worktree-1',
      phase: AgentTaskPhase.running,
      currentStep: 'flutter test',
      completedSteps: 3,
      totalSteps: 5,
      createdAt: createdAt,
      updatedAt: createdAt,
      startedAt: createdAt,
    );

    final restored = AgentTask.fromJson(task.toJson());

    expect(restored.id, task.id);
    expect(restored.workspaceId, 'workspace-1');
    expect(restored.environmentId, 'env-1');
    expect(restored.worktreeId, 'worktree-1');
    expect(restored.phase, AgentTaskPhase.running);
    expect(restored.currentStep, 'flutter test');
    expect(restored.completedSteps, 3);
    expect(restored.totalSteps, 5);
    expect(restored.startedAt, createdAt);
  });

  test('only recoverable phases can resume', () {
    expect(AgentTaskPhase.paused.canResume, isTrue);
    expect(AgentTaskPhase.interrupted.canResume, isTrue);
    expect(AgentTaskPhase.failed.canResume, isTrue);
    expect(AgentTaskPhase.running.canResume, isFalse);
    expect(AgentTaskPhase.completed.isTerminal, isTrue);
    expect(AgentTaskPhase.cancelled.isTerminal, isTrue);
  });
}
