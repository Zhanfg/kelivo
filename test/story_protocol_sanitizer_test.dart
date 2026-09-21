import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/parsing/story_protocol_sanitizer.dart';

void main() {
  test('removes a complete Kelivo Story sidecar', () {
    const raw = 'Visible prose.\n<!--KELIVO_STORY_EVENTS\n'
        '{"version":1,"events":[]}\nKELIVO_STORY_EVENTS-->';
    expect(stripKelivoStoryProtocol(raw), 'Visible prose.');
  });

  test('hides an incomplete sidecar during streaming', () {
    const raw = 'Visible prose.\n<!--KELIVO_STORY_EVENTS\n'
        '{"version":1,"events":[';
    expect(stripKelivoStoryProtocol(raw), 'Visible prose.');
  });

  test('leaves unrelated HTML comments untouched', () {
    const raw = 'Text <!-- ordinary comment --> more';
    expect(stripKelivoStoryProtocol(raw), raw);
  });
}
