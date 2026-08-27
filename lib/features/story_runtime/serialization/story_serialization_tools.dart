import '../../../core/database/business_preferences.dart';
import 'story_serialization_service.dart';

final class StorySerializationTools {
  const StorySerializationTools._();

  static const String exportBundle = 'story_export_bundle';
  static const String restoreBundle = 'story_restore_bundle';
  static const Set<String> names = <String>{exportBundle, restoreBundle};

  static List<Map<String, dynamic>> definitions() => <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': exportBundle,
        'description':
            'Export the current Kelivo Story Runtime state as a versioned, checksum-protected, secret-free JSON bundle.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
          'additionalProperties': false,
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': restoreBundle,
        'description':
            'Restore Story Runtime state from a validated Kelivo Story bundle. This changes local Story data and requires host approval.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'bundle': <String, dynamic>{
              'type': 'string',
              'description': 'Complete kelivo-story-bundle JSON text.',
            },
          },
          'required': <String>['bundle'],
          'additionalProperties': false,
        },
      },
    },
  ];

  static Future<String?> tryHandle({
    required String name,
    required Map<String, dynamic> arguments,
    required BusinessPreferences preferences,
    required Future<bool> Function() approveRestore,
  }) async {
    final service = StorySerializationService(preferences);
    if (name == exportBundle) {
      return service.exportJson(pretty: false);
    }
    if (name != restoreBundle) return null;

    final raw = (arguments['bundle'] ?? '').toString();
    if (raw.trim().isEmpty) {
      return '{"type":"tool_error","error":"invalid_story_bundle","message":"bundle must not be empty"}';
    }
    // Validate before asking for approval so malformed payloads cannot present
    // a misleading confirmation dialog.
    final decoded = service.decodeAndValidate(raw);
    if (!await approveRestore()) {
      return '{"type":"tool_error","error":"approval_denied","message":"Story restore was not approved"}';
    }
    final report = await service.restoreJson(raw);
    return '{"type":"story_restore_result","schemaVersion":${decoded.schemaVersion},"contentSha256":"${report.contentSha256}","restoredBlobs":${report.restoredBlobKeys.length},"restoredSettings":${report.restoredSettingKeys.length}}';
  }
}
