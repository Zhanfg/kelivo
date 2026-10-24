import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/agent/services/agent_resume_safety.dart';
import 'package:Kelivo/features/agent/services/agent_task_journal.dart';

AgentTaskEvent record(
  AgentTaskEventKind kind, {
  Map<String, dynamic> payload = const <String, dynamic>{},
}) {
  return AgentTaskEvent(
    id: 'event-${kind.name}',
    taskId: 'task-1',
    kind: kind,
    createdAt: DateTime.utc(2026, 10, 24),
    payload: payload,
  );
}

void main() {
  test('a task that never sent a prompt can start for the first time', () {
    expect(
      AgentResumeSafety.inspect(const <AgentTaskEvent>[]).action,
      AgentResumeAction.fresh,
    );
    expect(
      AgentResumeSafety.inspect(<AgentTaskEvent>[
        record(
          AgentTaskEventKind.phaseChanged,
          payload: const <String, dynamic>{'phase': 'preparing'},
        ),
      ]).action,
      AgentResumeAction.fresh,
    );
  });

  test('durable pre-dispatch marker prevents original goal replay', () {
    final result = AgentResumeSafety.inspect(<AgentTaskEvent>[
      record(
        AgentTaskEventKind.checkpoint,
        payload: const <String, dynamic>{'kind': 'prompt_dispatch_started'},
      ),
    ]);
    expect(result.action, AgentResumeAction.continueSession);
  });

  test('finished tool calls preserve context for safe continuation', () {
    final result = AgentResumeSafety.inspect(<AgentTaskEvent>[
      record(AgentTaskEventKind.turnStarted),
      record(
        AgentTaskEventKind.toolStarted,
        payload: const <String, dynamic>{'toolCallId': 'call-1'},
      ),
      record(
        AgentTaskEventKind.toolFinished,
        payload: const <String, dynamic>{'toolCallId': 'call-1'},
      ),
    ]);
    expect(result.action, AgentResumeAction.continueSession);
  });

  test('uncertain side effect fails closed after process interruption', () {
    final result = AgentResumeSafety.inspect(<AgentTaskEvent>[
      record(AgentTaskEventKind.turnStarted),
      record(
        AgentTaskEventKind.toolStarted,
        payload: const <String, dynamic>{
          'toolCallId': 'call-pending',
          'tool': 'bash',
        },
      ),
    ]);
    expect(result.action, AgentResumeAction.blocked);
    expect(
      result.reason,
      'agent_resume_requires_review_of_unfinished_operation',
    );
  });

  test('unknown correlation IDs are never assumed completed', () {
    final result = AgentResumeSafety.inspect(<AgentTaskEvent>[
      record(AgentTaskEventKind.turnStarted),
      record(AgentTaskEventKind.toolStarted),
      record(AgentTaskEventKind.toolFinished),
    ]);
    expect(result.action, AgentResumeAction.blocked);
  });

  test('unresolved extension approval blocks continuation', () {
    expect(
      AgentResumeSafety.inspect(<AgentTaskEvent>[
        record(AgentTaskEventKind.approvalRequested),
      ]).action,
      AgentResumeAction.blocked,
    );
    expect(
      AgentResumeSafety.inspect(<AgentTaskEvent>[
        record(AgentTaskEventKind.approvalRequested),
        record(AgentTaskEventKind.approvalResolved),
      ]).action,
      AgentResumeAction.continueSession,
    );
  });

  test('manual review clears only prior uncertain operations', () {
    final reviewed = AgentResumeSafety.inspect(<AgentTaskEvent>[
      record(AgentTaskEventKind.turnStarted),
      record(
        AgentTaskEventKind.toolStarted,
        payload: const <String, dynamic>{'toolCallId': 'tool-prior'},
      ),
      record(
        AgentTaskEventKind.checkpoint,
        payload: const <String, dynamic>{
          'kind': 'resume_uncertain_operations_acknowledged',
        },
      ),
    ]);
    expect(reviewed.action, AgentResumeAction.continueSession);

    final interruptedAgain = AgentResumeSafety.inspect(<AgentTaskEvent>[
      record(AgentTaskEventKind.turnStarted),
      record(
        AgentTaskEventKind.toolStarted,
        payload: const <String, dynamic>{'toolCallId': 'tool-prior'},
      ),
      record(
        AgentTaskEventKind.checkpoint,
        payload: const <String, dynamic>{
          'kind': 'resume_uncertain_operations_acknowledged',
        },
      ),
      record(
        AgentTaskEventKind.toolStarted,
        payload: const <String, dynamic>{'toolCallId': 'tool-new'},
      ),
    ]);
    expect(interruptedAgain.action, AgentResumeAction.blocked);
  });

  test('persistent transcript is required before --continue', () async {
    final root = await Directory.systemTemp.createTemp('agent-session-test-');
    addTearDown(() => root.delete(recursive: true));

    expect(await AgentResumeSafety.hasPersistedSession(root), isFalse);
    final nested = Directory('${root.path}/nested');
    await nested.create(recursive: true);
    final file = File('${nested.path}/session.jsonl');
    await file.create();
    expect(await AgentResumeSafety.hasPersistedSession(root), isFalse);
    await file.writeAsString('{"type":"session"}\n');
    expect(await AgentResumeSafety.hasPersistedSession(root), isFalse);
    await file.writeAsString(
      '{"type":"message","message":{"role":"user","content":"work"}}\n',
      mode: FileMode.append,
    );
    expect(await AgentResumeSafety.hasPersistedSession(root), isTrue);
  });
}
