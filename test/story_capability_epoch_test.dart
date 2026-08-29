import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/cache/story_capability_epoch.dart';

void main() {
  group('StoryCapabilityEpoch', () {
    test(
      'canonical ordering prevents Set/Map order from changing cache key',
      () {
        final first = StoryCapabilityEpoch.canonical(
          epochId: 'epoch-a',
          worldlineId: 'wl-main',
          sceneEpochId: 'scene-1',
          activeSkillIds: const ['skill.z', 'skill.a'],
          toolIds: const ['tool.memory', 'tool.world'],
          mcpProfileId: 'story-standard',
          worldBookSnapshotId: 'wb-12',
          toolSchemaFingerprint: 'schema-v3',
        );
        final second = StoryCapabilityEpoch.canonical(
          epochId: 'epoch-b',
          worldlineId: 'wl-main',
          sceneEpochId: 'scene-1',
          activeSkillIds: const ['skill.a', 'skill.z'],
          toolIds: const ['tool.world', 'tool.memory'],
          mcpProfileId: 'story-standard',
          worldBookSnapshotId: 'wb-12',
          toolSchemaFingerprint: 'schema-v3',
        );

        expect(first.activeSkillIds, ['skill.a', 'skill.z']);
        expect(first.toolIds, ['tool.memory', 'tool.world']);
        expect(first.stableFingerprint, second.stableFingerprint);
        expect(first.canReuseStablePrefixWith(second), isTrue);
      },
    );

    test('tool schema change rolls cache even when tool ids do not', () {
      final before = StoryCapabilityEpoch.canonical(
        epochId: 'epoch-1',
        worldlineId: 'wl-main',
        sceneEpochId: 'scene-1',
        toolIds: const ['tool.memory'],
        toolSchemaFingerprint: 'schema-a',
      );
      final after = StoryCapabilityEpoch.canonical(
        epochId: 'epoch-2',
        worldlineId: 'wl-main',
        sceneEpochId: 'scene-1',
        toolIds: const ['tool.memory'],
        toolSchemaFingerprint: 'schema-b',
      );

      expect(before.canReuseStablePrefixWith(after), isFalse);
    });

    test(
      'worldline or scene epoch change invalidates stable prefix identity',
      () {
        final baseline = StoryCapabilityEpoch.canonical(
          epochId: 'epoch-1',
          worldlineId: 'wl-a',
          sceneEpochId: 'scene-1',
        );
        final otherWorldline = StoryCapabilityEpoch.canonical(
          epochId: 'epoch-2',
          worldlineId: 'wl-b',
          sceneEpochId: 'scene-1',
        );
        final otherScene = StoryCapabilityEpoch.canonical(
          epochId: 'epoch-3',
          worldlineId: 'wl-a',
          sceneEpochId: 'scene-2',
        );

        expect(baseline.canReuseStablePrefixWith(otherWorldline), isFalse);
        expect(baseline.canReuseStablePrefixWith(otherScene), isFalse);
      },
    );

    test(
      'duplicate capability ids are rejected instead of silently reordered',
      () {
        expect(
          () => StoryCapabilityEpoch.canonical(
            epochId: 'epoch-1',
            worldlineId: 'wl-main',
            sceneEpochId: 'scene-1',
            activeSkillIds: const ['skill.a', 'skill.a'],
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
