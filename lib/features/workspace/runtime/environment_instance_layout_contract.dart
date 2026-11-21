/// #52 Instance isolation and snapshot-reference contract (no disk mutation).
/// No real rootfs migration, upgrades or rollback happen in this module.
enum EnvironmentInstancePhase { stopped, running, upgrading, failed }

final class EnvironmentInstanceLayout {
  EnvironmentInstanceLayout({
    required this.instanceId,
    required this.distribution,
    required this.release,
  }) {
    final id = RegExp(r'^[a-z][a-z0-9_-]{2,63}$');
    final version = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.+-]{0,63}$');
    if (!id.hasMatch(instanceId) ||
        !id.hasMatch(distribution) ||
        !version.hasMatch(release)) {
      throw ArgumentError('Invalid instance identity');
    }
  }

  final String instanceId;
  final String distribution;
  final String release;

  /// Relative logical names only; path resolution remains with the owner.
  String get rootfsKey => 'instances/$instanceId/rootfs';
  String get snapshotIndexKey => 'instances/$instanceId/snapshots';
}

final class EnvironmentSnapshotReference {
  EnvironmentSnapshotReference({
    required this.id,
    required this.instanceId,
    required this.sourceRelease,
    required this.contentDigest,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{3,64}$').hasMatch(id) ||
        !RegExp(r'^[a-z][a-z0-9_-]{2,63}$').hasMatch(instanceId) ||
        !RegExp(
          r'^[a-zA-Z0-9][a-zA-Z0-9_.+-]{0,63}$',
        ).hasMatch(sourceRelease) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(contentDigest)) {
      throw ArgumentError('Invalid snapshot reference');
    }
  }
  final String id;
  final String instanceId;
  final String sourceRelease;
  final String contentDigest;

  bool belongsTo(EnvironmentInstanceLayout layout) =>
      instanceId == layout.instanceId && sourceRelease == layout.release;
}

final class EnvironmentInstanceCatalog {
  EnvironmentInstanceCatalog(Iterable<EnvironmentInstanceLayout> layouts)
    : instances = Map.unmodifiable({
        for (final layout in layouts) layout.instanceId: layout,
      }) {
    final input = layouts.toList();
    if (input.isEmpty || input.length != instances.length) {
      throw ArgumentError('Missing or duplicate instance');
    }
  }

  final Map<String, EnvironmentInstanceLayout> instances;
  bool canRestore(String instanceId, EnvironmentSnapshotReference snapshot) {
    final instance = instances[instanceId];
    return instance != null && snapshot.belongsTo(instance);
  }
}
