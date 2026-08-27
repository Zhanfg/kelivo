import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/database/business_preferences.dart';
import '../orchestration/story_break_armor_mode.dart';

final class StorySerializationBundle {
  const StorySerializationBundle({
    required this.schemaVersion,
    required this.createdAt,
    required this.blobs,
    required this.settings,
    required this.contentSha256,
  });

  static const String format = 'kelivo-story-bundle';
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime createdAt;
  final Map<String, List<Object?>> blobs;
  final Map<String, Object?> settings;
  final String contentSha256;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': format,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'blobs': blobs,
    'settings': settings,
    'contentSha256': contentSha256,
  };
}

final class StorySerializationRestoreReport {
  const StorySerializationRestoreReport({
    required this.restoredBlobKeys,
    required this.restoredSettingKeys,
    required this.contentSha256,
  });

  final List<String> restoredBlobKeys;
  final List<String> restoredSettingKeys;
  final String contentSha256;
}

/// Versioned, secret-free Story state export used by local backup and the
/// GitHub Serialization Skill.
///
/// The bundle snapshots Story-owned JSON blobs only. Provider credentials,
/// generic Kelivo settings, MCP OAuth state and TTS API keys are deliberately
/// excluded. Voice assignments contain only existing TTS service ids.
final class StorySerializationService {
  StorySerializationService(this.preferences);

  final BusinessPreferences preferences;

  static const int maxBundleChars = 32 * 1024 * 1024;

  static const Set<String> storyBlobKeys = <String>{
    'story_runtime_sessions_v1',
    'story_runtime_execution_v1',
    'story_scene_runtime_v1',
    'story_world_trees_v1',
    'story_worldline_memory_v1',
    'story_skill_bindings_v1',
    'story_skill_packages_v1',
    'story_reference_documents_v1',
    'story_reference_profiles_v1',
    'story_reference_selections_v1',
    'story_mcp_profiles_v1',
    'story_mcp_profile_selections_v1',
    'story_voice_routing_v1',
  };

  Future<StorySerializationBundle> exportBundle() async {
    await preferences.load();
    final blobs = <String, List<Object?>>{};
    final keys = storyBlobKeys.toList()..sort();
    for (final key in keys) {
      final raw = preferences.getString(key);
      if (raw == null || raw.trim().isEmpty) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw StateError('story_serialization_invalid_blob:$key');
      }
      blobs[key] = List<Object?>.from(decoded);
    }
    final settings = <String, Object?>{
      storyBreakArmorEnabledKey:
          preferences.getBool(storyBreakArmorEnabledKey) ?? false,
    };
    final createdAt = DateTime.now().toUtc();
    final digest = _contentDigest(
      schemaVersion: StorySerializationBundle.currentSchemaVersion,
      blobs: blobs,
      settings: settings,
    );
    return StorySerializationBundle(
      schemaVersion: StorySerializationBundle.currentSchemaVersion,
      createdAt: createdAt,
      blobs: Map.unmodifiable(blobs),
      settings: Map.unmodifiable(settings),
      contentSha256: digest,
    );
  }

  Future<String> exportJson({bool pretty = true}) async {
    final bundle = await exportBundle();
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : jsonEncode;
    if (encoder is JsonEncoder) return encoder.convert(bundle.toJson());
    return jsonEncode(bundle.toJson());
  }

  StorySerializationBundle decodeAndValidate(String encoded) {
    if (encoded.length > maxBundleChars) {
      throw const FormatException('story_bundle_too_large');
    }
    final raw = jsonDecode(encoded);
    if (raw is! Map) throw const FormatException('invalid_story_bundle_root');
    final json = Map<String, dynamic>.from(raw);
    if (json['format'] != StorySerializationBundle.format) {
      throw const FormatException('invalid_story_bundle_format');
    }
    final schemaVersion = (json['schemaVersion'] as num?)?.toInt();
    if (schemaVersion == null ||
        schemaVersion <= 0 ||
        schemaVersion > StorySerializationBundle.currentSchemaVersion) {
      throw FormatException('unsupported_story_bundle_schema:$schemaVersion');
    }
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw is! String) {
      throw const FormatException('invalid_story_bundle_created_at');
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw const FormatException('invalid_story_bundle_created_at');
    }

    final blobsRaw = json['blobs'];
    if (blobsRaw is! Map) {
      throw const FormatException('invalid_story_bundle_blobs');
    }
    final blobs = <String, List<Object?>>{};
    for (final entry in blobsRaw.entries) {
      final key = entry.key.toString();
      if (!storyBlobKeys.contains(key)) {
        throw FormatException('unknown_story_bundle_blob:$key');
      }
      final value = entry.value;
      if (value is! List) {
        throw FormatException('invalid_story_bundle_blob:$key');
      }
      blobs[key] = List<Object?>.from(value);
    }

    final settingsRaw = json['settings'];
    if (settingsRaw is! Map) {
      throw const FormatException('invalid_story_bundle_settings');
    }
    final settings = Map<String, Object?>.from(settingsRaw);
    for (final key in settings.keys) {
      if (key != storyBreakArmorEnabledKey) {
        throw FormatException('unknown_story_bundle_setting:$key');
      }
    }
    final breakArmor = settings[storyBreakArmorEnabledKey];
    if (breakArmor != null && breakArmor is! bool) {
      throw const FormatException('invalid_story_break_armor_setting');
    }

    final expected = _contentDigest(
      schemaVersion: schemaVersion,
      blobs: blobs,
      settings: settings,
    );
    final supplied = (json['contentSha256'] ?? '').toString().trim();
    if (supplied.isEmpty || supplied != expected) {
      throw const FormatException('story_bundle_checksum_mismatch');
    }

    return StorySerializationBundle(
      schemaVersion: schemaVersion,
      createdAt: createdAt.toUtc(),
      blobs: Map.unmodifiable(blobs),
      settings: Map.unmodifiable(settings),
      contentSha256: expected,
    );
  }

  /// Restores only keys carried by the bundle. Missing keys are preserved.
  ///
  /// This makes partial Git-backed snapshots safe to apply without silently
  /// deleting newer Story subsystems that an older bundle did not know about.
  Future<StorySerializationRestoreReport> restoreJson(String encoded) async {
    final bundle = decodeAndValidate(encoded);
    await preferences.load();
    final restoredBlobs = <String>[];
    final blobKeys = bundle.blobs.keys.toList()..sort();
    for (final key in blobKeys) {
      await preferences.setString(key, jsonEncode(bundle.blobs[key]));
      restoredBlobs.add(key);
    }
    final restoredSettings = <String>[];
    if (bundle.settings.containsKey(storyBreakArmorEnabledKey)) {
      await preferences.setBool(
        storyBreakArmorEnabledKey,
        bundle.settings[storyBreakArmorEnabledKey] == true,
      );
      restoredSettings.add(storyBreakArmorEnabledKey);
    }
    return StorySerializationRestoreReport(
      restoredBlobKeys: List.unmodifiable(restoredBlobs),
      restoredSettingKeys: List.unmodifiable(restoredSettings),
      contentSha256: bundle.contentSha256,
    );
  }
}

String _contentDigest({
  required int schemaVersion,
  required Map<String, List<Object?>> blobs,
  required Map<String, Object?> settings,
}) {
  final orderedBlobs = <String, Object?>{};
  final blobKeys = blobs.keys.toList()..sort();
  for (final key in blobKeys) {
    orderedBlobs[key] = blobs[key];
  }
  final orderedSettings = <String, Object?>{};
  final settingKeys = settings.keys.toList()..sort();
  for (final key in settingKeys) {
    orderedSettings[key] = settings[key];
  }
  final canonical = jsonEncode(<String, Object?>{
    'format': StorySerializationBundle.format,
    'schemaVersion': schemaVersion,
    'blobs': orderedBlobs,
    'settings': orderedSettings,
  });
  return sha256.convert(utf8.encode(canonical)).toString();
}
