/// Provider-neutral voice semantics for Story Mode.
///
/// A character binds to a stable base voice. Per-line delivery is expressed as
/// intent and adapted by the provider (MiMo, Azure, local Qwen, etc.) without
/// changing character identity merely because story importance changes.
library;

enum StorySpeechPace { verySlow, slow, normal, fast, veryFast }

enum StorySpeechVolume { veryQuiet, quiet, normal, loud, veryLoud }

enum StorySpeechDelivery {
  neutral,
  restrained,
  hesitant,
  whisper,
  breathy,
  firm,
  shout,
  trembling,
}

enum StoryVoiceChannel {
  direct,
  phone,
  radio,
  recording,
  speaker,
  internal,
  unknown,
}

/// Stable voice identity for a character.
///
/// [providerId] and [voiceId] should remain fixed after a recurring character
/// has acquired a recognizable voice. Character promotion upgrades persona and
/// synthesis quality first; provider migration is an explicit continuity event.
final class StoryCharacterVoiceProfile {
  const StoryCharacterVoiceProfile({
    required this.characterId,
    required this.providerId,
    required this.voiceId,
    this.personaDescription = '',
    this.lockContinuity = true,
    this.metadata = const <String, Object?>{},
  });

  final String characterId;
  final String providerId;
  final String voiceId;

  /// Long-lived speaking identity: rhythm, articulation, pause style, energy,
  /// sentence endings and a small number of stable signature traits.
  final String personaDescription;
  final bool lockContinuity;
  final Map<String, Object?> metadata;
}

/// Semantic delivery request for one spoken unit.
///
/// Providers map this into their own controls: MiMo may receive natural-language
/// instructions; Azure may map it to SSML/style/rate/pitch; lightweight local
/// engines may implement only pace and volume.
final class StorySpeechIntent {
  const StorySpeechIntent({
    this.emotion,
    this.intensity = 0,
    this.pace = StorySpeechPace.normal,
    this.volume = StorySpeechVolume.normal,
    this.delivery = StorySpeechDelivery.neutral,
    this.channel = StoryVoiceChannel.direct,
    this.emphasis = const <String>[],
  }) : assert(intensity >= 0 && intensity <= 1);

  final String? emotion;
  final double intensity;
  final StorySpeechPace pace;
  final StorySpeechVolume volume;
  final StorySpeechDelivery delivery;
  final StoryVoiceChannel channel;
  final List<String> emphasis;
}

/// Capabilities are declared per concrete voice, not just per provider.
/// Azure, for example, exposes different styles for different voices.
final class StoryVoiceCapabilities {
  const StoryVoiceCapabilities({
    this.streaming = false,
    this.naturalLanguageInstruction = false,
    this.voiceClone = false,
    this.voiceDesign = false,
    this.pace = false,
    this.pitch = false,
    this.volume = false,
    this.supportedStyles = const <String>{},
  });

  final bool streaming;
  final bool naturalLanguageInstruction;
  final bool voiceClone;
  final bool voiceDesign;
  final bool pace;
  final bool pitch;
  final bool volume;
  final Set<String> supportedStyles;
}
