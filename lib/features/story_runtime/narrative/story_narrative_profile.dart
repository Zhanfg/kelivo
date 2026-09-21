enum StorySurfaceMode { novel, roleplay, visualNovel, screenplay, experimental }

final class StoryStyleDna {
  const StoryStyleDna({
    this.narrativeVoice = 'literary, natural, non-formulaic',
    this.pov = 'preserve the established point of view',
    this.narrativeDistance = 'close when character interiority matters',
    this.sentenceRhythm = 'varied; let tension change sentence length',
    this.dialogue = 'character-specific, subtext-aware, not expository',
    this.descriptionDensity = 'selective rather than exhaustive',
    this.metaphorDensity = 'restrained; avoid habitual metaphors',
    this.sensoryFocus = 'use only details that matter to the scene',
    this.pacing = 'scene-driven; do not force equal beats per turn',
    this.expositionTolerance = 'low',
    this.implicitness = 'prefer implication over naming emotions',
    this.emotionalExplicitness = 'low to medium',
    this.sceneTransitions = 'organic; hard cuts are allowed when effective',
    this.paragraphRhythm = 'variable',
    this.avoidPatterns = const <String>[],
  });

  final String narrativeVoice;
  final String pov;
  final String narrativeDistance;
  final String sentenceRhythm;
  final String dialogue;
  final String descriptionDensity;
  final String metaphorDensity;
  final String sensoryFocus;
  final String pacing;
  final String expositionTolerance;
  final String implicitness;
  final String emotionalExplicitness;
  final String sceneTransitions;
  final String paragraphRhythm;
  final List<String> avoidPatterns;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'narrative_voice': narrativeVoice,
    'pov': pov,
    'narrative_distance': narrativeDistance,
    'sentence_rhythm': sentenceRhythm,
    'dialogue': dialogue,
    'description_density': descriptionDensity,
    'metaphor_density': metaphorDensity,
    'sensory_focus': sensoryFocus,
    'pacing': pacing,
    'exposition_tolerance': expositionTolerance,
    'implicitness': implicitness,
    'emotional_explicitness': emotionalExplicitness,
    'scene_transitions': sceneTransitions,
    'paragraph_rhythm': paragraphRhythm,
    'avoid_patterns': avoidPatterns,
  };

  factory StoryStyleDna.fromJson(Map<String, dynamic> json) => StoryStyleDna(
    narrativeVoice: _string(json['narrative_voice'], 'literary, natural, non-formulaic'),
    pov: _string(json['pov'], 'preserve the established point of view'),
    narrativeDistance: _string(json['narrative_distance'], 'close when character interiority matters'),
    sentenceRhythm: _string(json['sentence_rhythm'], 'varied; let tension change sentence length'),
    dialogue: _string(json['dialogue'], 'character-specific, subtext-aware, not expository'),
    descriptionDensity: _string(json['description_density'], 'selective rather than exhaustive'),
    metaphorDensity: _string(json['metaphor_density'], 'restrained; avoid habitual metaphors'),
    sensoryFocus: _string(json['sensory_focus'], 'use only details that matter to the scene'),
    pacing: _string(json['pacing'], 'scene-driven; do not force equal beats per turn'),
    expositionTolerance: _string(json['exposition_tolerance'], 'low'),
    implicitness: _string(json['implicitness'], 'prefer implication over naming emotions'),
    emotionalExplicitness: _string(json['emotional_explicitness'], 'low to medium'),
    sceneTransitions: _string(json['scene_transitions'], 'organic; hard cuts are allowed when effective'),
    paragraphRhythm: _string(json['paragraph_rhythm'], 'variable'),
    avoidPatterns: _strings(json['avoid_patterns']),
  );
}

final class StoryCharacterVoiceDna {
  const StoryCharacterVoiceDna({
    required this.characterId,
    this.vocabulary = '',
    this.sentenceShape = '',
    this.subtext = '',
    this.emotionalLeakage = '',
    this.verbalHabits = const <String>[],
    this.avoids = const <String>[],
  });

  final String characterId;
  final String vocabulary;
  final String sentenceShape;
  final String subtext;
  final String emotionalLeakage;
  final List<String> verbalHabits;
  final List<String> avoids;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'character_id': characterId,
    'vocabulary': vocabulary,
    'sentence_shape': sentenceShape,
    'subtext': subtext,
    'emotional_leakage': emotionalLeakage,
    'verbal_habits': verbalHabits,
    'avoids': avoids,
  };

  factory StoryCharacterVoiceDna.fromJson(Map<String, dynamic> json) =>
      StoryCharacterVoiceDna(
        characterId: _string(json['character_id'], ''),
        vocabulary: _string(json['vocabulary'], ''),
        sentenceShape: _string(json['sentence_shape'], ''),
        subtext: _string(json['subtext'], ''),
        emotionalLeakage: _string(json['emotional_leakage'], ''),
        verbalHabits: _strings(json['verbal_habits']),
        avoids: _strings(json['avoids']),
      );
}

final class StoryNarrativeDirectorState {
  const StoryNarrativeDirectorState({
    this.scenePurpose = '',
    this.dramaticQuestion = '',
    this.pacingDirection = '',
    this.informationAsymmetry = const <String>[],
    this.affordances = const <String>[],
    this.repetitionWarnings = const <String>[],
    this.tension,
    this.targetTension,
  });

  final String scenePurpose;
  final String dramaticQuestion;
  final String pacingDirection;
  final List<String> informationAsymmetry;
  final List<String> affordances;
  final List<String> repetitionWarnings;
  final double? tension;
  final double? targetTension;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'scene_purpose': scenePurpose,
    'dramatic_question': dramaticQuestion,
    'pacing_direction': pacingDirection,
    'information_asymmetry': informationAsymmetry,
    'affordances': affordances,
    'repetition_warnings': repetitionWarnings,
    if (tension != null) 'tension': tension,
    if (targetTension != null) 'target_tension': targetTension,
  };

  factory StoryNarrativeDirectorState.fromJson(Map<String, dynamic> json) =>
      StoryNarrativeDirectorState(
        scenePurpose: _string(json['scene_purpose'], ''),
        dramaticQuestion: _string(json['dramatic_question'], ''),
        pacingDirection: _string(json['pacing_direction'], ''),
        informationAsymmetry: _strings(json['information_asymmetry']),
        affordances: _strings(json['affordances']),
        repetitionWarnings: _strings(json['repetition_warnings']),
        tension: _double(json['tension']),
        targetTension: _double(json['target_tension']),
      );
}

final class StoryNarrativeProfile {
  const StoryNarrativeProfile({
    required this.conversationId,
    this.surface = StorySurfaceMode.novel,
    this.style = const StoryStyleDna(),
    this.characterVoices = const <String, StoryCharacterVoiceDna>{},
    this.director = const StoryNarrativeDirectorState(),
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final String conversationId;
  final StorySurfaceMode surface;
  final StoryStyleDna style;
  final Map<String, StoryCharacterVoiceDna> characterVoices;
  final StoryNarrativeDirectorState director;
  final int schemaVersion;

  StoryNarrativeProfile copyWith({
    StorySurfaceMode? surface,
    StoryStyleDna? style,
    Map<String, StoryCharacterVoiceDna>? characterVoices,
    StoryNarrativeDirectorState? director,
  }) => StoryNarrativeProfile(
    conversationId: conversationId,
    surface: surface ?? this.surface,
    style: style ?? this.style,
    characterVoices: characterVoices ?? this.characterVoices,
    director: director ?? this.director,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': currentSchemaVersion,
    'conversation_id': conversationId,
    'surface': surface.name,
    'style': style.toJson(),
    'character_voices': <String, dynamic>{
      for (final entry in characterVoices.entries) entry.key: entry.value.toJson(),
    },
    'director': director.toJson(),
  };

  factory StoryNarrativeProfile.fromJson(Map<String, dynamic> json) {
    final id = _string(json['conversation_id'], '');
    if (id.isEmpty) throw const FormatException('missing_story_narrative_conversation_id');
    final rawVoices = json['character_voices'];
    final voices = <String, StoryCharacterVoiceDna>{};
    if (rawVoices is Map) {
      for (final entry in rawVoices.entries) {
        if (entry.value is Map) {
          final map = Map<String, dynamic>.from(entry.value as Map);
          final voice = StoryCharacterVoiceDna.fromJson(map);
          if (voice.characterId.isNotEmpty) voices[entry.key.toString()] = voice;
        }
      }
    }
    return StoryNarrativeProfile(
      conversationId: id,
      surface: StorySurfaceMode.values.firstWhere(
        (value) => value.name == json['surface'],
        orElse: () => StorySurfaceMode.novel,
      ),
      style: json['style'] is Map
          ? StoryStyleDna.fromJson(Map<String, dynamic>.from(json['style'] as Map))
          : const StoryStyleDna(),
      characterVoices: Map.unmodifiable(voices),
      director: json['director'] is Map
          ? StoryNarrativeDirectorState.fromJson(
              Map<String, dynamic>.from(json['director'] as Map),
            )
          : const StoryNarrativeDirectorState(),
    );
  }
}

String _string(Object? value, String fallback) {
  if (value is! String) return fallback;
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

List<String> _strings(Object? value) {
  if (value is! List) return const <String>[];
  return List<String>.unmodifiable(
    value.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty),
  );
}

double? _double(Object? value) {
  if (value is! num || value.isNaN || value.isInfinite) return null;
  return value.toDouble().clamp(0.0, 1.0).toDouble();
}
