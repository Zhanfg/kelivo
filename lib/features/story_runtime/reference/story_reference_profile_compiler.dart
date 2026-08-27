import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../cache/story_prompt_cache_plan.dart';
import 'story_reference_models.dart';

final class StoryCompiledReferenceProfile {
  const StoryCompiledReferenceProfile({
    required this.profileId,
    required this.fingerprint,
    required this.contribution,
  });

  final String profileId;
  final String fingerprint;
  final StoryPromptContribution contribution;
}

/// Turns user-selected StyleProfiles into compact model-visible craft guidance.
///
/// The compiler never reads the source novel. It only receives already-derived
/// profiles, so normal Story turns cannot accidentally pull the full reference
/// text into the prompt.
final class StoryReferenceProfileCompiler {
  const StoryReferenceProfileCompiler();

  List<StoryCompiledReferenceProfile> compile({
    required Iterable<StoryReferenceStyleProfile> profiles,
    required Iterable<StoryReferenceInvocation> invocations,
  }) {
    final byId = <String, StoryReferenceStyleProfile>{
      for (final profile in profiles) profile.id: profile,
    };
    final requested = invocations.where((item) => item.strength > 0).toList()
      ..sort((a, b) => a.profileId.compareTo(b.profileId));

    final result = <StoryCompiledReferenceProfile>[];
    final seen = <String>{};
    for (final invocation in requested) {
      if (!seen.add(invocation.profileId)) {
        throw ArgumentError.value(
          invocation.profileId,
          'invocations',
          'duplicate reference profile invocation',
        );
      }
      final profile = byId[invocation.profileId];
      if (profile == null) continue;
      final aspects = invocation.enabledAspects.isEmpty
          ? profile.aspects
          : invocation.enabledAspects.intersection(profile.aspects);
      final fingerprint = referenceInvocationFingerprint(profile, invocation);
      final content = _buildProfileText(profile, invocation, aspects);
      result.add(
        StoryCompiledReferenceProfile(
          profileId: profile.id,
          fingerprint: fingerprint,
          contribution: StoryPromptContribution(
            id: 'story.reference.${profile.id}',
            stability: invocation.turnScoped
                ? StoryPromptStability.volatile
                : StoryPromptStability.epochStable,
            content: content,
            order: 400,
          ),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  String _buildProfileText(
    StoryReferenceStyleProfile profile,
    StoryReferenceInvocation invocation,
    Set<StoryReferenceAspect> aspects,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('[REFERENCE_STYLE_PROFILE]');
    buffer.writeln('profile_id=${profile.id}');
    buffer.writeln('strength=${invocation.strength.toStringAsFixed(2)}');
    buffer.writeln(
      'Use this only as abstract writing-craft guidance. Produce original prose. Do not reuse source plot, characters, names, quotations, distinctive phrases, or reconstructed passages.',
    );

    void add(String label, Iterable<String> values) {
      final cleaned = values
          .map((value) => value.trim())
          .where((v) => v.isNotEmpty);
      if (cleaned.isEmpty) return;
      buffer.writeln('$label:');
      for (final value in cleaned) {
        buffer.writeln('- $value');
      }
    }

    add('CORE', profile.coreTraits);
    if (aspects.contains(StoryReferenceAspect.prose)) {
      add('SENTENCE_RHYTHM', profile.sentenceRhythm);
      add('PARAGRAPHING', profile.paragraphing);
      add('DICTION', profile.diction);
    }
    if (aspects.contains(StoryReferenceAspect.narration)) {
      add('NARRATION', profile.narrationMethods);
    }
    if (aspects.contains(StoryReferenceAspect.dialogue)) {
      add('DIALOGUE', profile.dialogueMethods);
    }
    if (aspects.contains(StoryReferenceAspect.description) ||
        aspects.contains(StoryReferenceAspect.worldbuilding)) {
      add('DESCRIPTION', profile.descriptionMethods);
    }
    if (aspects.contains(StoryReferenceAspect.action)) {
      add('ACTION', profile.actionMethods);
    }
    if (aspects.contains(StoryReferenceAspect.atmosphere) ||
        aspects.contains(StoryReferenceAspect.horror)) {
      add('ATMOSPHERE', profile.atmosphereMethods);
    }
    if (aspects.contains(StoryReferenceAspect.romanceIntimacy)) {
      add('MATURE_RELATIONSHIP_CRAFT', profile.intimacyMethods);
    }
    if (aspects.contains(StoryReferenceAspect.characterInterior)) {
      add('INTERIORITY', profile.interiorityMethods);
    }
    if (aspects.contains(StoryReferenceAspect.pacing)) {
      add('PACING', profile.pacingMethods);
    }
    add('AVOID', profile.avoidPatterns);

    if (profile.metrics.isNotEmpty) {
      buffer.writeln('METRICS:');
      final keys = profile.metrics.keys.toList(growable: false)..sort();
      for (final key in keys) {
        buffer.writeln('- $key=${profile.metrics[key]!.toStringAsFixed(2)}');
      }
    }
    buffer.write('[/REFERENCE_STYLE_PROFILE]');
    return buffer.toString();
  }
}

String referenceInvocationFingerprint(
  StoryReferenceStyleProfile profile,
  StoryReferenceInvocation invocation,
) {
  final aspects = invocation.enabledAspects.map((value) => value.name).toList()
    ..sort();
  final payload = jsonEncode(<String, Object?>{
    'profile_id': profile.id,
    'profile_schema': profile.schemaVersion,
    'source_hash': profile.sourceContentHash,
    'strength': invocation.strength.toStringAsFixed(4),
    'aspects': aspects,
    'turn_scoped': invocation.turnScoped,
  });
  return sha256.convert(utf8.encode(payload)).toString();
}
