import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../utils/app_directories.dart';

enum AgentTaskEventKind {
  phaseChanged,
  planUpdated,
  toolStarted,
  toolFinished,
  approvalRequested,
  approvalResolved,
  checkpoint,
  artifact,
  environmentMutation,
  assistantMessage,
  turnStarted,
  turnFinished,
  toolProgress,
  queueChanged,
  subagentLifecycle,
  subagentProgress,
  subagentEvent,
  retry,
  compaction,
  notice,
  note,
}

class AgentTaskEvent {
  const AgentTaskEvent({
    required this.id,
    required this.taskId,
    required this.kind,
    required this.createdAt,
    this.payload = const <String, dynamic>{},
  });

  final String id;
  final String taskId;
  final AgentTaskEventKind kind;
  final DateTime createdAt;

  /// Structured, already-redacted metadata. Secrets and raw credentials must
  /// never be written to the durable journal.
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'taskId': taskId,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'payload': payload,
  };

  factory AgentTaskEvent.fromJson(Map<String, dynamic> json) {
    return AgentTaskEvent(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      kind: AgentTaskEventKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => AgentTaskEventKind.note,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      payload:
          (json['payload'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}

/// Crash-tolerant append-only journal for Agent task control-plane events.
///
/// The journal is not the source of project files or Linux environment state.
/// It records enough durable metadata to recover orchestration after process
/// death and to build a user-facing Activity timeline.
class AgentTaskJournal extends ChangeNotifier {
  AgentTaskJournal({Directory? rootDirectory})
    : _injectedRootDirectory = rootDirectory;

  final Directory? _injectedRootDirectory;
  Future<void> _writeTail = Future<void>.value();

  Future<AgentTaskEvent> append(
    String taskId,
    AgentTaskEventKind kind, {
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    late AgentTaskEvent event;
    final operation = _writeTail.then((_) async {
      event = AgentTaskEvent(
        id: const Uuid().v4(),
        taskId: taskId,
        kind: kind,
        createdAt: DateTime.now().toUtc(),
        payload: Map<String, dynamic>.unmodifiable(payload),
      );
      final file = await _journalFile(taskId);
      final sink = file.openWrite(mode: FileMode.append);
      try {
        sink.writeln(jsonEncode(event.toJson()));
        await sink.flush();
      } finally {
        await sink.close();
      }
      notifyListeners();
    });
    _writeTail = operation.catchError((Object _) {});
    return operation.then((_) => event);
  }

  Future<List<AgentTaskEvent>> read(String taskId) async {
    await _writeTail;
    final file = await _journalFile(taskId, create: false);
    if (!await file.exists()) return const <AgentTaskEvent>[];

    final events = <AgentTaskEvent>[];
    final lines = const LineSplitter().convert(await file.readAsString());
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final event = AgentTaskEvent.fromJson(decoded.cast<String, dynamic>());
        if (event.taskId == taskId) events.add(event);
      } catch (_) {
        // A process may die while appending the final line. Earlier committed
        // lines remain valid and recovery should continue from them.
      }
    }
    return List<AgentTaskEvent>.unmodifiable(events);
  }

  Future<File> _journalFile(String taskId, {bool create = true}) async {
    final root =
        _injectedRootDirectory ?? await AppDirectories.getAgentTasksDirectory();
    final dir = Directory('${root.path}/$taskId');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/journal.ndjson');
  }
}
