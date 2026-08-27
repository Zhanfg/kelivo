import '../agency/story_agency_policy.dart';

/// Minimal persistent state required to opt a conversation into Story Mode.
///
/// Large/dynamic story data (world tree, character registry, memory, timeline)
/// intentionally does not live here. Those subsystems get dedicated stores so
/// toggling Story Mode never mutates the existing Conversation schema.
final class StoryRuntimeSessionState {
  const StoryRuntimeSessionState({
    required this.conversationId,
    this.enabled = false,
    this.agencyMode = StoryAgencyMode.balanced,
    this.worldlineId,
    this.sceneEpochId,
    this.sceneRevision = 0,
    this.schemaVersion = currentSchemaVersion,
  }) : assert(conversationId != ''),
       assert(sceneRevision >= 0),
       assert(schemaVersion > 0);

  static const int currentSchemaVersion = 1;

  final String conversationId;
  final bool enabled;
  final StoryAgencyMode agencyMode;
  final String? worldlineId;
  final String? sceneEpochId;
  final int sceneRevision;
  final int schemaVersion;

  StoryRuntimeSessionState copyWith({
    bool? enabled,
    StoryAgencyMode? agencyMode,
    String? worldlineId,
    String? sceneEpochId,
    int? sceneRevision,
    bool clearWorldlineId = false,
    bool clearSceneEpochId = false,
  }) {
    return StoryRuntimeSessionState(
      conversationId: conversationId,
      enabled: enabled ?? this.enabled,
      agencyMode: agencyMode ?? this.agencyMode,
      worldlineId: clearWorldlineId ? null : (worldlineId ?? this.worldlineId),
      sceneEpochId: clearSceneEpochId
          ? null
          : (sceneEpochId ?? this.sceneEpochId),
      sceneRevision: sceneRevision ?? this.sceneRevision,
      schemaVersion: schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'conversation_id': conversationId,
    'enabled': enabled,
    'agency_mode': agencyMode.name,
    if (worldlineId != null) 'worldline_id': worldlineId,
    if (sceneEpochId != null) 'scene_epoch_id': sceneEpochId,
    'scene_revision': sceneRevision,
  };

  factory StoryRuntimeSessionState.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _readInt(json, 'schema_version', fallback: 1);
    if (schemaVersion > currentSchemaVersion || schemaVersion <= 0) {
      throw FormatException(
        'unsupported_story_runtime_session_schema:$schemaVersion',
      );
    }

    final conversationId = _readRequiredString(json, 'conversation_id');
    final agencyMode = _parseAgencyMode(json['agency_mode']);
    final sceneRevision = _readInt(json, 'scene_revision', fallback: 0);
    if (sceneRevision < 0) {
      throw const FormatException('invalid_story_scene_revision');
    }

    return StoryRuntimeSessionState(
      conversationId: conversationId,
      enabled: json['enabled'] == true,
      agencyMode: agencyMode,
      worldlineId: _readOptionalString(json['worldline_id']),
      sceneEpochId: _readOptionalString(json['scene_epoch_id']),
      sceneRevision: sceneRevision,
      schemaVersion: schemaVersion,
    );
  }
}

StoryAgencyMode _parseAgencyMode(Object? value) {
  if (value == null) return StoryAgencyMode.balanced;
  if (value is! String) {
    throw const FormatException('invalid_story_agency_mode');
  }
  return switch (value) {
    'manual' => StoryAgencyMode.manual,
    'balanced' => StoryAgencyMode.balanced,
    'cinematic' => StoryAgencyMode.cinematic,
    _ => throw FormatException('unknown_story_agency_mode:$value'),
  };
}

String _readRequiredString(Map<String, dynamic> json, String key) {
  final value = _readOptionalString(json[key]);
  if (value == null) throw FormatException('missing_story_$key');
  return value;
}

String? _readOptionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('invalid_story_optional_string');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _readInt(
  Map<String, dynamic> json,
  String key, {
  required int fallback,
}) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is! num || value.isNaN || value.isInfinite) {
    throw FormatException('invalid_story_$key');
  }
  return value.toInt();
}
