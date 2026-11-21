/// #35 Immutable, deterministic non-Agent workflow admission policy.
/// Does not execute jobs or modify the shared Job Registry.
enum DagDependencyResult { pending, success, failed, unknown }

enum DagNodeAdmission { ready, blocked, failed, reviewRequired }

final class DagJobNode {
  DagJobNode({required this.id, Iterable<String> dependsOn = const []})
    : dependsOn = Set.unmodifiable(dependsOn) {
    if (!_safe.hasMatch(id) ||
        this.dependsOn.contains(id) ||
        this.dependsOn.any((part) => !_safe.hasMatch(part))) {
      throw ArgumentError('Invalid DAG node or self-dependency');
    }
  }

  static final RegExp _safe = RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,63}$');
  final String id;
  final Set<String> dependsOn;
}

final class JobDagAdmissionPolicy {
  JobDagAdmissionPolicy(Iterable<DagJobNode> nodes)
    : nodes = Map.unmodifiable({for (final n in nodes) n.id: n}) {
    final list = nodes.toList();
    if (list.isEmpty || list.length != this.nodes.length || list.length > 256) {
      throw ArgumentError('Empty, duplicated or oversized DAG');
    }
    if (list.any((n) => !n.dependsOn.every(this.nodes.containsKey))) {
      throw ArgumentError('Missing upstream dependency');
    }
    final marks = <String, int>{};
    void visit(String id) {
      if (marks[id] == 1) throw ArgumentError('Cyclic workflow');
      if (marks[id] == 2) return;
      marks[id] = 1;
      for (final dep in this.nodes[id]!.dependsOn) {
        visit(dep);
      }
      marks[id] = 2;
    }

    for (final id in this.nodes.keys) {
      visit(id);
    }
  }

  final Map<String, DagJobNode> nodes;

  DagNodeAdmission admission(
    String id,
    Map<String, DagDependencyResult> outcomes,
  ) {
    final node = nodes[id];
    if (node == null) throw ArgumentError('Unknown DAG node');
    final dependencies = node.dependsOn.map(
      (d) => outcomes[d] ?? DagDependencyResult.unknown,
    );
    if (dependencies.any((v) => v == DagDependencyResult.failed)) {
      return DagNodeAdmission.failed;
    }
    if (dependencies.any((v) => v == DagDependencyResult.unknown)) {
      return DagNodeAdmission.reviewRequired;
    }
    if (dependencies.any((v) => v == DagDependencyResult.pending)) {
      return DagNodeAdmission.blocked;
    }
    return DagNodeAdmission.ready;
  }
}
