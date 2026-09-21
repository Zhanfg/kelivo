import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/narrative/story_narrative_director.dart';
import 'package:Kelivo/features/story_runtime/narrative/story_narrative_profile.dart';
import 'package:Kelivo/features/story_runtime/state/story_scene_runtime_state.dart';

void main() {
  test('director treats runtime state as boundaries, not a beat sheet', () {
    const profile = StoryNarrativeProfile(
      conversationId: 'c1',
      director: StoryNarrativeDirectorState(
        scenePurpose: 'Increase unease without forcing a reveal.',
        dramaticQuestion: 'Does Bob know about the key?',
        affordances: <String>['Bob has just entered', 'Alice can leave'],
      ),
    );
    const scene = StorySceneRuntimeState(
      conversationId: 'c1',
      location: 'library',
      participantCharacterIds: <String>['alice', 'bob'],
      openLoops: <String>['basement-noise'],
      continuityState: <String, Object?>{
        'alice.has_key': true,
        'bob.knows_key': false,
      },
    );

    final frame = const StoryNarrativeDirector().build(
      profile: profile,
      scene: scene,
    );

    final stable = frame.stable.map((item) => item.content).join('\n');
    final dynamicText = frame.volatile.map((item) => item.content).join('\n');

    expect(stable, contains('Runtime facts are boundaries, not a beat sheet'));
    expect(dynamicText, contains('hard_truths='));
    expect(dynamicText, contains('affordances='));
    expect(dynamicText, contains('freedom=Choose freely'));
    expect(dynamicText, isNot(contains('event log')));
  });

  test('scene packet has a hard size ceiling', () {
    final profile = StoryNarrativeProfile(
      conversationId: 'c2',
      director: StoryNarrativeDirectorState(
        affordances: List<String>.generate(
          80,
          (index) => 'long-affordance-number-$index',
        ),
      ),
    );
    const scene = StorySceneRuntimeState(conversationId: 'c2');

    final frame = const StoryNarrativeDirector(maxScenePacketChars: 420).build(
      profile: profile,
      scene: scene,
    );
    final packet = frame.volatile.single.content;

    expect(packet.length, lessThanOrEqualTo(420));
    expect(packet, contains('packet_truncated=true'));
  });
}
