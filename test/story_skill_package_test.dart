import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/skills/story_skill_package_importer.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_package_store.dart';

void main() {
  group('Story Skill package importer', () {
    late Directory tempDir;
    late _MemorySkillPackageRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kelivo_skill_test_');
      repository = _MemorySkillPackageRepository();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('installs manifest, SKILL.md and prompt files as one capability package', () async {
      final zip = await _writeArchive(
        tempDir,
        'skill.zip',
        Archive()
          ..add(
            ArchiveFile.string(
              'NovelSkill/manifest.json',
              '''{
                "schema_version": 1,
                "id": "story.novel",
                "name": "Novel Skill",
                "version": "1.0.0",
                "mcp_servers": ["mcp.story"],
                "permissions": ["mcp"],
                "activation": {"modes": ["manual", "director"]}
              }''',
            ),
          )
          ..add(
            ArchiveFile.string(
              'NovelSkill/SKILL.md',
              'Keep scene continuity and preserve second-person SELF.',
            ),
          )
          ..add(
            ArchiveFile.string(
              'NovelSkill/prompts/20_dialogue.md',
              'Dialogue should keep subtext concise.',
            ),
          )
          ..add(
            ArchiveFile.string(
              'NovelSkill/prompts/10_scene.md',
              'Resolve scene state before narration.',
            ),
          )
          ..add(
            ArchiveFile.string(
              'NovelSkill/assets/readme.txt',
              'data asset',
            ),
          )
          ..add(
            ArchiveFile.string(
              'NovelSkill/scripts/ignored.sh',
              'echo should-never-be-executed-or-extracted',
            ),
          ),
      );

      final importer = StorySkillPackageImporter(
        repository: repository,
        appDataRootResolver: () async => tempDir,
      );
      final result = await importer.importZip(zip.path);

      expect(result.deduplicated, isFalse);
      expect(result.manifest.id, 'story.novel');
      expect(result.manifest.instructions, [
        'Keep scene continuity and preserve second-person SELF.',
        'Resolve scene state before narration.',
        'Dialogue should keep subtext concise.',
      ]);
      expect(result.package.relativeRoot, 'story_skills/story.novel/1.0.0');

      final installed = Directory('${tempDir.path}/${result.package.relativeRoot}');
      expect(await File('${installed.path}/manifest.json').exists(), isTrue);
      expect(await File('${installed.path}/SKILL.md').exists(), isTrue);
      expect(await File('${installed.path}/prompts/10_scene.md').exists(), isTrue);
      expect(await File('${installed.path}/scripts/ignored.sh').exists(), isFalse);
    });

    test('same package hash deduplicates the same id and version', () async {
      final zip = await _writeArchive(
        tempDir,
        'dedupe.zip',
        Archive()
          ..add(
            ArchiveFile.string(
              'manifest.json',
              '{"id":"story.dedupe","name":"Dedupe","version":"1"}',
            ),
          )
          ..add(ArchiveFile.string('SKILL.md', 'Stable instructions.')),
      );
      final importer = StorySkillPackageImporter(
        repository: repository,
        appDataRootResolver: () async => tempDir,
      );

      final first = await importer.importZip(zip.path);
      final second = await importer.importZip(zip.path);

      expect(first.deduplicated, isFalse);
      expect(second.deduplicated, isTrue);
      expect(second.package.packageHash, first.package.packageHash);
    });

    test('path traversal entry is rejected before extraction', () async {
      final zip = await _writeArchive(
        tempDir,
        'traversal.zip',
        Archive()
          ..add(
            ArchiveFile.string(
              'manifest.json',
              '{"id":"story.bad","name":"Bad","version":"1"}',
            ),
          )
          ..add(ArchiveFile.string('SKILL.md', 'Safe instruction.'))
          ..add(ArchiveFile.string('../escape.txt', 'must not escape')),
      );
      final importer = StorySkillPackageImporter(
        repository: repository,
        appDataRootResolver: () async => tempDir,
      );

      expect(
        () => importer.importZip(zip.path),
        throwsA(
          isA<StorySkillPackageException>().having(
            (error) => error.code,
            'code',
            'path_traversal',
          ),
        ),
      );
      expect(await File('${tempDir.parent.path}/escape.txt').exists(), isFalse);
    });

    test('oversized instruction bundle is rejected', () async {
      final zip = await _writeArchive(
        tempDir,
        'large_prompt.zip',
        Archive()
          ..add(
            ArchiveFile.string(
              'manifest.json',
              '{"id":"story.large","name":"Large","version":"1"}',
            ),
          )
          ..add(ArchiveFile.string('SKILL.md', '1234567890')),
      );
      final importer = StorySkillPackageImporter(
        repository: repository,
        appDataRootResolver: () async => tempDir,
        maxInstructionChars: 5,
      );

      expect(
        () => importer.importZip(zip.path),
        throwsA(
          isA<StorySkillPackageException>().having(
            (error) => error.code,
            'code',
            'instruction_budget_exceeded',
          ),
        ),
      );
    });
  });
}

Future<File> _writeArchive(
  Directory root,
  String name,
  Archive archive,
) async {
  final bytes = ZipEncoder().encodeBytes(archive);
  final file = File('${root.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

final class _MemorySkillPackageRepository
    implements StorySkillPackageRepository {
  final List<StoryInstalledSkillPackage> items = <StoryInstalledSkillPackage>[];

  @override
  Future<List<StoryInstalledSkillPackage>> readAll() async =>
      List.unmodifiable(items);

  @override
  Future<StoryInstalledSkillPackage?> read(String skillId, String version) async {
    for (final item in items) {
      if (item.skillId == skillId && item.version == version) return item;
    }
    return null;
  }

  @override
  Future<void> upsert(StoryInstalledSkillPackage package) async {
    items.removeWhere(
      (item) => item.skillId == package.skillId && item.version == package.version,
    );
    items.add(package);
  }

  @override
  Future<void> remove(String skillId, String version) async {
    items.removeWhere(
      (item) => item.skillId == skillId && item.version == version,
    );
  }
}
