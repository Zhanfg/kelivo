import '../../../core/services/json_blob_store.dart';

final class StoryInstalledSkillPackage {
  const StoryInstalledSkillPackage({
    required this.skillId,
    required this.version,
    required this.relativeRoot,
    required this.packageHash,
    required this.installedAtMs,
    this.sourceProvider,
    this.sourceRepository,
    this.sourceRef,
    this.sourceSubdirectory,
    this.sourceCommitSha,
    this.sourceCheckedAtMs,
  });

  final String skillId;
  final String version;
  final String relativeRoot;
  final String packageHash;
  final int installedAtMs;
  final String? sourceProvider;
  final String? sourceRepository;
  final String? sourceRef;
  final String? sourceSubdirectory;
  final String? sourceCommitSha;
  final int? sourceCheckedAtMs;

  bool get isGitHubManaged =>
      sourceProvider == 'github' &&
      sourceRepository != null &&
      sourceRepository!.isNotEmpty &&
      sourceCommitSha != null &&
      sourceCommitSha!.isNotEmpty;

  StoryInstalledSkillPackage copyWith({
    String? skillId,
    String? version,
    String? relativeRoot,
    String? packageHash,
    int? installedAtMs,
    String? sourceProvider,
    String? sourceRepository,
    String? sourceRef,
    String? sourceSubdirectory,
    String? sourceCommitSha,
    int? sourceCheckedAtMs,
  }) => StoryInstalledSkillPackage(
    skillId: skillId ?? this.skillId,
    version: version ?? this.version,
    relativeRoot: relativeRoot ?? this.relativeRoot,
    packageHash: packageHash ?? this.packageHash,
    installedAtMs: installedAtMs ?? this.installedAtMs,
    sourceProvider: sourceProvider ?? this.sourceProvider,
    sourceRepository: sourceRepository ?? this.sourceRepository,
    sourceRef: sourceRef ?? this.sourceRef,
    sourceSubdirectory: sourceSubdirectory ?? this.sourceSubdirectory,
    sourceCommitSha: sourceCommitSha ?? this.sourceCommitSha,
    sourceCheckedAtMs: sourceCheckedAtMs ?? this.sourceCheckedAtMs,
  );
}

abstract interface class StorySkillPackageRepository {
  Future<List<StoryInstalledSkillPackage>> readAll();
  Future<StoryInstalledSkillPackage?> read(String skillId, String version);
  Future<void> upsert(StoryInstalledSkillPackage package);
  Future<void> remove(String skillId, String version);
}

final class StorySkillPackageStore
    extends JsonBlobStore<StoryInstalledSkillPackage>
    implements StorySkillPackageRepository {
  StorySkillPackageStore(super.preferences);

  static const String key = 'story_skill_packages_v1';

  @override
  String get storageKey => key;

  @override
  StoryInstalledSkillPackage decodeItem(Map<String, dynamic> json) =>
      StoryInstalledSkillPackage(
        skillId: _requiredString(json, 'skill_id'),
        version: _requiredString(json, 'version'),
        relativeRoot: _requiredString(json, 'relative_root'),
        packageHash: _requiredString(json, 'package_hash'),
        installedAtMs: _requiredInt(json, 'installed_at_ms'),
        sourceProvider: _optionalString(json, 'source_provider'),
        sourceRepository: _optionalString(json, 'source_repository'),
        sourceRef: _optionalString(json, 'source_ref'),
        sourceSubdirectory: _optionalString(json, 'source_subdirectory'),
        sourceCommitSha: _optionalString(json, 'source_commit_sha'),
        sourceCheckedAtMs: _optionalInt(json, 'source_checked_at_ms'),
      );

  @override
  Map<String, dynamic> encodeItem(
    StoryInstalledSkillPackage item,
  ) => <String, dynamic>{
    'skill_id': item.skillId,
    'version': item.version,
    'relative_root': item.relativeRoot,
    'package_hash': item.packageHash,
    'installed_at_ms': item.installedAtMs,
    if (item.sourceProvider != null) 'source_provider': item.sourceProvider,
    if (item.sourceRepository != null)
      'source_repository': item.sourceRepository,
    if (item.sourceRef != null) 'source_ref': item.sourceRef,
    if (item.sourceSubdirectory != null)
      'source_subdirectory': item.sourceSubdirectory,
    if (item.sourceCommitSha != null) 'source_commit_sha': item.sourceCommitSha,
    if (item.sourceCheckedAtMs != null)
      'source_checked_at_ms': item.sourceCheckedAtMs,
  };

  @override
  Future<StoryInstalledSkillPackage?> read(
    String skillId,
    String version,
  ) async {
    final sid = _normalize(skillId);
    final ver = _normalize(version);
    for (final item in await readAll()) {
      if (item.skillId == sid && item.version == ver) return item;
    }
    return null;
  }

  @override
  Future<void> upsert(StoryInstalledSkillPackage package) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryInstalledSkillPackage>[];
      var replaced = false;
      for (final item in items) {
        final same =
            item.skillId == package.skillId && item.version == package.version;
        if (!same) {
          next.add(item);
          continue;
        }
        if (!replaced) {
          next.add(package);
          replaced = true;
        }
      }
      if (!replaced) next.add(package);
      next.sort((a, b) {
        final skill = a.skillId.compareTo(b.skillId);
        return skill != 0 ? skill : a.version.compareTo(b.version);
      });
      await writeAll(next);
    });
  }

  @override
  Future<void> remove(String skillId, String version) {
    return runExclusive(() async {
      final sid = _normalize(skillId);
      final ver = _normalize(version);
      final items = await readAll();
      final next = items
          .where((item) => item.skillId != sid || item.version != ver)
          .toList(growable: false);
      if (next.length != items.length) await writeAll(next);
    });
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('invalid_story_skill_package_$key');
  }
  return value.trim();
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('invalid_story_skill_package_$key');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('invalid_story_skill_package_$key');
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw FormatException('invalid_story_skill_package_$key');
  }
  return value;
}

String _normalize(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, 'id');
  return normalized;
}
