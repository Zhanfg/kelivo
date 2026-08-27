/// Core semantic types for Story Mode.
///
/// These models intentionally describe story meaning, not Flutter rendering.
/// Chat Mode remains untouched; Story Mode can project these events into a
/// dedicated renderer while existing reasoning/tool parts keep their native UI.
library;

enum StoryActorType { self, character, world }

enum StoryEventType {
  narration,
  dialogue,
  action,
  expression,
  sceneTransition,
  choiceSet,
  runtimeNotice,
}

enum StoryTextEffect {
  normal,
  emphasis,
  horror,
  warning,
  whisper,
  distorted,
  corrupted,
  memory,
  unknown,
}

enum StoryTextDecoration { none, underline, wavyUnderline, strikethrough }

enum StoryTextMotion { none, jitter, flicker, glitch }

enum StoryAvatarKind { initials, localAsset, generated, custom }

/// The semantic speaker/actor for a story event.
///
/// `self` is always the real user in second-person Story Mode. There is no
/// player-character id and no mechanism for silently switching control to an
/// NPC.
final class StoryActorRef {
  const StoryActorRef._(this.type, this.characterId);

  const StoryActorRef.self() : this._(StoryActorType.self, null);

  const StoryActorRef.world() : this._(StoryActorType.world, null);

  const StoryActorRef.character(String characterId)
    : assert(characterId != ''),
      this._(StoryActorType.character, characterId);

  final StoryActorType type;
  final String? characterId;

  bool get isSelf => type == StoryActorType.self;
  bool get isCharacter => type == StoryActorType.character;
  bool get isWorld => type == StoryActorType.world;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoryActorRef &&
          type == other.type &&
          characterId == other.characterId;

  @override
  int get hashCode => Object.hash(type, characterId);
}

/// A span-level presentation hint.
///
/// The model/runtime emits semantics (`horror`, `distorted`, ...), while the
/// theme resolver decides actual colors, weights and motion. This keeps dynamic
/// color, accessibility and reduced-motion settings authoritative.
final class StoryTextSpan {
  const StoryTextSpan(
    this.text, {
    this.effect = StoryTextEffect.normal,
    this.decoration = StoryTextDecoration.none,
    this.motion = StoryTextMotion.none,
  });

  final String text;
  final StoryTextEffect effect;
  final StoryTextDecoration decoration;
  final StoryTextMotion motion;
}

/// Social avatar used by the conversation UI.
///
/// It is deliberately separate from character appearance/portrait. A social
/// avatar may be a letter, pet, scenery, casual photo, chibi image or any other
/// stable identity marker. Generated avatars are expected to be created once
/// and reused unless the story explicitly establishes a major identity change.
final class StoryAvatarRef {
  const StoryAvatarRef({required this.kind, this.value});

  const StoryAvatarRef.initials() : kind = StoryAvatarKind.initials, value = null;

  final StoryAvatarKind kind;
  final String? value;
}

/// What the user should currently see for a stable character id.
///
/// [characterId] never changes. [displayName] and [presentationId] may change
/// with aliases, roles, disguises, relationship context, worldline state or
/// other story developments.
final class StoryCharacterPresentation {
  const StoryCharacterPresentation({
    required this.characterId,
    required this.presentationId,
    required this.displayName,
    this.avatar = const StoryAvatarRef.initials(),
  });

  final String characterId;
  final String presentationId;
  final String displayName;
  final StoryAvatarRef avatar;
}

final class StoryChoice {
  const StoryChoice({
    required this.id,
    required this.label,
    this.submitText,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String label;

  /// Optional semantic text sent to the runtime. The visible label can remain
  /// concise while the runtime receives an unambiguous action.
  final String? submitText;
  final Map<String, Object?> metadata;
}

/// One semantic event in story order.
///
/// Reasoning and tool calls do not belong here: they remain native Kelivo
/// runtime items. Story projection interleaves those native runtime items with
/// these events without pretending that reasoning is a character's inner voice.
final class StoryEvent {
  const StoryEvent({
    required this.id,
    required this.type,
    required this.actor,
    this.text = const <StoryTextSpan>[],
    this.choices = const <StoryChoice>[],
    this.timeout,
    this.timeoutActionId,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final StoryEventType type;
  final StoryActorRef actor;
  final List<StoryTextSpan> text;
  final List<StoryChoice> choices;

  /// Optional pressure timer. Absence means the interaction is not timed.
  final Duration? timeout;

  /// Choice/action used when the timeout expires. A runtime may instead map a
  /// null value to semantic silence/no-response.
  final String? timeoutActionId;
  final Map<String, Object?> metadata;
}

final class StoryTurn {
  const StoryTurn({required this.id, required this.events});

  final String id;
  final List<StoryEvent> events;
}

/// Stable baseline for a scene epoch.
///
/// Location/time are runtime state, not mandatory permanent chrome. The
/// presentation layer decides when a location/time transition should actually
/// be shown to the reader.
final class StorySceneSnapshot {
  const StorySceneSnapshot({
    required this.id,
    required this.worldlineId,
    this.location,
    this.timeLabel,
    this.participantCharacterIds = const <String>[],
    this.revision = 0,
  });

  final String id;
  final String worldlineId;
  final String? location;
  final String? timeLabel;
  final List<String> participantCharacterIds;
  final int revision;
}
