import '../../../core/models/memory_entry.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/memory_provider_v2.dart';
import '../../../core/services/skills/skills_service.dart';

class AgentSkillCapability {
  const AgentSkillCapability({
    required this.id,
    required this.name,
    required this.description,
    required this.directory,
  });

  final String id;
  final String name;
  final String description;

  /// Host-side persistent directory. Sandboxed runtimes see the same data via
  /// the existing read-only /skills mount; no second copy is created.
  final String directory;
}

class AgentMcpCapability {
  const AgentMcpCapability({
    required this.id,
    required this.name,
    required this.transport,
    required this.connected,
    required this.toolNames,
  });

  final String id;
  final String name;
  final McpTransportType transport;
  final bool connected;
  final List<String> toolNames;
}

class AgentContextSnapshot {
  const AgentContextSnapshot({
    required this.memories,
    required this.skills,
    required this.mcpServers,
  });

  /// The exact KELIVO Memory V2 entries visible to this assistant.
  final List<MemoryEntry> memories;

  /// Enabled KELIVO skills. Bodies remain in the shared persistent skills dir.
  final List<AgentSkillCapability> skills;

  /// Enabled MCP capabilities. Credentials and headers intentionally stay in
  /// the host-side McpProvider and are never copied into the Linux filesystem.
  final List<AgentMcpCapability> mcpServers;
}

/// Read-only projection of KELIVO-owned context into the Agent control plane.
///
/// KELIVO remains the source of truth. Pi/Linux consumers receive a snapshot
/// and use existing host services for writes or privileged operations.
class AgentContextBridge {
  const AgentContextBridge({
    required this.memory,
    required this.skills,
    required this.mcp,
  });

  final MemoryProviderV2 memory;
  final SkillsService skills;
  final McpProvider mcp;

  Future<AgentContextSnapshot> build({
    String? assistantId,
    Set<String>? skillIds,
    Set<String>? mcpServerIds,
  }) async {
    await Future.wait<void>([
      memory.initialize(assistantId: assistantId),
      skills.loaded,
      mcp.loaded,
    ]);

    final visibleMemories = List<MemoryEntry>.unmodifiable(
      memory.visibleFor(assistantId),
    );

    final visibleSkills = [
      for (final skill in skills.skills)
        if (skill.record.enabled &&
            (skillIds == null || skillIds.contains(skill.record.id)))
          AgentSkillCapability(
            id: skill.record.id,
            name: skill.name,
            description: skill.description,
            directory: skill.dir,
          ),
    ];

    final visibleMcp = [
      for (final server in mcp.servers)
        if (server.enabled &&
            (mcpServerIds == null || mcpServerIds.contains(server.id)))
          AgentMcpCapability(
            id: server.id,
            name: server.name,
            transport: server.transport,
            connected: mcp.isConnected(server.id),
            toolNames: List<String>.unmodifiable([
              for (final tool in server.tools)
                if (tool.enabled) tool.name,
            ]),
          ),
    ];

    return AgentContextSnapshot(
      memories: visibleMemories,
      skills: List<AgentSkillCapability>.unmodifiable(visibleSkills),
      mcpServers: List<AgentMcpCapability>.unmodifiable(visibleMcp),
    );
  }
}
