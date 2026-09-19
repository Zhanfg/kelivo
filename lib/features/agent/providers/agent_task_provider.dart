import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/extension_entity_store.dart';
import '../models/agent_task.dart';
import '../services/agent_task_journal.dart';

class AgentTaskProvider extends ChangeNotifier {
  AgentTaskProvider({required this.store, this.journal}) {
    loaded = _load();
  }

  final ExtensionEntityStore store;
  final AgentTaskJournal? journal;
  final List<AgentTask> _tasks = <AgentTask>[];

  late final Future<void> loaded;

  List<AgentTask> get tasks => List<AgentTask>.unmodifiable(_tasks);

  List<AgentTask> get resumableTasks =>
      _tasks.where((task) => task.canResume).toList(growable: false);

  AgentTask? byId(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final entities = await store.listByKind(
        ExtensionEntityStore.kindAgentTask,
      );
      _tasks
        ..clear()
        ..addAll([
          for (final entity in entities) AgentTask.fromJson(entity.payload),
        ]);
    } catch (error) {
      debugPrint('Failed to load agent tasks: $error');
      _tasks.clear();
    }
    notifyListeners();
  }

  Future<AgentTask> create({
    required String title,
    required String goal,
    required String workspaceId,
    String environmentId = 'default',
    String? conversationId,
    String? assistantId,
    String? worktreeId,
  }) async {
    await loaded;
    final now = DateTime.now().toUtc();
    final task = AgentTask(
      id: const Uuid().v4(),
      title: title.trim(),
      goal: goal,
      workspaceId: workspaceId,
      environmentId: environmentId,
      conversationId: conversationId,
      assistantId: assistantId,
      worktreeId: worktreeId,
      phase: AgentTaskPhase.queued,
      createdAt: now,
      updatedAt: now,
    );
    await _persist(task, sortOrder: _tasks.length);
    _tasks.add(task);
    notifyListeners();
    return task;
  }

  Future<void> update(AgentTask task) async {
    await loaded;
    final next = task.copyWith(updatedAt: DateTime.now().toUtc());
    final index = _tasks.indexWhere((item) => item.id == next.id);
    await _persist(next, sortOrder: index >= 0 ? index : null);
    if (index >= 0) {
      _tasks[index] = next;
    } else {
      _tasks.add(next);
    }
    notifyListeners();
  }

  Future<void> setPhase(
    String id,
    AgentTaskPhase phase, {
    String? currentStep,
    String? error,
  }) async {
    await loaded;
    final current = byId(id);
    if (current == null) return;

    final now = DateTime.now().toUtc();
    final isStarting =
        current.startedAt == null &&
        (phase == AgentTaskPhase.preparing || phase == AgentTaskPhase.running);
    final isFinishing = phase.isTerminal;

    await update(
      current.copyWith(
        phase: phase,
        currentStep: currentStep,
        lastError: error,
        startedAt: isStarting ? now : null,
        finishedAt: isFinishing ? now : null,
        clearLastError: error == null && phase != AgentTaskPhase.failed,
        clearFinishedAt: !isFinishing,
      ),
    );
    await journal?.append(
      id,
      AgentTaskEventKind.phaseChanged,
      payload: <String, dynamic>{
        'phase': phase.name,
        if (currentStep != null) 'step': currentStep,
        if (error != null) 'hasError': true,
      },
    );
  }

  /// Marks unfinished work as recoverable after a worker/runtime crash.
  ///
  /// Bootstrap code should call this only after confirming no worker still owns
  /// the task. The task data, workspace, and environment remain untouched.
  Future<int> markUnownedRunningTasksInterrupted() async {
    await loaded;
    var count = 0;
    for (final task in List<AgentTask>.of(_tasks)) {
      if (task.phase != AgentTaskPhase.preparing &&
          task.phase != AgentTaskPhase.running &&
          task.phase != AgentTaskPhase.verifying &&
          task.phase != AgentTaskPhase.recovering) {
        continue;
      }
      await setPhase(task.id, AgentTaskPhase.interrupted);
      count++;
    }
    return count;
  }

  Future<void> delete(String id) async {
    await loaded;
    await store.delete(ExtensionEntityStore.kindAgentTask, id);
    _tasks.removeWhere((task) => task.id == id);
    notifyListeners();
  }

  Future<void> _persist(AgentTask task, {int? sortOrder}) {
    return store.upsert(
      ExtensionEntityStore.kindAgentTask,
      task.id,
      task.toJson(),
      sortOrder: sortOrder,
      ownerId: task.workspaceId,
    );
  }
}
