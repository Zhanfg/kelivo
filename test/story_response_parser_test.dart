import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/models/story_runtime_models.dart';
import 'package:Kelivo/features/story_runtime/parsing/story_response_contract.dart';
import 'package:Kelivo/features/story_runtime/parsing/story_response_parser.dart';

void main() {
  const parser = StoryResponseParser();

  group('StoryResponseParser', () {
    test('preserves story event order and second-person SELF', () {
      final turn = parser.parse(
        '''
        {
          "version": 1,
          "events": [
            {
              "type": "narration",
              "actor": {"type": "world"},
              "text": [{"text": "走廊里的灯闪了一下。"}]
            },
            {
              "type": "dialogue",
              "actor": {"type": "character", "character_id": "char_suqing"},
              "text": [{"text": "别回头。", "effect": "horror"}]
            },
            {
              "type": "action",
              "actor": {"type": "self"},
              "text": [{"text": "停下脚步。"}]
            }
          ]
        }
        ''',
        turnId: 'turn-7',
      );

      expect(turn.id, 'turn-7');
      expect(turn.events.map((event) => event.id), [
        'turn-7_e0',
        'turn-7_e1',
        'turn-7_e2',
      ]);
      expect(turn.events[0].actor.isWorld, isTrue);
      expect(turn.events[1].actor.characterId, 'char_suqing');
      expect(turn.events[1].text.single.effect, StoryTextEffect.horror);
      expect(turn.events[2].actor.isSelf, isTrue);
    });

    test('accepts fenced JSON defensively', () {
      final turn = parser.parse(
        '''```json
{"version":1,"events":[{"type":"dialogue","actor":{"type":"self"},"text":[{"text":"听见了。"}]}]}
```''',
        turnId: 'turn-fenced',
      );

      expect(turn.events.single.type, StoryEventType.dialogue);
      expect(turn.events.single.actor.isSelf, isTrue);
    });

    test('SELF expression remains valid without inventing a player character', () {
      final turn = parser.parse(
        '''{"version":1,"events":[{"type":"expression","actor":{"type":"self"},"text":[{"text":"皱了皱眉。"}]}]}''',
        turnId: 'turn-self-expression',
      );

      expect(turn.events.single.type, StoryEventType.expression);
      expect(turn.events.single.actor.isSelf, isTrue);
      expect(turn.events.single.actor.characterId, isNull);
    });

    test('parses timed choice set without making it a generic chat reply', () {
      final turn = parser.parse(
        '''
        {
          "version": 1,
          "events": [
            {
              "type": "choice_set",
              "actor": {"type": "self"},
              "choices": [
                {"id": "follow", "label": "跟上去", "submit_text": "跟上苏晴。"},
                {"id": "stay", "label": "留在这里"}
              ],
              "timeout_ms": 5000,
              "timeout_action_id": "silence"
            }
          ]
        }
        ''',
        turnId: 'turn-choice',
      );

      final event = turn.events.single;
      expect(event.type, StoryEventType.choiceSet);
      expect(event.choices.length, 2);
      expect(event.choices.first.submitText, '跟上苏晴。');
      expect(event.timeout, const Duration(seconds: 5));
      expect(event.timeoutActionId, 'silence');
    });

    test('unknown visual effects degrade without corrupting story text', () {
      final turn = parser.parse(
        '''
        {
          "version": 1,
          "events": [
            {
              "type": "narration",
              "actor": {"type": "world"},
              "text": [
                {
                  "text": "门后还有东西。",
                  "effect": "future_effect",
                  "decoration": "future_decoration",
                  "motion": "future_motion"
                }
              ]
            }
          ]
        }
        ''',
        turnId: 'turn-forward',
      );

      final span = turn.events.single.text.single;
      expect(span.text, '门后还有东西。');
      expect(span.effect, StoryTextEffect.unknown);
      expect(span.decoration, StoryTextDecoration.none);
      expect(span.motion, StoryTextMotion.none);
    });

    test('rejects an NPC id attached to SELF', () {
      expect(
        () => parser.parse(
          '''
          {
            "version": 1,
            "events": [
              {
                "type": "dialogue",
                "actor": {"type": "self", "character_id": "char_fake_player"},
                "text": [{"text": "错误。"}]
              }
            ]
          }
          ''',
          turnId: 'turn-invalid-self',
        ),
        throwsA(
          isA<StoryResponseParseException>().having(
            (error) => error.code,
            'code',
            'self_has_character_id',
          ),
        ),
      );
    });

    test('rejects non-integral protocol versions instead of truncating them', () {
      expect(
        () => parser.parse(
          '''{"version":1.5,"events":[{"type":"narration","actor":{"type":"world"},"text":[{"text":"x"}]}]}''',
          turnId: 'turn-version',
        ),
        throwsA(
          isA<StoryResponseParseException>().having(
            (error) => error.code,
            'code',
            'unsupported_version',
          ),
        ),
      );
    });

    test('rejects a consequential-looking choice without actual options', () {
      expect(
        () => parser.parse(
          '''
          {
            "version": 1,
            "events": [
              {"type": "choice_set", "actor": {"type": "self"}}
            ]
          }
          ''',
          turnId: 'turn-empty-choice',
        ),
        throwsA(
          isA<StoryResponseParseException>().having(
            (error) => error.code,
            'code',
            'choice_set_without_choices',
          ),
        ),
      );
    });

    test('rejects fractional timeout milliseconds', () {
      expect(
        () => parser.parse(
          '''{"version":1,"events":[{"type":"dialogue","actor":{"type":"character","character_id":"char_1"},"text":[{"text":"快回答。"}],"timeout_ms":2500.5}]}''',
          turnId: 'turn-fractional-timeout',
        ),
        throwsA(
          isA<StoryResponseParseException>().having(
            (error) => error.code,
            'code',
            'timeout_out_of_range',
          ),
        ),
      );
    });

    test('bounds timer and total event payload', () {
      const strictParser = StoryResponseParser(
        maxEvents: 1,
        maxTotalTextChars: 3,
      );

      expect(
        () => strictParser.parse(
          '''{"version":1,"events":[{"type":"narration","actor":{"type":"world"},"text":[{"text":"1234"}]}]}''',
          turnId: 'turn-budget',
        ),
        throwsA(
          isA<StoryResponseParseException>().having(
            (error) => error.code,
            'code',
            'text_budget_exceeded',
          ),
        ),
      );
    });
  });

  test('story output contract is a frozen cache contribution', () {
    expect(
      storyResponseContractContributionV1.stability.name,
      'frozen',
    );
    expect(storyResponseContractV1, contains('Never invent or switch'));
    expect(storyResponseContractV1, contains('Do not serialize reasoning'));
  });
}
