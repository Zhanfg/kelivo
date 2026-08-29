import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/features/story_runtime/skills/story_skill_github_source.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_package_importer.dart';
import 'package:Kelivo/features/story_runtime/skills/story_skill_package_store.dart';

const _sha1 = '1111111111111111111111111111111111111111';
const _sha2 = '2222222222222222222222222222222222222222';

void main() {
  group('Story Skill GitHub source', () {
    late Directory tempDir;
    late _MemorySkillPackageRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kelivo_github_skill_');
      repository = _MemorySkillPackageRepository();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('parses repository and tree URLs without trusting other hosts', () {
      final simple = StorySkillGitHubSource.parse('blader/humanizer');
      expect(simple.repositoryKey, 'blader/humanizer');
      expect(simple.ref, isNull);

      final tree = StorySkillGitHubSource.parse(
        'https://github.com/example/skills/tree/dev/writing/humanizer',
      );
      expect(tree.repositoryKey, 'example/skills');
      expect(tree.ref, 'dev');
      expect(tree.subdirectory, 'writing/humanizer');

      expect(
        () => StorySkillGitHubSource.parse('https://example.com/a/b'),
        throwsA(isA<StorySkillGitHubException>()),
      );
    });

    test(
      'installs a standard SKILL.md repository in prompt-only safe mode',
      () async {
        final zip = _skillArchive(
          skillMarkdown: '''---
name: Humanizer
description: Make prose more natural.
---
Write with natural rhythm and preserve meaning.
''',
          extraFiles: <String, String>{
            'prompts/10-check.md': 'Check repetitive sentence scaffolding.',
            'scripts/ignored.sh': 'echo no',
          },
        );
        final client = _githubClient(zipBySha: <String, List<int>>{_sha1: zip});
        final importer = StorySkillPackageImporter(
          repository: repository,
          appDataRootResolver: () async => tempDir,
        );
        final service = StorySkillGitHubService(
          repository: repository,
          importer: importer,
          client: client,
          appDataRootResolver: () async => tempDir,
          tempRootResolver: () async => tempDir,
        );

        final result = await service.install(
          repositoryUrl: 'https://github.com/blader/humanizer',
        );

        expect(result.package.skillId, 'github.blader.humanizer');
        expect(result.package.version, 'gh-${_sha1.substring(0, 12)}');
        expect(result.package.isGitHubManaged, isTrue);
        expect(result.package.sourceRepository, 'blader/humanizer');
        expect(result.package.sourceCommitSha, _sha1);
        expect(result.ref, 'main');
        expect(result.replacedVersions, 0);

        final installed = Directory(
          '${tempDir.path}/${result.package.relativeRoot}',
        );
        expect(await File('${installed.path}/SKILL.md').exists(), isTrue);
        expect(
          await File('${installed.path}/prompts/10-check.md').exists(),
          isTrue,
        );
        expect(
          await File('${installed.path}/scripts/ignored.sh').exists(),
          isFalse,
        );

        final manifest =
            jsonDecode(
                  await File('${installed.path}/manifest.json').readAsString(),
                )
                as Map<String, dynamic>;
        expect(manifest['id'], 'github.blader.humanizer');
        expect(manifest['permissions'], isNull);
        expect(
          (manifest['metadata'] as Map<String, dynamic>)['source_commit_sha'],
          _sha1,
        );
      },
    );

    test(
      'detects a newer commit and atomically retires the old source version',
      () async {
        var latestSha = _sha1;
        final zip1 = _skillArchive(skillMarkdown: 'Version one.');
        final zip2 = _skillArchive(skillMarkdown: 'Version two.');
        final client = MockClient((request) async {
          final path = request.url.path;
          if (path == '/repos/blader/humanizer') {
            return http.Response(
              jsonEncode(<String, Object>{'default_branch': 'main'}),
              200,
            );
          }
          if (path == '/repos/blader/humanizer/commits/main') {
            return http.Response(
              jsonEncode(<String, Object>{'sha': latestSha}),
              200,
            );
          }
          if (path.endsWith('/zipball/$_sha1')) {
            return http.Response.bytes(zip1, 200);
          }
          if (path.endsWith('/zipball/$_sha2')) {
            return http.Response.bytes(zip2, 200);
          }
          return http.Response('not found', 404);
        });
        final importer = StorySkillPackageImporter(
          repository: repository,
          appDataRootResolver: () async => tempDir,
        );
        final service = StorySkillGitHubService(
          repository: repository,
          importer: importer,
          client: client,
          appDataRootResolver: () async => tempDir,
          tempRootResolver: () async => tempDir,
        );

        final first = await service.install(repositoryUrl: 'blader/humanizer');
        latestSha = _sha2;
        final check = await service.checkForUpdate(first.package);
        expect(check.updateAvailable, isTrue);
        expect(check.latestCommitSha, _sha2);

        final second = await service.update(first.package);
        expect(second.package.sourceCommitSha, _sha2);
        expect(second.replacedVersions, 1);
        final records = await repository.readAll();
        expect(records, hasLength(1));
        expect(records.single.version, 'gh-${_sha2.substring(0, 12)}');
        expect(
          await Directory(
            '${tempDir.path}/${first.package.relativeRoot}',
          ).exists(),
          isFalse,
        );
        expect(
          await Directory(
            '${tempDir.path}/${second.package.relativeRoot}',
          ).exists(),
          isTrue,
        );
      },
    );

    test(
      'rejects GitHub packages that try to gain runtime capabilities',
      () async {
        final zip = _skillArchive(
          skillMarkdown: 'Do useful work.',
          manifest: <String, Object?>{
            'id': 'dangerous',
            'name': 'Dangerous',
            'version': '1',
            'mcp_servers': <String>['mcp.github'],
            'permissions': <String>['mcp'],
          },
        );
        final importer = StorySkillPackageImporter(
          repository: repository,
          appDataRootResolver: () async => tempDir,
        );
        final service = StorySkillGitHubService(
          repository: repository,
          importer: importer,
          client: _githubClient(zipBySha: <String, List<int>>{_sha1: zip}),
          appDataRootResolver: () async => tempDir,
          tempRootResolver: () async => tempDir,
        );

        expect(
          () => service.install(repositoryUrl: 'blader/humanizer'),
          throwsA(
            isA<StorySkillGitHubException>().having(
              (error) => error.code,
              'code',
              'capabilities_require_local_zip_review',
            ),
          ),
        );
        expect(await repository.readAll(), isEmpty);
      },
    );
  });
}

MockClient _githubClient({required Map<String, List<int>> zipBySha}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path == '/repos/blader/humanizer') {
      return http.Response(
        jsonEncode(<String, Object>{'default_branch': 'main'}),
        200,
      );
    }
    if (path == '/repos/blader/humanizer/commits/main') {
      return http.Response(jsonEncode(<String, Object>{'sha': _sha1}), 200);
    }
    for (final entry in zipBySha.entries) {
      if (path.endsWith('/zipball/${entry.key}')) {
        return http.Response.bytes(entry.value, 200);
      }
    }
    return http.Response('not found', 404);
  });
}

List<int> _skillArchive({
  required String skillMarkdown,
  Map<String, Object?>? manifest,
  Map<String, String> extraFiles = const <String, String>{},
}) {
  const root = 'blader-humanizer-1234567';
  final archive = Archive()
    ..add(ArchiveFile.string('$root/SKILL.md', skillMarkdown));
  if (manifest != null) {
    archive.add(
      ArchiveFile.string('$root/manifest.json', jsonEncode(manifest)),
    );
  }
  for (final entry in extraFiles.entries) {
    archive.add(ArchiveFile.string('$root/${entry.key}', entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

final class _MemorySkillPackageRepository
    implements StorySkillPackageRepository {
  final List<StoryInstalledSkillPackage> items = <StoryInstalledSkillPackage>[];

  @override
  Future<List<StoryInstalledSkillPackage>> readAll() async =>
      List<StoryInstalledSkillPackage>.unmodifiable(items);

  @override
  Future<StoryInstalledSkillPackage?> read(
    String skillId,
    String version,
  ) async {
    for (final item in items) {
      if (item.skillId == skillId && item.version == version) return item;
    }
    return null;
  }

  @override
  Future<void> upsert(StoryInstalledSkillPackage package) async {
    items.removeWhere(
      (item) =>
          item.skillId == package.skillId && item.version == package.version,
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
