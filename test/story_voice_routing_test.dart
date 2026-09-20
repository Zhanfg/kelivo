import 'package:Kelivo/core/services/tts/network_tts.dart';
import 'package:Kelivo/features/story_runtime/voice/story_voice_context.dart';
import 'package:Kelivo/features/story_runtime/voice/story_voice_models.dart';
import 'package:Kelivo/features/story_runtime/voice/story_voice_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'MiMo keeps provider/model and changes voice plus delivery instruction',
    () {
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
      expect(resolved.cacheIdentity, isNotEmpty);
    },
  );

  test('MiMo context changes instruction and semantic cache identity', () {
    final base = MimoTtsOptions(
      id: 'mimo-main',
      enabled: true,
      name: 'MiMo',
      apiKey: 'secret',
      baseUrl: 'https://example.invalid/v1',
      model: 'mimo-v2.5-tts',
      voice: 'base',
      stream: true,
    );
    const assignment = StoryVoiceAssignment(
      characterId: 'npc-1',
      ttsServiceId: 'mimo-main',
      voiceId: 'voice-a',
      personaDescription: 'Quiet and precise.',
    );
    const contextA = StoryVoiceContextWindow(
      previous: '门关上了。',
      current: '别出声。',
      next: '脚步声靠近。',
      sceneHint: 'dark corridor',
    );
    const contextB = StoryVoiceContextWindow(
      previous: '门关上了。',
      current: '别出声。',
      next: '四周恢复安静。',
      sceneHint: 'dark corridor',
    );

    final a = const StoryVoiceResolver().resolve(
      service: base,
      assignment: assignment,
      context: contextA,
    );
    final b = const StoryVoiceResolver().resolve(
      service: base,
      assignment: assignment,
      context: contextB,
    );
    final routed = a.service as MimoTtsOptions;

    expect(routed.stream, isTrue);
    expect(routed.instruction, isNot(contains('门关上了')));
    expect(routed.instruction, isNot(contains('别出声')));
    expect(routed.instruction, isNot(contains('脚步声靠近')));
    expect(a.instruction, contains('门关上了'));
    expect(a.instruction, isNot(contains('别出声')));
    expect(a.instruction, contains('脚步声靠近'));
    expect(a.cacheIdentity, isNot(b.cacheIdentity));
  });

  test('MiMo chunk context uses adjacent chunks and never repeats current text', () {
    final service = MimoTtsOptions(
      id: 'mimo-main',
      enabled: true,
      name: 'MiMo',
      apiKey: 'secret',
      baseUrl: 'https://example.invalid/v1',
      model: 'mimo-v2.5-tts',
      voice: 'voice-a',
      instruction: 'Quiet and precise.',
    );
    const outer = StoryVoiceContextWindow(
      previous: '上一条消息。',
      current: '整条当前消息。',
      next: '下一条消息。',
      sceneHint: 'dark corridor',
    );
    final window = StoryVoiceContextCompiler.forChunk(
      chunks: const ['第一段。', '第二段。', '第三段。'],
      index: 1,
      outerContext: outer,
    );
    final routed = const StoryVoiceResolver().withMimoContext(
      service: service,
      context: window,
    );

    expect(routed.instruction, contains('第一段。'));
    expect(routed.instruction, contains('第三段。'));
    expect(routed.instruction, contains('dark corridor'));
    expect(routed.instruction, isNot(contains('第二段。')));
    expect(routed.instruction, isNot(contains('整条当前消息。')));
  });

  test('non-MiMo Story voice ignores contextual prompt augmentation', () {
    final base = StepTtsOptions(
      id: 'step-main',
      enabled: true,
      name: 'Step',
      apiKey: 'secret',
      baseUrl: 'https://example.invalid/v1',
      model: 'stepaudio-2.5-tts',
      voice: 'base',
      instruction: 'Base instruction.',
    );
    const assignment = StoryVoiceAssignment(
      characterId: 'npc-1',
      ttsServiceId: 'step-main',
      voiceId: 'voice-a',
      personaDescription: 'Calm speaker.',
    );
    const context = StoryVoiceContextWindow(
      previous: 'secret previous context',
      current: 'current line',
      next: 'secret next context',
    );

    final resolved = const StoryVoiceResolver().resolve(
      service: base,
      assignment: assignment,
      context: context,
    );
    final routed = resolved.service as StepTtsOptions;

    expect(routed.instruction, contains('Base instruction.'));
    expect(routed.instruction, contains('Calm speaker.'));
    expect(routed.instruction, isNot(contains('secret previous context')));
    expect(routed.instruction, isNot(contains('secret next context')));
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

    expect(
      state.resolveCharacter('npc-1', worldlineId: 'w2')?.voiceId,
      'branch',
    );
    expect(
      state.resolveCharacter('npc-1', worldlineId: 'w1')?.voiceId,
      'global',
    );
  });
}
