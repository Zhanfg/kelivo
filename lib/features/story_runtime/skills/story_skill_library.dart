// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import '../../../utils/app_directories.dart';
import 'built_in_story_skills.dart';
import 'story_skill_manifest_parser.dart';
import 'story_skill_models.dart';
import 'story_skill_package_store.dart';

typedef StorySkillLibraryRootResolver = Future<Directory> Function();

/// Loads installed Skill packages after app restart.
final class StorySkillLibrary {
  StorySkillLibrary({
    required StorySkillPackageRepository repository,
    StorySkillLibraryRootResolver? appDataRootResolver,
    this.parser = const StorySkillManifestParser(),
    this.maxInstructionChars = 200000,
  }) : _repository = repository,
       _appDataRootResolver =
           appDataRootResolver ?? AppDirectories.getAppDataDirectory;

  final StorySkillPackageRepository _repository;
  final StorySkillLibraryRootResolver _appDataRootResolver;
  final StorySkillManifestParser parser;
  final int maxInstructionChars;

  Future<List<StorySkillManifest>> loadAll() async {
    final packages = await _repository.readAll();
    final manifestsById = <String, StorySkillManifest>{
      for (final manifest in await loadBuiltInStorySkills()) manifest.id: manifest,
    };
    for (final package in packages) {
      final manifest = await load(package);
      manifestsById[manifest.id] = manifest;
    }
    final manifests = manifestsById.values.toList(growable: false);
    manifests.sort((a, b) {
      final id = a.id.compareTo(b.id);
      return id != 0 ? id : a.version.compareTo(b.version);
    });
    return List.unmodifiable(manifests);
  }

  Future<StorySkillManifest> load(StoryInstalledSkillPackage package) async {
    if (!_safeRelativeRoot(package.relativeRoot)) {
      throw const StorySkillLibraryException('unsafe_package_root');
    }
    final appRoot = await _appDataRootResolver();
    final root = Directory('${appRoot.path}/${package.relativeRoot}');
    if (!await root.exists()) {
      throw const StorySkillLibraryException('package_root_missing');
    }

    final manifestFile = File('${root.path}/manifest.json');
    final skillFile = File('${root.path}/SKILL.md');
    if (!await manifestFile.exists() || !await skillFile.exists()) {
      throw const StorySkillLibraryException('package_core_files_missing');
    }

    final base = parser.parse(await manifestFile.readAsString());
    if (base.id != package.skillId || base.version != package.version) {
      throw const StorySkillLibraryException('package_identity_mismatch');
    }

    final promptFiles = <File>[];
    final promptsDir = Directory('${root.path}/prompts');
    if (await promptsDir.exists()) {
      await for (final entity in promptsDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.md') || lower.endsWith('.txt')) {
          promptFiles.add(entity);
        }
      }
    }
    promptFiles.sort((a, b) => a.path.compareTo(b.path));

    final instructions = <String>[];
    final skillMarkdown = (await skillFile.readAsString()).trim();
    if (skillMarkdown.isNotEmpty) instructions.add(skillMarkdown);
    for (final file in promptFiles) {
      final text = (await file.readAsString()).trim();
      if (text.isNotEmpty) instructions.add(text);
    }
    instructions.addAll(base.instructions);

    final chars = instructions.fold<int>(
      0,
      (sum, instruction) => sum + instruction.length,
    );
    if (chars > maxInstructionChars) {
      throw const StorySkillLibraryException('instruction_budget_exceeded');
    }

    return StorySkillManifest(
      id: base.id,
      name: base.name,
      version: base.version,
      description: base.description,
      instructions: List.unmodifiable(instructions),
      worldBookIds: base.worldBookIds,
      mcpServerIds: base.mcpServerIds,
      toolIds: base.toolIds,
      memoryReadCategories: base.memoryReadCategories,
      memoryWriteCategories: base.memoryWriteCategories,
      ttsPolicy: base.ttsPolicy,
      activationModes: base.activationModes,
      activationSceneTags: base.activationSceneTags,
      activationConditionIds: base.activationConditionIds,
      permissions: base.permissions,
      hooks: base.hooks,
      compatibility: base.compatibility,
      assets: base.assets,
      templates: base.templates,
      metadata: base.metadata,
    );
  }
}

final class StorySkillLibraryException implements Exception {
  const StorySkillLibraryException(this.code);

  final String code;

  @override
  String toString() => 'StorySkillLibraryException($code)';
}

bool _safeRelativeRoot(String value) {
  final normalized = value.replaceAll('\\', '/');
  if (!normalized.startsWith('story_skills/') ||
      normalized.startsWith('/') ||
      normalized.split('/').contains('..')) {
    return false;
  }
  return normalized.isNotEmpty;
}
