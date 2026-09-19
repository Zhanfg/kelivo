import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/orchestration/story_break_armor_mode.dart';
import 'package:Kelivo/features/story_runtime/serialization/story_serialization_service.dart';

final class _MemoryStorySerializationStore implements StorySerializationStore {
  _MemoryStorySerializationStore(
    Map<String, Object> initial, {
    this.failOnStringKey,
  }) : values = Map<String, Object>.from(initial);

  final Map<String, Object> values;
  final String? failOnStringKey;
  bool _failed = false;

  @override
  Future<void> load() async {}

  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  String? getString(String key) => values[key] as String?;

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<bool> setString(String key, String value) async {
    if (!_failed && key == failOnStringKey) {
      _failed = true;
      throw StateError('injected_story_serialization_write_failure:$key');
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }
}

void main() {
  test(
    'Story serialization restore rolls back every touched key on failure',
    () async {
      const firstKey = 'story_runtime_execution_v1';
      const secondKey = 'story_runtime_sessions_v1';

      final source = _MemoryStorySerializationStore(<String, Object>{
        firstKey: jsonEncode(<Object?>[
          <String, Object?>{'id': 'new-execution'},
        ]),
        secondKey: jsonEncode(<Object?>[
          <String, Object?>{'id': 'new-session'},
        ]),
        storyBreakArmorEnabledKey: true,
      });
      final bundle = await StorySerializationService.withStore(
        source,
      ).exportJson(pretty: false);

      final oldFirst = jsonEncode(<Object?>[
        <String, Object?>{'id': 'old-execution'},
      ]);
      final target = _MemoryStorySerializationStore(<String, Object>{
        firstKey: oldFirst,
        storyBreakArmorEnabledKey: false,
      }, failOnStringKey: secondKey);

      await expectLater(
        StorySerializationService.withStore(target).restoreJson(bundle),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('injected_story_serialization_write_failure'),
          ),
        ),
      );

      expect(target.getString(firstKey), oldFirst);
      expect(target.containsKey(secondKey), isFalse);
      expect(target.getBool(storyBreakArmorEnabledKey), isFalse);
    },
  );

  test(
    'Story serialization restore still reports successful touched keys',
    () async {
      const key = 'story_runtime_sessions_v1';
      final source = _MemoryStorySerializationStore(<String, Object>{
        key: jsonEncode(<Object?>[
          <String, Object?>{'id': 'session-1'},
        ]),
        storyBreakArmorEnabledKey: true,
      });
      final bundle = await StorySerializationService.withStore(
        source,
      ).exportJson(pretty: false);

      final target = _MemoryStorySerializationStore(<String, Object>{});
      final report = await StorySerializationService.withStore(
        target,
      ).restoreJson(bundle);

      expect(report.restoredBlobKeys, <String>[key]);
      expect(report.restoredSettingKeys, <String>[storyBreakArmorEnabledKey]);
      expect(target.getBool(storyBreakArmorEnabledKey), isTrue);
      expect(target.getString(key), isNotNull);
    },
  );
}
