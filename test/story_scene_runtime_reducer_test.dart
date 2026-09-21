import 'package:Kelivo/features/story_runtime/models/story_runtime_models.dart';
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

  test('action result updates scene relationships and replaces choices', () {
    const raw = '''
{
  "version": 1,
  "events": [
    {
      "type": "action_result",
      "actor": {"type": "world"},
      "metadata": {
        "feedback": "你推开门，守卫明显更警惕了。",
        "scene_patch": {
          "location": "Archive",
          "participant_add": ["guard"],
          "participant_remove": ["mira"]
        },
        "relationship_patch": [
          {
            "from": "guard",
            "to": "self",
            "delta": {"trust": -0.2, "fear": 0.1}
          }
        ]
      }
    },
    {
      "type": "choice_set",
      "actor": {"type": "self"},
      "choices": [
        {"id": "hide", "label": "躲到书架后"},
        {"id": "speak", "label": "主动开口"}
      ]
    }
  ]
}
''';
    final turn = const StoryResponseParser().parse(raw, turnId: 'turn-action');
    const current = StorySceneRuntimeState(
      conversationId: 'conversation',
      worldTreeId: 'tree',
      worldlineId: 'line',
      location: 'Hall',
      participantCharacterIds: <String>['mira'],
      availableChoices: <StoryChoice>[
        StoryChoice(id: 'old', label: '旧选项'),
      ],
      relationships: <StoryRelationshipEdge>[
        StoryRelationshipEdge(
          fromId: 'guard',
          toId: 'self',
          dimensions: <String, double>{'trust': 0.4},
        ),
      ],
      revision: 3,
    );

    final next = reduceStoryTurnIntoScene(
      current: current,
      turn: turn,
      worldTreeId: 'tree',
      worldlineId: 'line',
    );

    expect(next.location, 'Archive');
    expect(next.participantCharacterIds, <String>['guard']);
    expect(next.availableChoices.map((item) => item.id), <String>[
      'hide',
      'speak',
    ]);
    final edge = next.relationships.single;
    expect(edge.dimensions['trust'], closeTo(0.2, 0.0001));
    expect(edge.dimensions['fear'], closeTo(0.1, 0.0001));
    expect(next.revision, 4);
  });

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
