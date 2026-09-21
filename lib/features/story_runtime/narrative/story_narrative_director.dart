import '../cache/story_prompt_cache_plan.dart';
import '../state/story_scene_runtime_state.dart';
import 'story_narrative_profile.dart';

final class StoryNarrativeDirectorFrame {
  const StoryNarrativeDirectorFrame({
    required this.stable,
    required this.volatile,
  });

  final List<StoryPromptContribution> stable;
  final List<StoryPromptContribution> volatile;
}

/// Builds the literary layer above Story Runtime.
///
/// Runtime state is treated as a boundary, never as a prose outline. The frame
/// deliberately carries only compact constraints and creative affordances so
/// the model spends its output budget on fiction rather than restating state.
final class StoryNarrativeDirector {
  const StoryNarrativeDirector({this.maxScenePacketChars = 2600});

  final int maxScenePacketChars;

  StoryNarrativeDirectorFrame build({
    required StoryNarrativeProfile profile,
    required StorySceneRuntimeState scene,
  }) {
    final stable = <StoryPromptContribution>[
      StoryPromptContribution(
        id: 'story.narrative.style-dna.v1',
        stability: StoryPromptStability.epochStable,
        order: 345,
        content: _styleText(profile),
      ),
      if (profile.characterVoices.isNotEmpty)
        StoryPromptContribution(
          id: 'story.narrative.character-voices.v1',
          stability: StoryPromptStability.epochStable,
          order: 350,
          content: _voiceText(profile),
        ),
    ];

    return StoryNarrativeDirectorFrame(
      stable: List.unmodifiable(stable),
      volatile: <StoryPromptContribution>[
        StoryPromptContribution(
          id: 'story.narrative.scene-packet.v1',
          stability: StoryPromptStability.volatile,
          order: 835,
          content: _scenePacket(profile, scene),
        ),
      ],
    );
  }

  String _styleText(StoryNarrativeProfile profile) {
    final s = profile.style;
    final b = StringBuffer('[STORY_STYLE_DNA]\n')
      ..writeln('surface=' + profile.surface.name)
      ..writeln('voice=' + s.narrativeVoice)
      ..writeln('pov=' + s.pov)
      ..writeln('distance=' + s.narrativeDistance)
      ..writeln('sentence_rhythm=' + s.sentenceRhythm)
      ..writeln('dialogue=' + s.dialogue)
      ..writeln('description=' + s.descriptionDensity)
      ..writeln('metaphor=' + s.metaphorDensity)
      ..writeln('sensory=' + s.sensoryFocus)
      ..writeln('pacing=' + s.pacing)
      ..writeln('exposition=' + s.expositionTolerance)
      ..writeln('implicitness=' + s.implicitness)
      ..writeln('emotion=' + s.emotionalExplicitness)
      ..writeln('transitions=' + s.sceneTransitions)
      ..writeln('paragraphs=' + s.paragraphRhythm);
    if (s.avoidPatterns.isNotEmpty) {
      b.writeln('avoid=' + s.avoidPatterns.join(' | '));
    }
    b
      ..writeln('principle=Runtime facts are boundaries, not a beat sheet. Never turn them into an inventory, event log, status report, or checklist.')
      ..writeln('principle=Prefer natural scene construction, subtext, silence, omission, rhythm changes, and selective detail over explicit explanation.')
      ..writeln('principle=Do not force a choice, reveal, conflict, emotional beat, or scene transition merely because the runtime exposes one as possible.')
      ..write('[/STORY_STYLE_DNA]');
    return b.toString();
  }

  String _voiceText(StoryNarrativeProfile profile) {
    final ids = profile.characterVoices.keys.toList()..sort();
    final b = StringBuffer('[STORY_CHARACTER_VOICES]\n');
    for (final id in ids) {
      final v = profile.characterVoices[id]!;
      final traits = <String>[
        if (v.vocabulary.isNotEmpty) 'vocab=' + v.vocabulary,
        if (v.sentenceShape.isNotEmpty) 'shape=' + v.sentenceShape,
        if (v.subtext.isNotEmpty) 'subtext=' + v.subtext,
        if (v.emotionalLeakage.isNotEmpty) 'leak=' + v.emotionalLeakage,
        if (v.verbalHabits.isNotEmpty) 'habits=' + v.verbalHabits.join(','),
        if (v.avoids.isNotEmpty) 'avoid=' + v.avoids.join(','),
      ];
      if (traits.isNotEmpty) b.writeln(id + ':' + traits.join(';'));
    }
    b.write('[/STORY_CHARACTER_VOICES]');
    return b.toString();
  }

  String _scenePacket(
    StoryNarrativeProfile profile,
    StorySceneRuntimeState scene,
  ) {
    final d = profile.director;
    final b = StringBuffer('[STORY_SCENE_PACKET]\n');
    if (scene.location?.trim().isNotEmpty == true) {
      b.writeln('where=' + scene.location!.trim());
    }
    if (scene.timeLabel?.trim().isNotEmpty == true) {
      b.writeln('when=' + scene.timeLabel!.trim());
    }
    if (scene.participantCharacterIds.isNotEmpty) {
      b.writeln('present=' + scene.participantCharacterIds.join(','));
    }
    if (scene.pov.trim().isNotEmpty) b.writeln('pov=' + scene.pov.trim());
    if (d.scenePurpose.isNotEmpty) b.writeln('intent=' + d.scenePurpose);
    if (d.dramaticQuestion.isNotEmpty) {
      b.writeln('dramatic_question=' + d.dramaticQuestion);
    }
    if (d.pacingDirection.isNotEmpty) {
      b.writeln('pacing_direction=' + d.pacingDirection);
    }
    if (d.tension != null || d.targetTension != null) {
      b.writeln('tension=' + _num(d.tension) + '>' + _num(d.targetTension));
    }
    if (d.informationAsymmetry.isNotEmpty) {
      b.writeln(
        'information_asymmetry=' + d.informationAsymmetry.join(' | '),
      );
    }
    final hardTruths = _compactFacts(scene.continuityState);
    if (hardTruths.isNotEmpty) b.writeln('hard_truths=' + hardTruths);

    final affordances = <String>[
      ...d.affordances,
      ..._stringList(scene.serialState['affordances']),
    ];
    if (affordances.isNotEmpty) {
      b.writeln('affordances=' + _dedupe(affordances).join(' | '));
    }
    if (scene.openLoops.isNotEmpty) {
      b.writeln('open_threads=' + scene.openLoops.join(' | '));
    }
    if (d.repetitionWarnings.isNotEmpty) {
      b.writeln(
        'avoid_recent_pattern=' + d.repetitionWarnings.join(' | '),
      );
    }
    b
      ..writeln('freedom=Choose freely how to realize the scene. You may delay, omit, imply, redirect attention, use silence, or leave an affordance unused.')
      ..writeln('output=Write continuous reader-facing fiction, not runtime annotations.')
      ..write('[/STORY_SCENE_PACKET]');

    final raw = b.toString();
    if (raw.length <= maxScenePacketChars) return raw;
    const suffix = '\npacket_truncated=true\n[/STORY_SCENE_PACKET]';
    final keep = (maxScenePacketChars - suffix.length).clamp(0, raw.length).toInt();
    return raw.substring(0, keep) + suffix;
  }
}

String _num(double? value) =>
    value == null ? '?' : value.toStringAsFixed(2);

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

List<String> _dedupe(Iterable<String> values) {
  final seen = <String>{};
  final out = <String>[];
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty && seen.add(normalized)) out.add(normalized);
  }
  return out;
}

String _compactFacts(Map<String, Object?> facts) {
  if (facts.isEmpty) return '';
  final keys = facts.keys.toList()..sort();
  final parts = <String>[];
  for (final key in keys) {
    final value = facts[key];
    if (value == null) continue;
    final encoded = switch (value) {
      String v => v.trim(),
      num v => v.toString(),
      bool v => v ? 'true' : 'false',
      List v => v.take(8).join(','),
      _ => '',
    };
    if (encoded.isNotEmpty) parts.add(key + '=' + encoded);
  }
  return parts.join(';');
}
