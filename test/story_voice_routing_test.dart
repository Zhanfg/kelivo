import 'package:Kelivo/core/services/tts/network_tts.dart';
import 'package:Kelivo/features/story_runtime/voice/story_voice_models.dart';
import 'package:Kelivo/features/story_runtime/voice/story_voice_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MiMo keeps provider/model and changes voice plus delivery instruction', () {
    final base = MimoTtsOptions(
      id: 'mimo-main',
      enabled: true,
      name: 'MiMo',
      apiKey: 'secret',
      baseUrl: 'https://example.invalid/v1',
      model: 'mimo-v2.5-tts',
      voice: 'base-voice',
      instruction: 'Speak naturally.',
    );
    const assignment = StoryVoiceAssignment(
      characterId: 'npc-1',
      ttsServiceId: 'mimo-main',
      voiceId: 'voice-b',
      personaDescription: 'Young adult, clipped articulation, short pauses.',
      revision: 3,
    );
    const intent = StorySpeechIntent(
      emotion: 'fear',
      intensity: 0.6,
      delivery: StorySpeechDelivery.trembling,
      pace: StorySpeechPace.fast,
    );

    final resolved = const StoryVoiceResolver().resolve(
      service: base,
      assignment: assignment,
      intent: intent,
    );
    final routed = resolved.service as MimoTtsOptions;

    expect(routed.id, base.id);
    expect(routed.apiKey, base.apiKey);
    expect(routed.baseUrl, base.baseUrl);
    expect(routed.model, 'mimo-v2.5-tts');
    expect(routed.voice, 'voice-b');
    expect(routed.instruction, contains('Speak naturally.'));
    expect(routed.instruction, contains('Young adult'));
    expect(routed.instruction, contains('fear'));
    expect(routed.instruction, contains('trembling'));
    expect(resolved.assignmentRevision, 3);
  });

  test('explicit model override does not mutate the configured service', () {
    final base = MimoTtsOptions(
      id: 'mimo-main',
      enabled: true,
      name: 'MiMo',
      apiKey: 'secret',
      baseUrl: 'https://example.invalid/v1',
      model: 'mimo-v2.5-tts',
      voice: 'base',
    );
    const assignment = StoryVoiceAssignment(
      characterId: 'npc-1',
      ttsServiceId: 'mimo-main',
      voiceId: 'designed-voice',
      modelOverride: 'mimo-v2.5-tts-voicedesign',
      personaDescription: 'Low, dry, restrained voice.',
    );

    final resolved = const StoryVoiceResolver().resolve(
      service: base,
      assignment: assignment,
    );

    expect((resolved.service as MimoTtsOptions).model, contains('voicedesign'));
    expect(base.model, 'mimo-v2.5-tts');
  });

  test('worldline-specific assignment wins over global character voice', () {
    const state = StoryVoiceRoutingState(
      worldTreeId: 'tree',
      assignments: <StoryVoiceAssignment>[
        StoryVoiceAssignment(
          characterId: 'npc-1',
          ttsServiceId: 'svc',
          voiceId: 'global',
        ),
        StoryVoiceAssignment(
          characterId: 'npc-1',
          ttsServiceId: 'svc',
          voiceId: 'branch',
          worldlineId: 'w2',
        ),
      ],
    );

    expect(state.resolveCharacter('npc-1', worldlineId: 'w2')?.voiceId, 'branch');
    expect(state.resolveCharacter('npc-1', worldlineId: 'w1')?.voiceId, 'global');
  });
}
