import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../parsing/story_response_contract.dart';
import '../parsing/story_state_update_contract.dart';
import '../reference/story_reference_profile_compiler.dart';
import 'story_capability_epoch.dart';
import 'story_prompt_cache_plan.dart';

final class StoryPromptCompilation {
  const StoryPromptCompilation({
    required this.plan,
    required this.providerText,
    required this.stablePrefixText,
    required this.stablePrefixFingerprint,
    required this.capabilityEpoch,
  });

  final StoryPromptCachePlan plan;
  final String providerText;
  final String stablePrefixText;
  final String stablePrefixFingerprint;
  final StoryCapabilityEpoch capabilityEpoch;

  StoryPromptCacheDiagnostics get diagnostics => plan.diagnostics;
}

/// Canonical Story system-prompt compiler.
///
/// Modules never mutate the system prompt directly. This is the single ordering
/// boundary that keeps cache-stable material ahead of per-turn volatility.
final class StoryPromptCompiler {
  const StoryPromptCompiler();

  StoryPromptCompilation compile({
    required StoryCapabilityEpoch capabilityEpoch,
    required String storyCoreInstructions,
    String sceneBaseline = '',
    String capabilitySummary = '',
    Iterable<StoryPromptContribution> skillContributions =
        const <StoryPromptContribution>[],
    Iterable<StoryCompiledReferenceProfile> referenceProfiles =
        const <StoryCompiledReferenceProfile>[],
    Iterable<StoryPromptContribution> additionalStable =
        const <StoryPromptContribution>[],
    Iterable<StoryPromptContribution> appendOnly =
        const <StoryPromptContribution>[],
    Iterable<StoryPromptContribution> volatile =
        const <StoryPromptContribution>[],
    Iterable<StoryPromptContribution> localOnly =
        const <StoryPromptContribution>[],
  }) {
    final contributions = <StoryPromptContribution>[
      StoryPromptContribution(
        id: 'story.core.v1',
        stability: StoryPromptStability.frozen,
        content: storyCoreInstructions.trim(),
        order: 0,
      ),
      storyResponseContractContributionV1,
      storyStateUpdateContractContributionV1,
      if (sceneBaseline.trim().isNotEmpty)
        StoryPromptContribution(
          id: 'story.scene.baseline',
          stability: StoryPromptStability.epochStable,
          content: sceneBaseline.trim(),
          order: 200,
        ),
      StoryPromptContribution(
        id: 'story.capability.epoch',
        stability: StoryPromptStability.epochStable,
        content: _capabilityEpochText(
          capabilityEpoch,
          summary: capabilitySummary,
        ),
        order: 250,
      ),
      ..._validated(skillContributions, const {
        StoryPromptStability.epochStable,
      }, 'skillContributions'),
      for (final reference in referenceProfiles)
        _validateReference(reference.contribution),
      ..._validated(additionalStable, const {
        StoryPromptStability.frozen,
        StoryPromptStability.epochStable,
      }, 'additionalStable'),
      ..._validated(appendOnly, const {
        StoryPromptStability.appendOnly,
      }, 'appendOnly'),
      ..._validated(volatile, const {
        StoryPromptStability.volatile,
      }, 'volatile'),
      ..._validated(localOnly, const {
        StoryPromptStability.localOnly,
      }, 'localOnly'),
    ];

    final plan = StoryPromptCachePlan.compile(contributions);
    final stableSections = plan.sections.where(
      (section) =>
          section.stability == StoryPromptStability.frozen ||
          section.stability == StoryPromptStability.epochStable,
    );
    final stablePrefixText = stableSections
        .where((section) => section.content.isNotEmpty)
        .map((section) => section.content)
        .join('\n\n');
    final stableIdentity = [
      for (final section in stableSections)
        <String, Object?>{
          'id': section.id,
          'stability': section.stability.name,
          'order': section.order,
          'content': section.content,
        },
    ];
    final stablePrefixFingerprint = sha256
        .convert(utf8.encode(jsonEncode(stableIdentity)))
        .toString();

    return StoryPromptCompilation(
      plan: plan,
      providerText: plan.buildProviderText(),
      stablePrefixText: stablePrefixText,
      stablePrefixFingerprint: stablePrefixFingerprint,
      capabilityEpoch: capabilityEpoch,
    );
  }
}

Iterable<StoryPromptContribution> _validated(
  Iterable<StoryPromptContribution> contributions,
  Set<StoryPromptStability> allowed,
  String field,
) sync* {
  for (final contribution in contributions) {
    if (!allowed.contains(contribution.stability)) {
      throw ArgumentError.value(
        contribution.stability,
        field,
        'unexpected Story prompt stability',
      );
    }
    yield contribution;
  }
}

StoryPromptContribution _validateReference(
  StoryPromptContribution contribution,
) {
  if (contribution.stability != StoryPromptStability.epochStable &&
      contribution.stability != StoryPromptStability.volatile) {
    throw ArgumentError.value(
      contribution.stability,
      'referenceProfiles',
      'reference profile must be epochStable or volatile',
    );
  }
  return contribution;
}

String _capabilityEpochText(
  StoryCapabilityEpoch epoch, {
  required String summary,
}) {
  final buffer = StringBuffer('[STORY_CAPABILITY_EPOCH]\n');
  buffer.writeln('fingerprint=${epoch.stableFingerprint}');
  buffer.writeln('worldline=${epoch.worldlineId}');
  buffer.writeln('scene_epoch=${epoch.sceneEpochId}');
  if (epoch.activeSkillIds.isNotEmpty) {
    buffer.writeln('skills=${epoch.activeSkillIds.join(',')}');
  }
  if (epoch.referenceProfileFingerprints.isNotEmpty) {
    buffer.writeln(
      'reference_profiles=${epoch.referenceProfileFingerprints.join(',')}',
    );
  }
  if (epoch.mcpProfileId != null) {
    buffer.writeln('mcp_profile=${epoch.mcpProfileId}');
  }
  if (epoch.toolIds.isNotEmpty) {
    buffer.writeln('tools=${epoch.toolIds.join(',')}');
  }
  if (epoch.worldBookSnapshotId != null) {
    buffer.writeln('worldbook_snapshot=${epoch.worldBookSnapshotId}');
  }
  final normalizedSummary = summary.trim();
  if (normalizedSummary.isNotEmpty) {
    buffer.writeln('summary=$normalizedSummary');
  }
  buffer.write('[/STORY_CAPABILITY_EPOCH]');
  return buffer.toString();
}
