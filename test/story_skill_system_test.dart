import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/agency/story_agency_policy.dart';
import 'package:Kelivo/features/story_runtime/cache/story_prompt_cache_plan.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_manifest_parser.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_models.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_resolver.dart';

void main() {
  const parser = StorySkillManifestParser();
  const resolver = StorySkillResolver();

  group('Story Skill manifest', () {
    test('parses a capability package instead of a prompt-only skill', () {
      final manifest = parser.parse('''
      {
        "schema_version": 1,
        "id": "story.serial_writer",
        "name": "Serial Writer",
        "version": "1.2.0",
        "instructions": ["Keep chapter continuity stable."],
        "worldbooks": ["wb.serial"],
        "mcp_servers": ["mcp.github"],
        "tools": ["tool.repo_status"],
        "memory": {
          "read_categories": ["story_state"],
          "write_categories": ["chapter_summary"]
        },
        "tts": {"policy": "prefer_enabled"},
        "activation": {
          "modes": ["serial_due", "director"],
          "condition_ids": []
        },
        "permissions": [
          "mcp",
          "memory_read",
          "memory_write",
          "tts"
        ],
        "hooks": [
          {"event": "after_story_turn", "handler": "serial.checkpoint"}
        ]
      }
      ''');

      expect(manifest.id, 'story.serial_writer');
      expect(manifest.mcpServerIds, ['mcp.github']);
      expect(manifest.toolIds, ['tool.repo_status']);
      expect(
        manifest.permissions,
        containsAll([
          StorySkillPermission.mcp,
          StorySkillPermission.memoryRead,
          StorySkillPermission.memoryWrite,
          StorySkillPermission.tts,
        ]),
      );
      expect(manifest.hooks.single.localOnly, isTrue);
    });

    test('tool capability cannot silently bypass permission declaration', () {
      expect(
        () => parser.parse('''
        {
          "id": "bad.skill",
          "name": "Bad",
          "version": "1",
          "tools": ["tool.hidden"]
        }
        '''),
        throwsA(
          isA<StorySkillManifestException>().having(
            (error) => error.code,
            'code',
            'tool_permission_required',
          ),
        ),
      );
    });
  });

  group('Story Skill activation', () {
    const lowLatencyStory = StorySkillManifest(
      id: 'story.base',
      name: 'Base Story',
      version: '1',
      instructions: ['Use second-person story pacing.'],
      activationModes: {StorySkillActivationMode.always},
    );
    const githubSerial = StorySkillManifest(
      id: 'story.github_serial',
      name: 'GitHub Serial',
      version: '1',
      mcpServerIds: ['mcp.github'],
      toolIds: ['tool.repo_status'],
      activationModes: {StorySkillActivationMode.serialDue},
      permissions: {StorySkillPermission.mcp},
    );

    const bindings = [
      StorySkillBinding(assistantId: 'assistant-1', skillId: 'story.base'),
      StorySkillBinding(
        assistantId: 'assistant-1',
        skillId: 'story.github_serial',
      ),
    ];

    test('ordinary Story turn does not expose low-frequency GitHub capability', () {
      final resolved = resolver.resolve(
        manifests: const [lowLatencyStory, githubSerial],
        bindings: bindings,
        context: const StorySkillActivationContext(
          assistantId: 'assistant-1',
        ),
      );

      expect(resolved.activeSkills.map((skill) => skill.id), ['story.base']);
      expect(resolved.mcpServerIds, isEmpty);
      expect(resolved.toolIds, isEmpty);
    });

    test('SERIAL_DUE activates GitHub profile deterministically', () {
      final resolved = resolver.resolve(
        manifests: const [githubSerial, lowLatencyStory],
        bindings: bindings,
        context: const StorySkillActivationContext(
          assistantId: 'assistant-1',
          serialDueSkillIds: {'story.github_serial'},
        ),
      );

      expect(resolved.activeSkills.map((skill) => skill.id), [
        'story.base',
        'story.github_serial',
      ]);
      expect(resolved.mcpServerIds, ['mcp.github']);
      expect(resolved.toolIds, ['tool.repo_status']);
    });

    test('manual binding can disable automatic activation without disabling skill', () {
      final resolved = resolver.resolve(
        manifests: const [lowLatencyStory],
        bindings: const [
          StorySkillBinding(
            assistantId: 'assistant-1',
            skillId: 'story.base',
            allowAutomaticActivation: false,
          ),
        ],
        context: const StorySkillActivationContext(
          assistantId: 'assistant-1',
        ),
      );

      expect(resolved.activeSkills, isEmpty);
    });

    test('active instructions become epoch-stable prompt material', () {
      final resolved = resolver.resolve(
        manifests: const [lowLatencyStory],
        bindings: bindings,
        context: const StorySkillActivationContext(
          assistantId: 'assistant-1',
        ),
      );
      final contribution = resolved.toPromptContribution();

      expect(contribution, isNotNull);
      expect(contribution!.stability, StoryPromptStability.epochStable);
      expect(contribution.content, contains('Use second-person story pacing.'));
    });

    test('Skill result can join reference fingerprints in one capability epoch', () {
      final resolved = resolver.resolve(
        manifests: const [lowLatencyStory],
        bindings: bindings,
        context: const StorySkillActivationContext(
          assistantId: 'assistant-1',
        ),
      );
      final epoch = resolved.toCapabilityEpoch(
        epochId: 'epoch-1',
        sceneEpochId: 'scene-1',
        worldlineId: 'wl-main',
        referenceProfileFingerprints: const ['ref-fingerprint'],
      );

      expect(epoch.referenceProfileFingerprints, ['ref-fingerprint']);
      expect(epoch.activeSkillIds, ['story.base@1']);
    });
  });

  test('Agency policy remains independent from Skill activation', () {
    const policy = StoryAgencyPolicy(mode: StoryAgencyMode.cinematic);
    final decision = policy.decide(
      const StoryAgencySignals(
        requiresSelfAction: true,
        worldlineImpact: 0.9,
        predictionConfidence: 1,
      ),
    );
    expect(decision.requiresUserInput, isTrue);
  });
}
