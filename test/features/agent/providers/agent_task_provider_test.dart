import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/extension_entity_store.dart';
import 'package:Kelivo/features/agent/models/agent_task.dart';
import 'package:Kelivo/features/agent/providers/agent_task_provider.dart';

void main() {
  late AppDatabase database;
  late ExtensionEntityStore store;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = ExtensionEntityStore(database);
    await database.customSelect('SELECT 1;').getSingle();
  });

  tearDown(() => database.close());

  test('tasks survive provider recreation', () async {
    final first = AgentTaskProvider(store: store);
    await first.loaded;

    final created = await first.create(
      title: 'Persistent task',
      goal: 'Keep state across app restarts',
      workspaceId: 'workspace-1',
      environmentId: 'environment-1',
    );
    await first.setPhase(
      created.id,
      AgentTaskPhase.running,
      currentStep: 'install dependencies',
    );

    final second = AgentTaskProvider(store: store);
    await second.loaded;
    final restored = second.byId(created.id);

    expect(restored, isNotNull);
    expect(restored!.workspaceId, 'workspace-1');
    expect(restored.environmentId, 'environment-1');
    expect(restored.phase, AgentTaskPhase.running);
    expect(restored.currentStep, 'install dependencies');
  });

  test('unfinished unowned tasks become resumable after restart', () async {
    final provider = AgentTaskProvider(store: store);
    await provider.loaded;
    final task = await provider.create(
      title: 'Interrupted task',
      goal: 'Resume safely',
      workspaceId: 'workspace-1',
    );
    await provider.setPhase(task.id, AgentTaskPhase.verifying);

    final changed = await provider.markUnownedRunningTasksInterrupted();

    expect(changed, 1);
    expect(provider.byId(task.id)!.phase, AgentTaskPhase.interrupted);
    expect(provider.byId(task.id)!.canResume, isTrue);
  });
}
