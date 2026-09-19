import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/agent/services/agent_task_journal.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kelivo-agent-journal-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('journal persists ordered task events', () async {
    final journal = AgentTaskJournal(rootDirectory: root);

    await journal.append(
      'task-1',
      AgentTaskEventKind.toolStarted,
      payload: const {'tool': 'flutter_test'},
    );
    await journal.append(
      'task-1',
      AgentTaskEventKind.toolFinished,
      payload: const {'tool': 'flutter_test', 'exitCode': 0},
    );

    final restored = AgentTaskJournal(rootDirectory: root);
    final events = await restored.read('task-1');

    expect(events, hasLength(2));
    expect(events.first.kind, AgentTaskEventKind.toolStarted);
    expect(events.last.kind, AgentTaskEventKind.toolFinished);
    expect(events.last.payload['exitCode'], 0);
  });

  test('journal ignores a corrupt trailing record', () async {
    final journal = AgentTaskJournal(rootDirectory: root);
    await journal.append('task-1', AgentTaskEventKind.note);

    final file = File('${root.path}/task-1/journal.ndjson');
    await file.writeAsString(
      '{"broken":',
      mode: FileMode.append,
      flush: true,
    );

    final events = await journal.read('task-1');
    expect(events, hasLength(1));
    expect(events.single.kind, AgentTaskEventKind.note);
  });
}
