import 'dart:convert';

import 'story_skill_models.dart';

/// Strict v1 parser for `manifest.json` inside a Story Skill package.
final class StorySkillManifestParser {
  const StorySkillManifestParser();

  StorySkillManifest parse(String raw) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw StorySkillManifestException('invalid_json', detail: error.message);
    }
    if (decoded is! Map) {
      throw const StorySkillManifestException('root_not_object');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    final schemaVersion = _int(json['schema_version'], fallback: 1);
    if (schemaVersion != 1) {
      throw StorySkillManifestException(
        'unsupported_schema',
        detail: '$schemaVersion',
      );
    }

    final activation = _map(json['activation']);
    final memory = _map(json['memory']);
    final tts = _map(json['tts']);
    final compatibility = _map(json['compatibility']);

    final manifest = StorySkillManifest(
      id: _requiredId(json, 'id'),
      name: _requiredString(json, 'name'),
      version: _requiredString(json, 'version'),
      description: _string(json['description']) ?? '',
      instructions: _stringList(json['instructions']),
      worldBookIds: _idList(json['worldbooks']),
      mcpServerIds: _idList(json['mcp_servers']),
      toolIds: _idList(json['tools']),
      memoryReadCategories: _idList(memory['read_categories']),
      memoryWriteCategories: _idList(memory['write_categories']),
      ttsPolicy: _ttsPolicy(tts['policy']),
      activationModes: _activationModes(activation['modes']),
      activationSceneTags: _idList(activation['scene_tags']).toSet(),
      activationConditionIds: _idList(activation['condition_ids']).toSet(),
      permissions: _permissions(json['permissions']),
      hooks: _hooks(json['hooks']),
      compatibility: StorySkillCompatibility(
        minKelivoVersion: _string(compatibility['min_kelivo_version']),
        maxKelivoVersion: _string(compatibility['max_kelivo_version']),
        minStoryProtocol: _int(
          compatibility['min_story_protocol'],
          fallback: 1,
        ),
        platforms: _idList(compatibility['platforms']).toSet(),
      ),
      assets: _pathList(json['assets']),
      templates: _pathList(json['templates']),
      metadata: Map.unmodifiable(_map(json['metadata'])),
    );

    _validatePermissionClosure(manifest);
    return manifest;
  }
}

final class StorySkillManifestException implements Exception {
  const StorySkillManifestException(this.code, {this.detail});

  final String code;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StorySkillManifestException($code)'
      : 'StorySkillManifestException($code: $detail)';
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _string(json[key]);
  if (value == null) throw StorySkillManifestException('missing_$key');
  return value;
}

String _requiredId(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^[a-zA-Z0-9._-]{1,96}$').hasMatch(value)) {
    throw StorySkillManifestException('invalid_$key', detail: value);
  }
  return value;
}

String? _string(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const StorySkillManifestException('invalid_string');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? value, {required int fallback}) {
  if (value == null) return fallback;
  if (value is! num || value.isNaN || value.isInfinite || value % 1 != 0) {
    throw const StorySkillManifestException('invalid_integer');
  }
  return value.toInt();
}

Map<String, Object?> _map(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is! Map) throw const StorySkillManifestException('invalid_object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<String> _stringList(Object? value) {
  if (value == null) return const <String>[];
  if (value is! List) throw const StorySkillManifestException('invalid_list');
  return List.unmodifiable([
    for (final item in value)
      if (_string(item) case final String text) text,
  ]);
}

List<String> _idList(Object? value) {
  final values = _stringList(value);
  final seen = <String>{};
  for (final item in values) {
    if (!RegExp(r'^[a-zA-Z0-9._:/-]{1,160}$').hasMatch(item)) {
      throw StorySkillManifestException('invalid_identifier', detail: item);
    }
    if (!seen.add(item)) {
      throw StorySkillManifestException('duplicate_identifier', detail: item);
    }
  }
  return values;
}

List<String> _pathList(Object? value) {
  final values = _stringList(value);
  for (final item in values) {
    if (item.startsWith('/') || item.contains('..') || item.contains('\\')) {
      throw StorySkillManifestException('unsafe_package_path', detail: item);
    }
  }
  return values;
}

Set<StorySkillActivationMode> _activationModes(Object? value) {
  final values = _stringList(value);
  if (values.isEmpty) return const {StorySkillActivationMode.manual};
  return {
    for (final item in values)
      switch (item) {
        'manual' => StorySkillActivationMode.manual,
        'always' => StorySkillActivationMode.always,
        'scene_tag' => StorySkillActivationMode.sceneTag,
        'condition' => StorySkillActivationMode.condition,
        'director' => StorySkillActivationMode.director,
        'serial_due' => StorySkillActivationMode.serialDue,
        _ => throw StorySkillManifestException(
          'unknown_activation_mode',
          detail: item,
        ),
      },
  };
}

Set<StorySkillPermission> _permissions(Object? value) => {
  for (final item in _stringList(value))
    switch (item) {
      'memory_read' => StorySkillPermission.memoryRead,
      'memory_write' => StorySkillPermission.memoryWrite,
      'mcp' => StorySkillPermission.mcp,
      'local_tools' => StorySkillPermission.localTools,
      'network' => StorySkillPermission.network,
      'filesystem_read' => StorySkillPermission.filesystemRead,
      'filesystem_write' => StorySkillPermission.filesystemWrite,
      'tts' => StorySkillPermission.tts,
      _ => throw StorySkillManifestException(
        'unknown_permission',
        detail: item,
      ),
    },
};

StorySkillTtsPolicy _ttsPolicy(Object? value) {
  final policy = _string(value);
  return switch (policy) {
    null || 'inherit' => StorySkillTtsPolicy.inherit,
    'prefer_enabled' => StorySkillTtsPolicy.preferEnabled,
    'disabled' => StorySkillTtsPolicy.disabled,
    _ => throw StorySkillManifestException(
      'unknown_tts_policy',
      detail: policy,
    ),
  };
}

List<StorySkillHook> _hooks(Object? value) {
  if (value == null) return const <StorySkillHook>[];
  if (value is! List) throw const StorySkillManifestException('invalid_hooks');
  return List.unmodifiable([
    for (final item in value)
      () {
        final map = _map(item);
        return StorySkillHook(
          event: _requiredString(map, 'event'),
          handler: _requiredString(map, 'handler'),
          localOnly: map['local_only'] != false,
        );
      }(),
  ]);
}

void _validatePermissionClosure(StorySkillManifest manifest) {
  if (manifest.mcpServerIds.isNotEmpty &&
      !manifest.permissions.contains(StorySkillPermission.mcp)) {
    throw const StorySkillManifestException('mcp_permission_required');
  }
  if (manifest.toolIds.isNotEmpty &&
      !manifest.permissions.contains(StorySkillPermission.localTools) &&
      !manifest.permissions.contains(StorySkillPermission.mcp)) {
    throw const StorySkillManifestException('tool_permission_required');
  }
  if (manifest.memoryReadCategories.isNotEmpty &&
      !manifest.permissions.contains(StorySkillPermission.memoryRead)) {
    throw const StorySkillManifestException('memory_read_permission_required');
  }
  if (manifest.memoryWriteCategories.isNotEmpty &&
      !manifest.permissions.contains(StorySkillPermission.memoryWrite)) {
    throw const StorySkillManifestException('memory_write_permission_required');
  }
  if (manifest.ttsPolicy != StorySkillTtsPolicy.inherit &&
      !manifest.permissions.contains(StorySkillPermission.tts)) {
    throw const StorySkillManifestException('tts_permission_required');
  }
  if (manifest.hooks.any((hook) => !hook.localOnly)) {
    throw const StorySkillManifestException('remote_hooks_not_supported');
  }
}
