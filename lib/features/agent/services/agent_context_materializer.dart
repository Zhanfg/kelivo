import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';
import 'agent_context_bridge.dart';

class AgentMaterializedContext {
  const AgentMaterializedContext({
    required this.hostPromptFile,
    required this.guestPromptFile,
    required this.skillMounts,
  });

  final String hostPromptFile;
  final String guestPromptFile;
  final List<AgentSkillMount> skillMounts;
}

class AgentSkillMount {
  const AgentSkillMount({
    required this.hostDirectory,
    required this.guestDirectory,
  });

  final String hostDirectory;
  final String guestDirectory;
}

/// Converts KELIVO-owned context into a task-local, secret-free view for Pi.
///
/// The generated file is disposable/rebuildable because KELIVO Memory V2 and
/// the extension registry remain authoritative.
class AgentContextMaterializer {
  const AgentContextMaterializer({required this.bridge});

  static const String guestTaskRoot = '/kelivo-agent-task';

  final AgentContextBridge bridge;

  Future<AgentMaterializedContext> materialize({
    required String taskId,
    String? assistantId,
    Set<String>? skillIds,
    Set<String>? mcpServerIds,
  }) async {
    final snapshot = await bridge.build(
      assistantId: assistantId,
      skillIds: skillIds,
      mcpServerIds: mcpServerIds,
    );
    final taskDir = await AppDirectories.agentTaskDir(taskId);
    final contextDir = Directory(p.join(taskDir.path, 'context'));
    await contextDir.create(recursive: true);

    final promptFile = File(p.join(contextDir.path, 'KELIVO_CONTEXT.md'));
    await promptFile.writeAsString(_render(snapshot), flush: true);

    final skillMounts = <AgentSkillMount>[
      for (final skill in snapshot.skills)
        AgentSkillMount(
          hostDirectory: skill.directory,
          guestDirectory: '/kelivo-skills/${_safeSegment(skill.id)}',
        ),
    ];

    return AgentMaterializedContext(
      hostPromptFile: promptFile.path,
      guestPromptFile: '$guestTaskRoot/context/KELIVO_CONTEXT.md',
      skillMounts: List<AgentSkillMount>.unmodifiable(skillMounts),
    );
  }

  String _render(AgentContextSnapshot snapshot) {
    final out = StringBuffer()
      ..writeln('# KELIVO Shared Context')
      ..writeln()
      ..writeln(
        'This context is supplied by KELIVO. KELIVO remains the source of '
        'truth for memory, permissions, secrets, extensions, and task state.',
      )
      ..writeln();

    final activeMemories = snapshot.memories
        .where((memory) => memory.status.name == 'active')
        .toList(growable: false);
    if (activeMemories.isNotEmpty) {
      out
        ..writeln('## Shared memory')
        ..writeln();
      for (final memory in activeMemories) {
        final content = memory.content.trim();
        if (content.isEmpty) continue;
        out.writeln('- [${memory.type.name}] $content');
      }
      out.writeln();
    }

    if (snapshot.mcpServers.isNotEmpty) {
      out
        ..writeln('## KELIVO host capabilities')
        ..writeln()
        ..writeln(
          'The following MCP registrations belong to KELIVO Host. Do not '
          'assume they are shell commands or directly callable Pi tools unless '
          'KELIVO exposes a corresponding tool bridge in this session.',
        )
        ..writeln();
      for (final server in snapshot.mcpServers) {
        final tools = server.toolNames.isEmpty
            ? 'no enabled tools'
            : server.toolNames.join(', ');
        out.writeln(
          '- ${server.name}: ${server.connected ? 'connected' : 'disconnected'}; '
          '$tools',
        );
      }
      out.writeln();
    }

    out
      ..writeln('## Runtime boundary')
      ..writeln()
      ..writeln('- /workspace is the persistent KELIVO project workspace.')
      ..writeln(
        '- KELIVO-managed memory and credentials must not be copied into '
        'project files.',
      )
      ..writeln(
        '- Task scratch data belongs under /kelivo-agent-task, not /workspace.',
      );

    return out.toString();
  }

  static String _safeSegment(String value) {
    final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return normalized.isEmpty ? 'skill' : normalized;
  }
}
