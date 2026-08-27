import 'package:Kelivo/features/story_runtime/state/story_runtime_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Story conversation mode state', () {
    test('fresh conversation has not committed the initial mode choice', () {
      const state = StoryRuntimeSessionState(conversationId: 'c1');
      expect(state.enabled, isFalse);
      expect(state.modeSelectionCommitted, isFalse);
    });

    test('explicit Chat or Story choice round-trips independently of enabled', () {
      const chat = StoryRuntimeSessionState(
        conversationId: 'c1',
        enabled: false,
        modeSelectionCommitted: true,
      );
      final decodedChat = StoryRuntimeSessionState.fromJson(chat.toJson());
      expect(decodedChat.enabled, isFalse);
      expect(decodedChat.modeSelectionCommitted, isTrue);

      const story = StoryRuntimeSessionState(
        conversationId: 'c2',
        enabled: true,
        modeSelectionCommitted: true,
      );
      final decodedStory = StoryRuntimeSessionState.fromJson(story.toJson());
      expect(decodedStory.enabled, isTrue);
      expect(decodedStory.modeSelectionCommitted, isTrue);
    });

    test('v1 enabled Story sessions migrate as an already-made choice', () {
      final decoded = StoryRuntimeSessionState.fromJson(<String, dynamic>{
        'schema_version': 1,
        'conversation_id': 'legacy',
        'enabled': true,
        'agency_mode': 'balanced',
        'scene_revision': 0,
      });

      expect(decoded.enabled, isTrue);
      expect(decoded.modeSelectionCommitted, isTrue);
      expect(decoded.schemaVersion, StoryRuntimeSessionState.currentSchemaVersion);
    });

    test('mode conversion preserves worldline and scene sidecar identity', () {
      const story = StoryRuntimeSessionState(
        conversationId: 'c3',
        enabled: true,
        modeSelectionCommitted: true,
        worldlineId: 'worldline-a',
        sceneEpochId: 'scene-a',
        sceneRevision: 7,
      );

      final chat = story.copyWith(
        enabled: false,
        modeSelectionCommitted: true,
      );

      expect(chat.enabled, isFalse);
      expect(chat.modeSelectionCommitted, isTrue);
      expect(chat.worldlineId, 'worldline-a');
      expect(chat.sceneEpochId, 'scene-a');
      expect(chat.sceneRevision, 7);
    });
  });
}
