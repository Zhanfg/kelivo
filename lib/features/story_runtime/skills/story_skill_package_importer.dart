// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../utils/app_directories.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'story_skill_manifest_parser.dart';
import 'story_skill_models.dart';
import 'story_skill_package_store.dart';

typedef StorySkillRootResolver = Future<Directory> Function();

final class StorySkillPackageImportResult {
  const StorySkillPackageImportResult({
    required this.package,
    required this.manifest,
    required this.deduplicated,
  });

  final StoryInstalledSkillPackage package;
  final StorySkillManifest manifest;
  final bool deduplicated;
}

/// Installs a zipped Story Skill package into app-managed storage.
///
/// Package files are data only. No scripts or binaries are executed. Only the
/// documented Skill surfaces are extracted; MCP/tools still execute through
/// Kelivo's native permission and approval paths.
final class StorySkillPackageImporter {
  StorySkillPackageImporter({
    required StorySkillPackageRepository repository,
    StorySkillRootResolver? appDataRootResolver,
    this.parser = const StorySkillManifestParser(),
    this.maxSourceBytes = 128 * 1024 * 1024,
    this.maxExtractedBytes = 256 * 1024 * 1024,
    this.maxInstructionChars = 200000,
    this.maxFiles = 2048,
  }) : _repository = repository,
       _appDataRootResolver =
           appDataRootResolver ?? AppDirectories.getAppDataDirectory;

  final StorySkillPackageRepository _repository;
  final StorySkillRootResolver _appDataRootResolver;
  final StorySkillManifestParser parser;
  final int maxSourceBytes;
  final int maxExtractedBytes;
  final int maxInstructionChars;
  final int maxFiles;

  Future<StorySkillPackageImportResult> importZip(String path) async {
    final resolved = SandboxPathResolver.resolveForIo(path);
    if (resolved == null) {
      throw const StorySkillPackageException('source_path_unavailable');
    }
    final source = File(resolved);
    if (!await source.exists()) {
      throw const StorySkillPackageException('source_missing');
    }
    final size = await source.length();
    if (size > maxSourceBytes) {
      throw const StorySkillPackageException('source_too_large');
    }

    final root = await _appDataRootResolver();
    final skillsRoot = Directory('${root.path}/story_skills');
    await skillsRoot.create(recursive: true);
    final staging = Directory(
      '${skillsRoot.path}/.staging_${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create(recursive: true);

    late final Map<String, Object?> extracted;
    try {
      extracted = await compute(_extractSkillPackageTask, <String, Object?>{
        'source_path': resolved,
        'staging_path': staging.path,
        'max_files': maxFiles,
        'max_extracted_bytes': maxExtractedBytes,
      });
    } catch (_) {
      await _deleteBestEffort(staging);
      rethrow;
    }

    try {
      final manifestJson = extracted['manifest_json'];
      final skillMarkdown = extracted['skill_markdown'];
      final packageHash = extracted['package_hash'];
      final promptTextsRaw = extracted['prompt_texts'];
      if (manifestJson is! String ||
          skillMarkdown is! String ||
          packageHash is! String ||
          promptTextsRaw is! List) {
        throw const StorySkillPackageException('invalid_extraction_result');
      }
      final base = parser.parse(manifestJson);
      final promptTexts = promptTextsRaw.whereType<String>().toList();
      final manifest = _withPackageInstructions(
        base,
        skillMarkdown: skillMarkdown,
        promptTexts: promptTexts,
      );
      final instructionChars = manifest.instructions.fold<int>(
        0,
        (sum, instruction) => sum + instruction.length,
      );
      if (instructionChars > maxInstructionChars) {
        throw const StorySkillPackageException('instruction_budget_exceeded');
      }

      final existing = await _repository.read(manifest.id, manifest.version);
      if (existing != null) {
        await _deleteBestEffort(staging);
        if (existing.packageHash != packageHash) {
          throw const StorySkillPackageException('version_conflict');
        }
        return StorySkillPackageImportResult(
          package: existing,
          manifest: manifest,
          deduplicated: true,
        );
      }

      final relativeRoot = 'story_skills/${manifest.id}/${manifest.version}';
      if (!_safePackageDestination(manifest.id) ||
          !_safePackageDestination(manifest.version)) {
        throw const StorySkillPackageException('unsafe_manifest_identity');
      }
      final target = Directory('${root.path}/$relativeRoot');
      if (await target.exists()) {
        throw const StorySkillPackageException('target_already_exists');
      }
      await target.parent.create(recursive: true);
      await staging.rename(target.path);

      final record = StoryInstalledSkillPackage(
        skillId: manifest.id,
        version: manifest.version,
        relativeRoot: relativeRoot,
        packageHash: packageHash,
        installedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      try {
        await _repository.upsert(record);
      } catch (_) {
        await _deleteBestEffort(target);
        rethrow;
      }
      return StorySkillPackageImportResult(
        package: record,
        manifest: manifest,
        deduplicated: false,
      );
    } catch (_) {
      await _deleteBestEffort(staging);
      rethrow;
    }
  }
}

final class StorySkillPackageException implements Exception {
  const StorySkillPackageException(this.code, {this.detail});

  final String code;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StorySkillPackageException($code)'
      : 'StorySkillPackageException($code: $detail)';
}

Map<String, Object?> _extractSkillPackageTask(Map<String, Object?> params) {
  final sourcePath = params['source_path'];
  final stagingPath = params['staging_path'];
  final maxFiles = params['max_files'];
  final maxExtractedBytes = params['max_extracted_bytes'];
  if (sourcePath is! String ||
      stagingPath is! String ||
      maxFiles is! int ||
      maxExtractedBytes is! int) {
    throw const StorySkillPackageException('invalid_extract_params');
  }

  final sourceBytes = File(sourcePath).readAsBytesSync();
  final packageHash = sha256.convert(sourceBytes).toString();
  final archive = ZipDecoder().decodeBytes(sourceBytes, verify: true);
  if (archive.files.length > maxFiles) {
    throw const StorySkillPackageException('too_many_files');
  }

  var totalBytes = 0;
  final normalizedEntries = <String, ArchiveFile>{};
  for (final entry in archive.files) {
    if (entry.symbolicLink != null) {
      throw const StorySkillPackageException('symlink_not_allowed');
    }
    final path = _safeArchivePath(entry.name);
    if (path == null || path.isEmpty) continue;
    if (normalizedEntries.containsKey(path)) {
      throw StorySkillPackageException('duplicate_package_path', detail: path);
    }
    normalizedEntries[path] = entry;
    if (entry.isFile) {
      totalBytes += entry.size;
      if (totalBytes > maxExtractedBytes) {
        throw const StorySkillPackageException('package_too_large');
      }
    }
  }

  final manifestCandidates = normalizedEntries.keys
      .where((path) => path == 'manifest.json' || path.endsWith('/manifest.json'))
      .toList(growable: false)
    ..sort((a, b) {
      final depth = _pathDepth(a).compareTo(_pathDepth(b));
      return depth != 0 ? depth : a.compareTo(b);
    });
  if (manifestCandidates.isEmpty) {
    throw const StorySkillPackageException('manifest_missing');
  }
  final manifestPath = manifestCandidates.first;
  final shortestDepth = _pathDepth(manifestPath);
  if (manifestCandidates.length > 1 &&
      _pathDepth(manifestCandidates[1]) == shortestDepth) {
    throw const StorySkillPackageException('manifest_ambiguous');
  }
  final rootPrefix = manifestPath == 'manifest.json'
      ? ''
      : manifestPath.substring(0, manifestPath.length - 'manifest.json'.length);
  final skillPath = '${rootPrefix}SKILL.md';
  final skillEntry = normalizedEntries[skillPath];
  if (skillEntry == null || !skillEntry.isFile) {
    throw const StorySkillPackageException('skill_markdown_missing');
  }

  bool allowedRelative(String relative) {
    if (relative == 'manifest.json' || relative == 'SKILL.md') return true;
    return relative.startsWith('prompts/') ||
        relative.startsWith('assets/') ||
        relative.startsWith('worldbooks/') ||
        relative.startsWith('templates/');
  }

  final promptTextByPath = <String, String>{};
  for (final mapEntry in normalizedEntries.entries) {
    final fullPath = mapEntry.key;
    if (!fullPath.startsWith(rootPrefix)) continue;
    final relative = fullPath.substring(rootPrefix.length);
    if (relative.isEmpty || !allowedRelative(relative)) continue;
    final entry = mapEntry.value;
    if (!entry.isFile) continue;
    final bytes = _readArchiveBytes(entry);
    final output = File('$stagingPath/$relative');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes, flush: true);

    if (relative.startsWith('prompts/') &&
        (relative.toLowerCase().endsWith('.md') ||
            relative.toLowerCase().endsWith('.txt'))) {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isNotEmpty) promptTextByPath[relative] = text;
    }
  }

  final manifestJson = utf8.decode(
    _readArchiveBytes(normalizedEntries[manifestPath]!),
    allowMalformed: true,
  );
  final skillMarkdown = utf8.decode(
    _readArchiveBytes(skillEntry),
    allowMalformed: true,
  ).trim();
  final promptPaths = promptTextByPath.keys.toList(growable: false)..sort();
  final promptTexts = [for (final path in promptPaths) promptTextByPath[path]!];

  return <String, Object?>{
    'manifest_json': manifestJson,
    'skill_markdown': skillMarkdown,
    'prompt_texts': promptTexts,
    'package_hash': packageHash,
  };
}

StorySkillManifest _withPackageInstructions(
  StorySkillManifest base, {
  required String skillMarkdown,
  required List<String> promptTexts,
}) {
  final instructions = <String>[
    if (skillMarkdown.trim().isNotEmpty) skillMarkdown.trim(),
    ...promptTexts.map((text) => text.trim()).where((text) => text.isNotEmpty),
    ...base.instructions,
  ];
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

List<int> _readArchiveBytes(ArchiveFile file) {
  final bytes = file.readBytes();
  if (bytes == null) {
    throw StorySkillPackageException('package_file_unreadable', detail: file.name);
  }
  return bytes;
}

String? _safeArchivePath(String value) {
  final normalized = value.replaceAll('\\', '/');
  if (normalized.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
    throw const StorySkillPackageException('absolute_path_not_allowed');
  }
  final parts = <String>[];
  for (final raw in normalized.split('/')) {
    final part = raw.trim();
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      throw const StorySkillPackageException('path_traversal');
    }
    parts.add(part);
  }
  return parts.join('/');
}

int _pathDepth(String value) => value.split('/').length;

bool _safePackageDestination(String value) =>
    RegExp(r'^[a-zA-Z0-9._-]{1,96}$').hasMatch(value);

Future<void> _deleteBestEffort(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {}
}
