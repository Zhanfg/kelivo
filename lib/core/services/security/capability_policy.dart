/// Immutable per-task authorization contract. No OS permission changes.
library;

import '../capabilities/capability_report.dart';

class CapabilityPolicy {
  CapabilityPolicy({
    required this.taskId,
    required Iterable<String> allowed,
    Iterable<String> revoked = const <String>[],
  }) : allowed = Set<String>.unmodifiable(allowed.map(_validId)),
       revoked = Set<String>.unmodifiable(revoked.map(_validId)) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(taskId)) {
      throw const FormatException('invalid task id');
    }
  }

  final String taskId;
  final Set<String> allowed;
  final Set<String> revoked;

  /// Missing authorization or unavailable device capability always denies.
  bool permits(String id, CapabilityReport report) =>
      allowed.contains(id) &&
      !revoked.contains(id) &&
      report[id]?.availability == CapabilityAvailability.available;

  CapabilityPolicy revoke(String id) => CapabilityPolicy(
    taskId: taskId,
    allowed: allowed,
    revoked: {...revoked, _validId(id)},
  );

  /// Child may receive only non-revoked permissions from its parent.
  CapabilityPolicy deriveChild(String childTaskId, Iterable<String> requested) {
    final ids = requested.map(_validId).toSet();
    return CapabilityPolicy(
      taskId: childTaskId,
      allowed: allowed.intersection(ids).difference(revoked),
    );
  }

  /// Audit metadata deliberately excludes capability details and secrets.
  Map<String, Object> auditSummary() => {
    'taskId': taskId,
    'allowedCount': allowed.length,
    'revokedCount': revoked.length,
  };
}

String _validId(String id) {
  if (id.length > capabilityIdMaxLength ||
      !RegExp(r'^[a-z0-9]+(?:[.-][a-z0-9]+)*$').hasMatch(id)) {
    throw const FormatException('invalid capability id');
  }
  return id;
}
