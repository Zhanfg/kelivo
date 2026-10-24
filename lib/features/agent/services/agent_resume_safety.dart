import 'dart:io';

import 'agent_task_journal.dart';

/// A conservative recovery boundary for already-started Agent work.
///
/// It distinguishes a task which never sent its first prompt from one whose
/// tools may have mutated a workspace or external system before Android died.
/// It does NOT claim exactly-once execution of third-party operations.
enum AgentResumeAction { fresh, continueSession, blocked }

class AgentResumeDecision {
  const AgentResumeDecision(this.action, {this.reason});

  final AgentResumeAction action;
  final String? reason;
}

abstract final class AgentResumeSafety {
  static AgentResumeDecision inspect(List<AgentTaskEvent> events) {
    var promptMayHaveRun = false;
    var unresolvedApprovals = 0;
    var uncorrelatedTool = false;
    final pendingTools = <String>{};

    for (final event in events) {
      final payload = event.payload;
      switch (event.kind) {
        case AgentTaskEventKind.checkpoint:
          if (payload['kind'] == 'prompt_dispatch_started') {
            promptMayHaveRun = true;
          } else if (payload['kind'] ==
              'resume_uncertain_operations_acknowledged') {
            // Only an explicit review may clear uncertainties that predate it.
            // Any subsequent in-flight tool or approval blocks again.
            promptMayHaveRun = true;
            pendingTools.clear();
            uncorrelatedTool = false;
            unresolvedApprovals = 0;
          }
          break;
        case AgentTaskEventKind.turnStarted:
          promptMayHaveRun = true;
          break;
        case AgentTaskEventKind.toolStarted:
          promptMayHaveRun = true;
          final id = payload['toolCallId']?.toString();
          if (id == null || id.isEmpty) {
            uncorrelatedTool = true;
          } else {
            pendingTools.add(id);
          }
          break;
        case AgentTaskEventKind.toolFinished:
          final id = payload['toolCallId']?.toString();
          if (id == null || id.isEmpty) {
            uncorrelatedTool = true;
          } else {
            pendingTools.remove(id);
          }
          break;
        case AgentTaskEventKind.approvalRequested:
          promptMayHaveRun = true;
          unresolvedApprovals++;
          break;
        case AgentTaskEventKind.approvalResolved:
          if (unresolvedApprovals > 0) unresolvedApprovals--;
          break;
        default:
          break;
      }
    }

    if (uncorrelatedTool ||
        pendingTools.isNotEmpty ||
        unresolvedApprovals != 0) {
      return const AgentResumeDecision(
        AgentResumeAction.blocked,
        reason: 'agent_resume_requires_review_of_unfinished_operation',
      );
    }
    return AgentResumeDecision(
      promptMayHaveRun
          ? AgentResumeAction.continueSession
          : AgentResumeAction.fresh,
    );
  }

  /// An interrupted prompt may have been dispatched before its transcript was
  /// journaled. Never silently create a new session and resend the old goal.
  static Future<bool> hasPersistedSession(Directory sessionDir) async {
    if (!await sessionDir.exists()) return false;
    try {
      await for (final entity in sessionDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            entity.path.endsWith('.jsonl') &&
            await entity.length() > 0) {
          return true;
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }
}
