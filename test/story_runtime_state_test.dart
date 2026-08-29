import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/agency/story_agency_policy.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_state.dart';

void main() {
  group('StoryRuntimeSessionState', () {
    test('defaults to opt-out and balanced agency', () {
      const state = StoryRuntimeSessionState(conversationId: 'conv-1');

      expect(state.enabled, isFalse);
      expect(state.agencyMode, StoryAgencyMode.balanced);
      expect(state.worldlineId, isNull);
      expect(state.sceneEpochId, isNull);
    });

    test('round-trips versioned state', () {
      const state = StoryRuntimeSessionState(
        conversationId: 'conv-2',
        enabled: true,
        agencyMode: StoryAgencyMode.cinematic,
        worldlineId: 'wl-main',
        sceneEpochId: 'scene-42',
        sceneRevision: 7,
      );

      final decoded = StoryRuntimeSessionState.fromJson(state.toJson());

      expect(decoded.conversationId, state.conversationId);
      expect(decoded.enabled, isTrue);
      expect(decoded.agencyMode, StoryAgencyMode.cinematic);
      expect(decoded.worldlineId, 'wl-main');
      expect(decoded.sceneEpochId, 'scene-42');
      expect(decoded.sceneRevision, 7);
    });

    test(
      'copyWith can clear epoch/worldline without changing opt-in state',
      () {
        const state = StoryRuntimeSessionState(
          conversationId: 'conv-3',
          enabled: true,
          worldlineId: 'wl-branch',
          sceneEpochId: 'scene-9',
        );

        final next = state.copyWith(
          clearWorldlineId: true,
          clearSceneEpochId: true,
        );

        expect(next.enabled, isTrue);
        expect(next.worldlineId, isNull);
        expect(next.sceneEpochId, isNull);
      },
    );

    test(
      'rejects future schema versions instead of silently corrupting state',
      () {
        expect(
          () => StoryRuntimeSessionState.fromJson({
            'schema_version': 999,
            'conversation_id': 'conv-future',
          }),
          throwsFormatException,
        );
      },
    );
  });
}
