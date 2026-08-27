import 'package:Kelivo/features/story_runtime/parsing/story_readable_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structured Story response becomes readable Markdown', () {
    const raw = '''
{
  "version": 1,
  "events": [
    {
      "type": "narration",
      "actor": {"type": "world"},
      "text": [{"text": "Rain hits the window."}]
    },
    {
      "type": "dialogue",
      "actor": {"type": "character", "character_id": "npc-secret-id"},
      "text": [{"text": "You came back."}],
      "metadata": {"display_name": "Mira"}
    },
    {
      "type": "action",
      "actor": {"type": "character", "character_id": "npc-secret-id"},
      "text": [{"text": "She closes the door."}]
    },
    {
      "type": "choice_set",
      "actor": {"type": "self"},
      "choices": [
        {"id": "stay", "label": "Stay"},
        {"id": "leave", "label": "Leave"}
      ]
    }
  ]
}
''';

    final projected = tryProjectStoryReadable(raw, turnId: 'turn-1');
    expect(projected, isNotNull);
    expect(projected!.markdown, contains('Rain hits the window.'));
    expect(projected.markdown, contains('**Mira**'));
    expect(projected.markdown, contains('You came back.'));
    expect(projected.markdown, contains('*She closes the door.*'));
    expect(projected.markdown, contains('**Stay**'));
    expect(projected.markdown, contains('**Leave**'));
    expect(projected.markdown, isNot(contains('npc-secret-id')));
  });

  test('plain assistant prose remains unchanged', () {
    const text = 'Ordinary assistant response.';
    expect(
      projectStoryReadableOrOriginal(text, turnId: 'turn-2'),
      text,
    );
  });

  test('partial streaming Story envelope is hidden until it is renderable', () {
    const partial = '{"version":1,"events":[';
    expect(
      projectStoryReadableOrOriginal(
        partial,
        turnId: 'turn-3',
        streaming: true,
      ),
      isEmpty,
    );
  });

  test('invalid finalized Story-like JSON remains available as fallback text', () {
    const invalid = '{"version":1,"events":[';
    expect(
      projectStoryReadableOrOriginal(invalid, turnId: 'turn-4'),
      invalid,
    );
  });
}
