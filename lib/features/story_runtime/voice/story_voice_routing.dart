import '../../../core/services/tts/network_tts.dart';
import 'story_voice_context.dart';
import 'story_voice_models.dart';

/// Stable Story binding to one of Kelivo's existing network TTS services.
///
/// Credentials and endpoints stay in Kelivo's TTS service config. Story stores
/// only identity/presentation overrides, so changing a character's narrative
/// importance never creates a second provider configuration.
final class StoryVoiceAssignment {
  const StoryVoiceAssignment({
    required this.characterId,
    required this.ttsServiceId,
    required this.voiceId,
    this.modelOverride,
    this.personaDescription = '',
    this.worldlineId,
    this.revision = 0,
    this.lockContinuity = true,
    this.metadata = const <String, Object?>{},
  }) : assert(characterId != ''),
       assert(ttsServiceId != ''),
       assert(voiceId != ''),
       assert(revision >= 0);

  final String characterId;
  final String ttsServiceId;
  final String voiceId;
  final String? modelOverride;
  final String personaDescription;
  final String? worldlineId;
  final int revision;
  final bool lockContinuity;
  final Map<String, Object?> metadata;

  StoryVoiceAssignment copyWith({
    String? ttsServiceId,
    String? voiceId,
    String? modelOverride,
    String? personaDescription,
    String? worldlineId,
    int? revision,
    bool? lockContinuity,
    Map<String, Object?>? metadata,
    bool clearModelOverride = false,
    bool clearWorldlineId = false,
  }) => StoryVoiceAssignment(
    characterId: characterId,
    ttsServiceId: ttsServiceId ?? this.ttsServiceId,
    voiceId: voiceId ?? this.voiceId,
    modelOverride: clearModelOverride
        ? null
        : (modelOverride ?? this.modelOverride),
    personaDescription: personaDescription ?? this.personaDescription,
    worldlineId: clearWorldlineId ? null : (worldlineId ?? this.worldlineId),
    revision: revision ?? this.revision,
    lockContinuity: lockContinuity ?? this.lockContinuity,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'characterId': characterId,
    'ttsServiceId': ttsServiceId,
    'voiceId': voiceId,
    if (modelOverride != null) 'modelOverride': modelOverride,
    'personaDescription': personaDescription,
    if (worldlineId != null) 'worldlineId': worldlineId,
    'revision': revision,
    'lockContinuity': lockContinuity,
    'metadata': metadata,
  };

  factory StoryVoiceAssignment.fromJson(Map<String, dynamic> json) =>
      StoryVoiceAssignment(
        characterId: (json['characterId'] as String).trim(),
        ttsServiceId: (json['ttsServiceId'] as String).trim(),
        voiceId: (json['voiceId'] as String).trim(),
        modelOverride: _optionalString(json['modelOverride']),
        personaDescription: (json['personaDescription'] as String? ?? '')
            .trim(),
        worldlineId: _optionalString(json['worldlineId']),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        lockContinuity: json['lockContinuity'] != false,
        metadata: Map<String, Object?>.from(
          (json['metadata'] as Map?) ?? const <String, Object?>{},
        ),
      );
}

final class StoryVoiceRoutingState {
  const StoryVoiceRoutingState({
    required this.worldTreeId,
    this.narrator,
    this.assignments = const <StoryVoiceAssignment>[],
  });

  final String worldTreeId;
  final StoryVoiceAssignment? narrator;
  final List<StoryVoiceAssignment> assignments;

  StoryVoiceAssignment? resolveCharacter(
    String characterId, {
    String? worldlineId,
  }) {
    StoryVoiceAssignment? fallback;
    for (final assignment in assignments) {
      if (assignment.characterId != characterId) continue;
      if (assignment.worldlineId == worldlineId && worldlineId != null) {
        return assignment;
      }
      if (assignment.worldlineId == null) fallback = assignment;
    }
    return fallback;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'worldTreeId': worldTreeId,
    if (narrator != null) 'narrator': narrator!.toJson(),
    'assignments': assignments.map((item) => item.toJson()).toList(),
  };

  factory StoryVoiceRoutingState.fromJson(Map<String, dynamic> json) =>
      StoryVoiceRoutingState(
        worldTreeId: (json['worldTreeId'] as String).trim(),
        narrator: json['narrator'] is Map
            ? StoryVoiceAssignment.fromJson(
                Map<String, dynamic>.from(json['narrator'] as Map),
              )
            : null,
        assignments: ((json['assignments'] as List?) ?? const <Object?>[])
            .map(
              (item) => StoryVoiceAssignment.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
}

final class StoryResolvedVoiceRequest {
  const StoryResolvedVoiceRequest({
    required this.service,
    required this.characterId,
    required this.voiceId,
    required this.instruction,
    required this.assignmentRevision,
    required this.cacheIdentity,
  });

  final TtsServiceOptions service;
  final String characterId;
  final String voiceId;
  final String instruction;
  final int assignmentRevision;

  /// Stable semantic identity for the routed voice/context. Kelivo's native
  /// TtsProvider remains authoritative for actual chunk/replay audio caching.
  final String cacheIdentity;
}

/// Maps Story semantics onto an existing Kelivo TTS service configuration.
///
/// MiMo receives the same configured API key/base URL/model by default. Story
/// changes only voice + natural-language delivery/context instruction unless an
/// explicit modelOverride was stored on the assignment. The resulting service
/// is still played once through native TtsProvider, preserving its internal
/// chunking, prefetch, seek and replay cache semantics.
final class StoryVoiceResolver {
  const StoryVoiceResolver();

  StoryResolvedVoiceRequest resolve({
    required TtsServiceOptions service,
    required StoryVoiceAssignment assignment,
    StorySpeechIntent intent = const StorySpeechIntent(),
    StoryVoiceContextWindow? context,
  }) {
    if (service.id != assignment.ttsServiceId) {
      throw StateError('story_voice_service_identity_mismatch');
    }
    final deliveryInstruction = StoryVoiceInstructionCompiler.compile(
      persona: assignment.personaDescription,
      intent: intent,
    );
    final contextInstruction = StoryVoiceContextCompiler.instruction(context);
    final instruction = _mergeInstructions(
      deliveryInstruction,
      contextInstruction,
    );
    final routed = _routeService(
      service,
      assignment: assignment,
      instruction: instruction,
    );
    final modelIdentity = switch (routed) {
      MimoTtsOptions() => routed.model,
      StepTtsOptions() => routed.model,
      QwenTtsOptions() => routed.model,
      _ => routed.kind.name,
    };
    return StoryResolvedVoiceRequest(
      service: routed,
      characterId: assignment.characterId,
      voiceId: assignment.voiceId,
      instruction: instruction,
      assignmentRevision: assignment.revision,
      cacheIdentity: StoryVoiceContextCompiler.cacheIdentity(
        serviceId: routed.id,
        model: modelIdentity,
        voiceId: assignment.voiceId,
        persona: assignment.personaDescription,
        deliveryInstruction: deliveryInstruction,
        context: context,
      ),
    );
  }

  TtsServiceOptions _routeService(
    TtsServiceOptions service, {
    required StoryVoiceAssignment assignment,
    required String instruction,
  }) {
    if (service is MimoTtsOptions) {
      return MimoTtsOptions(
        id: service.id,
        enabled: service.enabled,
        name: service.name,
        apiKey: service.apiKey,
        baseUrl: service.baseUrl,
        model: assignment.modelOverride?.trim().isNotEmpty == true
            ? assignment.modelOverride!.trim()
            : service.model,
        voice: assignment.voiceId,
        instruction: _mergeInstructions(service.instruction, instruction),
        stream: service.stream,
        optimizeTextPreview: service.optimizeTextPreview,
      );
    }
    if (service is StepTtsOptions) {
      return StepTtsOptions(
        id: service.id,
        enabled: service.enabled,
        name: service.name,
        apiKey: service.apiKey,
        baseUrl: service.baseUrl,
        model: assignment.modelOverride?.trim().isNotEmpty == true
            ? assignment.modelOverride!.trim()
            : service.model,
        voice: assignment.voiceId,
        responseFormat: service.responseFormat,
        speed: service.speed,
        volume: service.volume,
        sampleRate: service.sampleRate,
        instruction: _mergeInstructions(service.instruction, instruction),
      );
    }
    if (service is AzureTtsOptions) {
      return AzureTtsOptions(
        id: service.id,
        enabled: service.enabled,
        name: service.name,
        apiKey: service.apiKey,
        baseUrl: service.baseUrl,
        language: service.language,
        voice: assignment.voiceId,
      );
    }
    if (service is QwenTtsOptions) {
      return QwenTtsOptions(
        id: service.id,
        enabled: service.enabled,
        name: service.name,
        apiKey: service.apiKey,
        baseUrl: service.baseUrl,
        model: assignment.modelOverride?.trim().isNotEmpty == true
            ? assignment.modelOverride!.trim()
            : service.model,
        voice: assignment.voiceId,
        languageType: service.languageType,
      );
    }
    throw UnsupportedError(
      'Story contextual voice routing is not implemented for ${service.kind.name}.',
    );
  }
}

final class StoryVoiceInstructionCompiler {
  const StoryVoiceInstructionCompiler._();

  static String compile({
    required String persona,
    required StorySpeechIntent intent,
  }) {
    final parts = <String>[];
    final base = persona.trim();
    if (base.isNotEmpty) parts.add(base);
    final emotion = intent.emotion?.trim();
    if (emotion != null && emotion.isNotEmpty) {
      final intensity = (intent.intensity * 100).round();
      parts.add('Emotion: $emotion at about $intensity% intensity.');
    }
    if (intent.delivery != StorySpeechDelivery.neutral) {
      parts.add('Delivery: ${_enumWords(intent.delivery.name)}.');
    }
    if (intent.pace != StorySpeechPace.normal) {
      parts.add('Pace: ${_enumWords(intent.pace.name)}.');
    }
    if (intent.volume != StorySpeechVolume.normal) {
      parts.add('Volume: ${_enumWords(intent.volume.name)}.');
    }
    if (intent.channel != StoryVoiceChannel.direct) {
      parts.add('Channel impression: ${_enumWords(intent.channel.name)}.');
    }
    if (intent.emphasis.isNotEmpty) {
      parts.add('Gently emphasize: ${intent.emphasis.join(', ')}.');
    }
    return parts.join(' ');
  }
}

String _mergeInstructions(String base, String contextual) {
  final a = base.trim();
  final b = contextual.trim();
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return '$a $b';
}

String _enumWords(String value) => value.replaceAllMapped(
  RegExp(r'([a-z])([A-Z])'),
  (match) => '${match.group(1)} ${match.group(2)!.toLowerCase()}',
);

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
