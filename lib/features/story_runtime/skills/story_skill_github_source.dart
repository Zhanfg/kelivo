import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../utils/app_directories.dart';
import 'story_skill_package_importer.dart';
import 'story_skill_package_store.dart';

typedef StorySkillGitHubRootResolver = Future<Directory> Function();

final class StorySkillGitHubSource {
  const StorySkillGitHubSource({
    required this.owner,
    required this.repository,
    this.ref,
    this.subdirectory,
  });

  final String owner;
  final String repository;
  final String? ref;
  final String? subdirectory;

  String get repositoryKey => '$owner/$repository';
  String get repositoryUrl => 'https://github.com/$owner/$repository';

  StorySkillGitHubSource copyWith({String? ref, String? subdirectory}) =>
      StorySkillGitHubSource(
        owner: owner,
        repository: repository,
        ref: ref ?? this.ref,
        subdirectory: subdirectory ?? this.subdirectory,
      );

  static StorySkillGitHubSource parse(
    String value, {
    String? ref,
    String? subdirectory,
  }) {
    var raw = value.trim();
    if (raw.isEmpty) {
      throw const StorySkillGitHubException('repository_url_missing');
    }
    if (!raw.contains('://')) raw = 'https://github.com/$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com') {
      throw const StorySkillGitHubException('repository_url_invalid');
    }
    final parts = uri.pathSegments.where((item) => item.isNotEmpty).toList();
    if (parts.length < 2) {
      throw const StorySkillGitHubException('repository_url_invalid');
    }
    final owner = parts[0];
    var repository = parts[1];
    if (repository.endsWith('.git')) {
      repository = repository.substring(0, repository.length - 4);
    }
    if (!_safeGithubName(owner) || !_safeGithubName(repository)) {
      throw const StorySkillGitHubException('repository_identity_invalid');
    }

    String? urlRef;
    String? urlPath;
    if (parts.length >= 4 && parts[2] == 'tree') {
      urlRef = parts[3];
      if (parts.length > 4) urlPath = parts.sublist(4).join('/');
    }
    final resolvedRef = _normalizedOptional(ref) ?? _normalizedOptional(urlRef);
    final resolvedPath = _normalizeSubdirectory(
      _normalizedOptional(subdirectory) ?? _normalizedOptional(urlPath),
    );
    return StorySkillGitHubSource(
      owner: owner,
      repository: repository,
      ref: resolvedRef,
      subdirectory: resolvedPath,
    );
  }
}

final class StorySkillGitHubUpdateCheck {
  const StorySkillGitHubUpdateCheck({
    required this.currentCommitSha,
    required this.latestCommitSha,
    required this.ref,
  });

  final String currentCommitSha;
  final String latestCommitSha;
  final String ref;

  bool get updateAvailable => currentCommitSha != latestCommitSha;
}

final class StorySkillGitHubInstallResult {
  const StorySkillGitHubInstallResult({
    required this.importResult,
    required this.package,
    required this.source,
    required this.commitSha,
    required this.ref,
    required this.replacedVersions,
  });

  final StorySkillPackageImportResult importResult;
  final StoryInstalledSkillPackage package;
  final StorySkillGitHubSource source;
  final String commitSha;
  final String ref;
  final int replacedVersions;
}

final class StorySkillGitHubException implements Exception {
  const StorySkillGitHubException(this.code, {this.detail});

  final String code;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StorySkillGitHubException($code)'
      : 'StorySkillGitHubException($code: $detail)';
}

/// Installs prompt/data-only Agent Skills from public GitHub repositories.
///
/// GitHub source installs are deliberately capability-safe: executable files
/// are discarded and a source package that declares MCP/tools/permissions or
/// hooks is rejected. Capability-bearing packages must still go through the
/// local ZIP review/import path so GitHub updates cannot silently expand app
/// privileges.
final class StorySkillGitHubService {
  StorySkillGitHubService({
    required StorySkillPackageRepository repository,
    required StorySkillPackageImporter importer,
    http.Client? client,
    StorySkillGitHubRootResolver? appDataRootResolver,
    this.maxDownloadBytes = 128 * 1024 * 1024,
  }) : _repository = repository,
       _importer = importer,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _appDataRootResolver =
           appDataRootResolver ?? AppDirectories.getAppDataDirectory;

  final StorySkillPackageRepository _repository;
  final StorySkillPackageImporter _importer;
  final http.Client _client;
  final bool _ownsClient;
  final StorySkillGitHubRootResolver _appDataRootResolver;
  final int maxDownloadBytes;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<StorySkillGitHubInstallResult> install({
    required String repositoryUrl,
    String? ref,
    String? subdirectory,
  }) async {
    final source = StorySkillGitHubSource.parse(
      repositoryUrl,
      ref: ref,
      subdirectory: subdirectory,
    );
    final resolvedRef = source.ref ?? await _defaultBranch(source);
    final commitSha = await _resolveCommit(source, resolvedRef);
    final zipBytes = await _downloadZipball(source, commitSha);
    final adapted = await _adaptRepositoryZip(
      source: source,
      resolvedRef: resolvedRef,
      commitSha: commitSha,
      zipBytes: zipBytes,
    );

    StorySkillPackageImportResult imported;
    try {
      imported = await _importer.importZip(adapted.path);
    } finally {
      try {
        if (await adapted.exists()) await adapted.delete();
        final parent = adapted.parent;
        if (await parent.exists() && await parent.list().isEmpty) {
          await parent.delete();
        }
      } catch (_) {}
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final enriched = imported.package.copyWith(
      sourceProvider: 'github',
      sourceRepository: source.repositoryKey,
      sourceRef: resolvedRef,
      sourceSubdirectory: source.subdirectory,
      sourceCommitSha: commitSha,
      sourceCheckedAtMs: now,
    );
    await _repository.upsert(enriched);

    final replaced = await _removePreviousSourceVersions(
      source: source,
      keepSkillId: enriched.skillId,
      keepVersion: enriched.version,
    );
    return StorySkillGitHubInstallResult(
      importResult: imported,
      package: enriched,
      source: source,
      commitSha: commitSha,
      ref: resolvedRef,
      replacedVersions: replaced,
    );
  }

  Future<StorySkillGitHubUpdateCheck> checkForUpdate(
    StoryInstalledSkillPackage package,
  ) async {
    if (!package.isGitHubManaged ||
        package.sourceRepository == null ||
        package.sourceCommitSha == null) {
      throw const StorySkillGitHubException('package_not_github_managed');
    }
    final source = StorySkillGitHubSource.parse(
      package.sourceRepository!,
      ref: package.sourceRef,
      subdirectory: package.sourceSubdirectory,
    );
    final resolvedRef = source.ref ?? await _defaultBranch(source);
    final latest = await _resolveCommit(source, resolvedRef);
    await _repository.upsert(
      package.copyWith(sourceCheckedAtMs: DateTime.now().millisecondsSinceEpoch),
    );
    return StorySkillGitHubUpdateCheck(
      currentCommitSha: package.sourceCommitSha!,
      latestCommitSha: latest,
      ref: resolvedRef,
    );
  }

  Future<StorySkillGitHubInstallResult> update(
    StoryInstalledSkillPackage package,
  ) async {
    if (!package.isGitHubManaged || package.sourceRepository == null) {
      throw const StorySkillGitHubException('package_not_github_managed');
    }
    return install(
      repositoryUrl: package.sourceRepository!,
      ref: package.sourceRef,
      subdirectory: package.sourceSubdirectory,
    );
  }

  Future<String> _defaultBranch(StorySkillGitHubSource source) async {
    final response = await _getJson(
      Uri.https('api.github.com', '/repos/${source.repositoryKey}'),
    );
    final branch = response['default_branch'];
    if (branch is! String || branch.trim().isEmpty) {
      throw const StorySkillGitHubException('default_branch_missing');
    }
    return branch.trim();
  }

  Future<String> _resolveCommit(
    StorySkillGitHubSource source,
    String ref,
  ) async {
    final encodedRef = Uri.encodeComponent(ref);
    final response = await _getJson(
      Uri.parse(
        'https://api.github.com/repos/${source.repositoryKey}/commits/$encodedRef',
      ),
    );
    final sha = response['sha'];
    if (sha is! String || !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha)) {
      throw const StorySkillGitHubException('commit_sha_invalid');
    }
    return sha;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StorySkillGitHubException(
        'github_http_error',
        detail: '${response.statusCode} ${uri.path}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const StorySkillGitHubException('github_json_invalid');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<List<int>> _downloadZipball(
    StorySkillGitHubSource source,
    String commitSha,
  ) async {
    final response = await _client.get(
      Uri.parse(
        'https://api.github.com/repos/${source.repositoryKey}/zipball/$commitSha',
      ),
      headers: const <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StorySkillGitHubException(
        'github_download_failed',
        detail: '${response.statusCode}',
      );
    }
    if (response.bodyBytes.length > maxDownloadBytes) {
      throw const StorySkillGitHubException('github_archive_too_large');
    }
    return response.bodyBytes;
  }

  Future<File> _adaptRepositoryZip({
    required StorySkillGitHubSource source,
    required String resolvedRef,
    required String commitSha,
    required List<int> zipBytes,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    final normalized = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      if (entry.symbolicLink != null) {
        throw const StorySkillGitHubException('symlink_not_allowed');
      }
      final path = _safeArchivePath(entry.name);
      if (path == null || path.isEmpty) continue;
      if (normalized.containsKey(path)) {
        throw StorySkillGitHubException('duplicate_archive_path', detail: path);
      }
      normalized[path] = entry;
    }
    if (normalized.isEmpty) {
      throw const StorySkillGitHubException('github_archive_empty');
    }

    final root = _commonArchiveRoot(normalized.keys);
    final relative = <String, ArchiveFile>{};
    for (final entry in normalized.entries) {
      if (!entry.key.startsWith('$root/')) continue;
      relative[entry.key.substring(root.length + 1)] = entry.value;
    }

    final skillRoot = _selectSkillRoot(relative, source.subdirectory);
    final skillEntry = relative[
      skillRoot.isEmpty ? 'SKILL.md' : '$skillRoot/SKILL.md'
    ];
    if (skillEntry == null || !skillEntry.isFile) {
      throw const StorySkillGitHubException('skill_markdown_missing');
    }
    final skillMarkdown = _decodeText(skillEntry);
    final manifestPath = skillRoot.isEmpty
        ? 'manifest.json'
        : '$skillRoot/manifest.json';
    final upstreamManifest = relative[manifestPath];
    Map<String, dynamic>? manifestJson;
    if (upstreamManifest != null && upstreamManifest.isFile) {
      final decoded = jsonDecode(_decodeText(upstreamManifest));
      if (decoded is Map && decoded.keys.every((key) => key is String)) {
        manifestJson = decoded.cast<String, dynamic>();
        _rejectPrivilegedManifest(manifestJson);
      }
    }

    final frontmatter = _parseFrontmatter(skillMarkdown);
    final rawName = _firstString(<Object?>[
      manifestJson?['name'],
      frontmatter['name'],
      skillRoot.isEmpty ? source.repository : p.basename(skillRoot),
    ]);
    final rawDescription = _firstString(<Object?>[
      manifestJson?['description'],
      frontmatter['description'],
    ]);
    final stableSlug = _skillSlug(
      _firstString(<Object?>[
        manifestJson?['id'],
        frontmatter['name'],
        skillRoot.isEmpty ? source.repository : p.basename(skillRoot),
      ]),
    );
    final ownerSlug = _skillSlug(source.owner);
    final skillId = _boundedId('github.$ownerSlug.$stableSlug');
    final version = 'gh-${commitSha.substring(0, 12)}';
    final generatedManifest = <String, Object?>{
      'schema_version': 1,
      'id': skillId,
      'name': rawName,
      'version': version,
      if (rawDescription.isNotEmpty) 'description': rawDescription,
      'activation': <String, Object?>{
        'modes': <String>['manual'],
      },
      'metadata': <String, Object?>{
        'source_provider': 'github',
        'source_repository': source.repositoryKey,
        'source_url': source.repositoryUrl,
        'source_ref': resolvedRef,
        'source_commit_sha': commitSha,
        if (skillRoot.isNotEmpty) 'source_subdirectory': skillRoot,
        'github_safe_mode': true,
      },
    };

    final output = Archive()
      ..add(ArchiveFile.string('manifest.json', jsonEncode(generatedManifest)))
      ..add(ArchiveFile.string('SKILL.md', skillMarkdown));
    final prefix = skillRoot.isEmpty ? '' : '$skillRoot/';
    for (final entry in relative.entries) {
      if (!entry.value.isFile || !entry.key.startsWith(prefix)) continue;
      final child = entry.key.substring(prefix.length);
      if (!_allowedPackageChild(child) ||
          child == 'SKILL.md' ||
          child == 'manifest.json') {
        continue;
      }
      final bytes = entry.value.readBytes();
      if (bytes == null) continue;
      output.add(ArchiveFile(child, bytes.length, bytes));
    }

    final temp = await getTemporaryDirectory();
    final dir = await temp.createTemp('kelivo_github_skill_');
    final file = File('${dir.path}/skill.zip');
    final encoded = ZipEncoder().encodeBytes(output);
    if (encoded.length > _importer.maxSourceBytes) {
      await dir.delete(recursive: true);
      throw const StorySkillGitHubException('adapted_package_too_large');
    }
    await file.writeAsBytes(encoded, flush: true);
    return file;
  }

  Future<int> _removePreviousSourceVersions({
    required StorySkillGitHubSource source,
    required String keepSkillId,
    required String keepVersion,
  }) async {
    final all = await _repository.readAll();
    var removed = 0;
    final root = await _appDataRootResolver();
    for (final item in all) {
      if (!item.isGitHubManaged ||
          item.sourceRepository != source.repositoryKey ||
          _normalizeSubdirectory(item.sourceSubdirectory) !=
              _normalizeSubdirectory(source.subdirectory) ||
          (item.skillId == keepSkillId && item.version == keepVersion)) {
        continue;
      }
      await _repository.remove(item.skillId, item.version);
      if (_safeRelativeRoot(item.relativeRoot)) {
        final directory = Directory('${root.path}/${item.relativeRoot}');
        try {
          if (await directory.exists()) await directory.delete(recursive: true);
        } catch (_) {}
      }
      removed++;
    }
    return removed;
  }
}

void _rejectPrivilegedManifest(Map<String, dynamic> manifest) {
  bool nonEmpty(Object? value) => switch (value) {
    List<Object?> list => list.isNotEmpty,
    Map<Object?, Object?> map => map.isNotEmpty,
    String text => text.trim().isNotEmpty,
    _ => false,
  };
  for (final key in const <String>[
    'mcp_servers',
    'tools',
    'permissions',
    'hooks',
  ]) {
    if (nonEmpty(manifest[key])) {
      throw StorySkillGitHubException(
        'capabilities_require_local_zip_review',
        detail: key,
      );
    }
  }
  final memory = manifest['memory'];
  if (memory is Map && memory.isNotEmpty) {
    throw const StorySkillGitHubException(
      'capabilities_require_local_zip_review',
      detail: 'memory',
    );
  }
}

String _selectSkillRoot(
  Map<String, ArchiveFile> entries,
  String? requestedSubdirectory,
) {
  final requested = _normalizeSubdirectory(requestedSubdirectory);
  if (requested != null) {
    if (entries.containsKey('$requested/SKILL.md')) return requested;
    throw StorySkillGitHubException(
      'skill_subdirectory_missing',
      detail: requested,
    );
  }
  if (entries.containsKey('SKILL.md')) return '';
  final candidates = entries.keys
      .where((path) => path.endsWith('/SKILL.md'))
      .map((path) => path.substring(0, path.length - '/SKILL.md'.length))
      .toList(growable: false)
    ..sort((a, b) {
      final depth = a.split('/').length.compareTo(b.split('/').length);
      return depth != 0 ? depth : a.compareTo(b);
    });
  if (candidates.isEmpty) {
    throw const StorySkillGitHubException('skill_markdown_missing');
  }
  final depth = candidates.first.split('/').length;
  if (candidates.length > 1 && candidates[1].split('/').length == depth) {
    throw const StorySkillGitHubException('skill_path_ambiguous');
  }
  return candidates.first;
}

Map<String, String> _parseFrontmatter(String markdown) {
  if (!markdown.startsWith('---')) return const <String, String>{};
  final lines = const LineSplitter().convert(markdown);
  if (lines.isEmpty || lines.first.trim() != '---') {
    return const <String, String>{};
  }
  final result = <String, String>{};
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim() == '---') break;
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim().toLowerCase();
    var value = line.substring(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isNotEmpty) result[key] = value;
  }
  return result;
}

String _commonArchiveRoot(Iterable<String> paths) {
  String? root;
  for (final path in paths) {
    final first = path.split('/').first;
    root ??= first;
    if (root != first) {
      throw const StorySkillGitHubException('github_archive_root_invalid');
    }
  }
  if (root == null || root.isEmpty) {
    throw const StorySkillGitHubException('github_archive_root_invalid');
  }
  return root;
}

String? _safeArchivePath(String raw) {
  final normalized = raw.replaceAll('\\', '/');
  if (normalized.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
    throw const StorySkillGitHubException('absolute_path_not_allowed');
  }
  final parts = <String>[];
  for (final value in normalized.split('/')) {
    final part = value.trim();
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      throw const StorySkillGitHubException('path_traversal');
    }
    parts.add(part);
  }
  return parts.join('/');
}

bool _allowedPackageChild(String value) =>
    value.startsWith('prompts/') ||
    value.startsWith('assets/') ||
    value.startsWith('worldbooks/') ||
    value.startsWith('templates/');

String _decodeText(ArchiveFile entry) {
  final bytes = entry.readBytes();
  if (bytes == null) {
    throw StorySkillGitHubException('package_file_unreadable', detail: entry.name);
  }
  return utf8.decode(bytes, allowMalformed: true).trim();
}

String _firstString(List<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

String _skillSlug(String value) {
  final lower = value.trim().toLowerCase();
  final slug = lower
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return slug.isEmpty ? 'skill' : slug;
}

String _boundedId(String value) {
  if (value.length <= 96) return value;
  return value.substring(0, 96).replaceAll(RegExp(r'[-._]+$'), '');
}

bool _safeGithubName(String value) =>
    RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(value);

String? _normalizedOptional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _normalizeSubdirectory(String? value) {
  final normalized = _normalizedOptional(value)?.replaceAll('\\', '/');
  if (normalized == null) return null;
  if (normalized.startsWith('/') ||
      normalized.split('/').any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const StorySkillGitHubException('subdirectory_invalid');
  }
  return normalized.replaceAll(RegExp(r'/+$'), '');
}

bool _safeRelativeRoot(String value) {
  final normalized = value.replaceAll('\\', '/');
  return normalized.startsWith('story_skills/') &&
      !normalized.startsWith('/') &&
      !normalized.split('/').contains('..');
}
