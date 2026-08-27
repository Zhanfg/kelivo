import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Cache-stable capability snapshot for one Story Runtime epoch.
///
/// A capability epoch should roll only when a meaningful boundary changes the
/// model-visible capability set (scene/skill/tool/world-book snapshot), never
/// merely because a Map/Set happened to iterate in a different order.
final class StoryCapabilityEpoch {
  StoryCapabilityEpoch._({
    required this.epochId,
    required this.worldlineId,
    required this.sceneEpochId,
    required this.activeSkillIds,
    required this.toolIds,
    required this.mcpProfileId,
    required this.worldBookSnapshotId,
    required this.toolSchemaFingerprint,
  });

  factory StoryCapabilityEpoch.canonical({
    required String epochId,
    required String worldlineId,
    required String sceneEpochId,
    Iterable<String> activeSkillIds = const <String>[],
    Iterable<String> toolIds = const <String>[],
    String? mcpProfileId,
    String? worldBookSnapshotId,
    String? toolSchemaFingerprint,
  }) {
    return StoryCapabilityEpoch._(
      epochId: _requiredId(epochId, 'epochId'),
      worldlineId: _requiredId(worldlineId, 'worldlineId'),
      sceneEpochId: _requiredId(sceneEpochId, 'sceneEpochId'),
      activeSkillIds: _canonicalIds(activeSkillIds, 'activeSkillIds'),
      toolIds: _canonicalIds(toolIds, 'toolIds'),
      mcpProfileId: _optionalId(mcpProfileId),
      worldBookSnapshotId: _optionalId(worldBookSnapshotId),
      toolSchemaFingerprint: _optionalId(toolSchemaFingerprint),
    );
  }

  final String epochId;
  final String worldlineId;
  final String sceneEpochId;
  final List<String> activeSkillIds;
  final List<String> toolIds;
  final String? mcpProfileId;
  final String? worldBookSnapshotId;

  /// Hash of the canonical provider-visible tool definitions. Tool ids alone
  /// are insufficient because a schema mutation under the same id must roll
  /// the cache epoch.
  final String? toolSchemaFingerprint;

  /// Deterministic fingerprint of everything that can change the capability
  /// prefix. [epochId] is intentionally excluded: two epochs with identical
  /// model-visible capability state may reuse the same provider prefix.
  String get stableFingerprint {
    final payload = jsonEncode(<String, Object?>{
      'worldline_id': worldlineId,
      'scene_epoch_id': sceneEpochId,
      'skills': activeSkillIds,
      'mcp_profile_id': mcpProfileId,
      'tools': toolIds,
      'tool_schema_fingerprint': toolSchemaFingerprint,
      'world_book_snapshot_id': worldBookSnapshotId,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  bool canReuseStablePrefixWith(StoryCapabilityEpoch other) =>
      stableFingerprint == other.stableFingerprint;

  Map<String, Object?> toDiagnosticJson() => <String, Object?>{
    'epoch_id': epochId,
    'worldline_id': worldlineId,
    'scene_epoch_id': sceneEpochId,
    'skills': activeSkillIds,
    'mcp_profile_id': mcpProfileId,
    'tools': toolIds,
    'tool_schema_fingerprint': toolSchemaFingerprint,
    'world_book_snapshot_id': worldBookSnapshotId,
    'stable_fingerprint': stableFingerprint,
  };
}

List<String> _canonicalIds(Iterable<String> values, String field) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(raw, field, 'ids must be non-empty');
    }
    if (!seen.add(value)) {
      throw ArgumentError.value(value, field, 'duplicate id');
    }
    normalized.add(value);
  }
  normalized.sort();
  return List.unmodifiable(normalized);
}

String _requiredId(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, field, 'must be non-empty');
  }
  return normalized;
}

String? _optionalId(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
