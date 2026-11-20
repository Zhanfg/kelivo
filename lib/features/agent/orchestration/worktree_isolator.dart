/// Read-only worktree ownership and merge-conflict preflight contract.
///
/// No git command or filesystem mutation is performed by this service.
/// Actual creation and merge operations belong to the authorized host.
final class AgentWorktreeLease {
  AgentWorktreeLease({
    required this.agentId,
    required this.branch,
    required this.worktreePath,
    required this.baseSha,
    required Iterable<String> ownedFiles,
  }) : ownedFiles = Set.unmodifiable(ownedFiles) {
    _validateId(agentId);
    _validateId(branch);
    if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(baseSha)) {
      throw ArgumentError('Invalid pinned base SHA');
    }
    if (!worktreePath.startsWith('/') ||
        worktreePath.contains('..') ||
        worktreePath.contains('\\') ||
        worktreePath.contains('//')) {
      throw ArgumentError('Unsafe worktree path');
    }
    if (this.ownedFiles.isEmpty) throw ArgumentError('Empty ownership set');
    for (final path in this.ownedFiles) {
      if (path.isEmpty ||
          path.startsWith('/') ||
          path.contains('..') ||
          path.contains('\\') ||
          path.contains('//')) {
        throw ArgumentError('Unsafe ownership path');
      }
    }
  }

  final String agentId;
  final String branch;
  final String worktreePath;
  final String baseSha;
  final Set<String> ownedFiles;

  static void _validateId(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_.:/-]{1,160}$').hasMatch(value) ||
        value.contains('..') ||
        value.startsWith('/') ||
        value.endsWith('/')) {
      throw ArgumentError('Invalid worktree reference');
    }
  }
}

final class WorktreeConflictReport {
  WorktreeConflictReport(Set<String> conflicts, Set<String> outsideOwnership)
    : conflicts = Set.unmodifiable(conflicts),
      outsideOwnership = Set.unmodifiable(outsideOwnership);

  final Set<String> conflicts;
  final Set<String> outsideOwnership;
  bool get canIntegrate => conflicts.isEmpty && outsideOwnership.isEmpty;
}

/// Non-overlapping, uniquely named leases; no implicit conflict resolution.
final class AgentWorktreeIsolator {
  final Map<String, AgentWorktreeLease> _leases = {};

  void register(AgentWorktreeLease lease) {
    if (_leases.containsKey(lease.agentId) ||
        _leases.values.any(
          (item) =>
              item.branch == lease.branch ||
              item.worktreePath == lease.worktreePath,
        )) {
      throw StateError('Worktree or branch already leased');
    }
    if (_leases.values.any((item) => item.baseSha != lease.baseSha)) {
      throw StateError('Mixed baselines require revalidation');
    }
    _leases[lease.agentId] = lease;
  }

  void release(String agentId) {
    if (_leases.remove(agentId) == null) throw StateError('Unknown lease');
  }

  WorktreeConflictReport inspect(
    String agentId, {
    required Iterable<String> changedFiles,
    required Iterable<String> integrationChangedFiles,
  }) {
    final lease = _leases[agentId];
    if (lease == null) throw StateError('Unregistered agent');
    final changed = changedFiles.toSet();
    final external = integrationChangedFiles.toSet();
    final ownedByOthers = <String>{};
    for (final entry in _leases.entries) {
      if (entry.key != agentId) ownedByOthers.addAll(entry.value.ownedFiles);
    }
    return WorktreeConflictReport(
      changed.intersection(external).union(changed.intersection(ownedByOthers)),
      changed.difference(lease.ownedFiles),
    );
  }
}
