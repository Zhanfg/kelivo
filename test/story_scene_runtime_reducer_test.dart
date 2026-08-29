import 'package:Kelivo/features/story_runtime/parsing/story_response_parser.dart';
import 'package:Kelivo/features/story_runtime/state/story_scene_runtime_reducer.dart';
import 'package:Kelivo/features/story_runtime/state/story_scene_runtime_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'scene transition and continuity patches update persisted scene state',
    () {
      const raw = '''
{
  "version": 1,
  "events": [
    {
      "type": "scene_transition",
      "actor": {"type": "world"},
      "text": [{"text": "The elevator opens."}],
      "metadata": {
        "scene_id": "tower-12",
        "location": "North Tower / Floor 12",
        "time_label": "23:40",
        "participant_character_ids": ["mira"],
        "pov": "self",
        "open_loops_add": ["Find the missing key"],
        "continuity_patch": {"weather": "storm", "old": null},
        "serial_patch": {"chapter": 7}
      }
    },
    {
      "type": "dialogue",
      "actor": {"type": "character", "character_id": "guard"},
      "text": [{"text": "Stop."}],
      "metadata": {
        "open_loops_add": ["Convince the guard"],
        "open_loops_close": ["Find the missing key"],
        "continuity_patch": {"door_locked": true}
      }
    }
  ]
}
''';
      final turn = const StoryResponseParser().parse(raw, turnId: 'turn-1');
      const current = StorySceneRuntimeState(
        conversationId: 'conversation',
        openLoops: <String>['Old loop'],
        continuityState: <String, Object?>{'old': 'remove-me'},
        revision: 4,
      );

      final next = reduceStoryTurnIntoScene(
        current: current,
        turn: turn,
        worldTreeId: 'tree',
        worldlineId: 'line',
      );

      expect(next.worldTreeId, 'tree');
      expect(next.worldlineId, 'line');
      expect(next.sceneId, 'tower-12');
      expect(next.location, 'North Tower / Floor 12');
      expect(next.timeLabel, '23:40');
      expect(next.participantCharacterIds, <String>['guard', 'mira']);
      expect(next.openLoops, <String>['Old loop', 'Convince the guard']);
      expect(next.continuityState['weather'], 'storm');
      expect(next.continuityState['door_locked'], true);
      expect(next.continuityState.containsKey('old'), isFalse);
      expect(next.serialState['chapter'], 7);
      expect(next.revision, 5);
    },
  );

  test(
    'malformed metadata is ignored and unchanged state does not churn revision',
    () {
      const raw = '''
{
  "version": 1,
  "events": [
    {
      "type": "narration",
      "actor": {"type": "world"},
      "text": [{"text": "Nothing changes."}],
      "metadata": {
        "open_loops_add": "not-an-array",
        "continuity_patch": "not-an-object"
      }
    }
  ]
}
''';
      final turn = const StoryResponseParser().parse(raw, turnId: 'turn-2');
      const current = StorySceneRuntimeState(
        conversationId: 'conversation',
        worldTreeId: 'tree',
        worldlineId: 'line',
        revision: 2,
      );

      final next = reduceStoryTurnIntoScene(
        current: current,
        turn: turn,
        worldTreeId: 'tree',
        worldlineId: 'line',
      );

      expect(next.revision, 2);
      expect(next.openLoops, isEmpty);
      expect(next.continuityState, isEmpty);
    },
  );
}
