from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"patch anchor missing: {path}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1))


def remove_once(path: str, old: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        return
    file.write_text(text.replace(old, "", 1))


Path(
    "lib/features/story_runtime/skills/story_skill_activation_policy.dart"
).write_text(
    """import 'story_skill_models.dart';

/// Resolves persisted per-assistant overrides against manifest defaults.
///
/// An explicit binding always wins, including `enabled: false`. This is
/// important for built-in Skills that are enabled by default: deleting the
/// binding would otherwise make the manifest default immediately turn back on.
final class StorySkillActivationPolicy {
  const StorySkillActivationPolicy._();

  static StorySkillBinding? explicitBinding({
    required String? assistantId,
    required String skillId,
    required Iterable<StorySkillBinding> bindings,
  }) {
    final aid = assistantId?.trim();
    if (aid == null || aid.isEmpty) return null;
    for (final binding in bindings) {
      if (binding.assistantId == aid && binding.skillId == skillId) {
        return binding;
      }
    }
    return null;
  }

  static bool isEnabled({
    required StorySkillManifest manifest,
    required String? assistantId,
    required Iterable<StorySkillBinding> bindings,
  }) {
    final explicit = explicitBinding(
      assistantId: assistantId,
      skillId: manifest.id,
      bindings: bindings,
    );
    if (explicit != null) return explicit.enabled;
    return manifest.metadata['defaultEnabled'] == true;
  }

  static List<StorySkillBinding> effectiveBindings({
    required String assistantId,
    required Iterable<StorySkillManifest> manifests,
    required Iterable<StorySkillBinding> bindings,
  }) {
    final aid = assistantId.trim();
    if (aid.isEmpty) return const <StorySkillBinding>[];
    final result = <StorySkillBinding>[
      for (final binding in bindings)
        if (binding.assistantId == aid) binding,
    ];
    final explicitIds = <String>{
      for (final binding in result) binding.skillId,
    };
    for (final manifest in manifests) {
      if (manifest.metadata['defaultEnabled'] == true &&
          !explicitIds.contains(manifest.id)) {
        result.add(
          StorySkillBinding(assistantId: aid, skillId: manifest.id),
        );
      }
    }
    return List<StorySkillBinding>.unmodifiable(result);
  }
}
"""
)

# Strict-analyze cleanup that predates this UI integration.
remove_once(
    "lib/features/story_runtime/skills/story_skill_package_store.dart",
    "import '../../../core/database/business_preferences.dart';\n",
)
remove_once(
    "lib/features/story_runtime/state/story_runtime_store.dart",
    "import '../../../core/database/business_preferences.dart';\n",
)
replace_once(
    "lib/features/story_runtime/skills/story_skill_github_source.dart",
    """  StorySkillGitHubService({
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
""",
    """  factory StorySkillGitHubService({
    required StorySkillPackageRepository repository,
    required StorySkillPackageImporter importer,
    http.Client? client,
    StorySkillGitHubRootResolver? appDataRootResolver,
    int maxDownloadBytes = 128 * 1024 * 1024,
  }) {
    final resolvedClient = client ?? http.Client();
    return StorySkillGitHubService._(
      repository,
      importer,
      resolvedClient,
      client == null,
      appDataRootResolver ?? AppDirectories.getAppDataDirectory,
      maxDownloadBytes,
    );
  }

  StorySkillGitHubService._(
    this._repository,
    this._importer,
    this._client,
    this._ownsClient,
    this._appDataRootResolver,
    this.maxDownloadBytes,
  );
""",
)

# Runtime and UI must share one authoritative default/override policy.
replace_once(
    "lib/features/story_runtime/orchestration/story_mvp_prompt_service.dart",
    "import '../skills/story_skill_binding_store.dart';\n",
    "import '../skills/story_skill_activation_policy.dart';\nimport '../skills/story_skill_binding_store.dart';\n",
)
replace_once(
    "lib/features/story_runtime/orchestration/story_mvp_prompt_service.dart",
    """    final effectiveBindings = <StorySkillBinding>[...bindings];
    final explicitlyBoundIds = <String>{for (final binding in bindings) binding.skillId};
    for (final manifest in manifests) {
      if (manifest.metadata['defaultEnabled'] == true &&
          !explicitlyBoundIds.contains(manifest.id)) {
        effectiveBindings.add(
          StorySkillBinding(assistantId: aid, skillId: manifest.id),
        );
      }
    }
""",
    """    final effectiveBindings = StorySkillActivationPolicy.effectiveBindings(
      assistantId: aid,
      manifests: manifests,
      bindings: bindings,
    );
""",
)

studio = "lib/features/story_runtime/ui/story_studio_page.dart"
replace_once(
    studio,
    """import '../skills/story_skill_binding_store.dart';
import '../skills/story_skill_models.dart';
import '../skills/story_skill_package_importer.dart';
import '../skills/story_skill_package_store.dart';
""",
    """import '../skills/story_skill_activation_policy.dart';
import '../skills/story_skill_binding_store.dart';
import '../skills/story_skill_github_source.dart';
import '../skills/story_skill_library.dart';
import '../skills/story_skill_models.dart';
import '../skills/story_skill_package_importer.dart';
import '../skills/story_skill_package_store.dart';
""",
)
replace_once(
    studio,
    "import '../state/story_runtime_store.dart';\n",
    "import '../state/story_runtime_store.dart';\nimport 'story_skill_github_install_dialog.dart';\n",
)
replace_once(
    studio,
    """  late StorySkillPackageStore _skillPackageStore;
  late StorySkillPackageImporter _skillImporter;
  late StorySkillBindingStore _skillBindingStore;
""",
    """  late StorySkillPackageStore _skillPackageStore;
  late StorySkillPackageImporter _skillImporter;
  late StorySkillLibrary _skillLibrary;
  StorySkillGitHubService? _skillGitHubService;
  late StorySkillBindingStore _skillBindingStore;
""",
)
replace_once(
    studio,
    """  List<StoryInstalledSkillPackage> _skillPackages = const [];
  List<StorySkillBinding> _skillBindings = const [];
""",
    """  List<StoryInstalledSkillPackage> _skillPackages = const [];
  List<StorySkillManifest> _skillManifests = const [];
  List<StorySkillBinding> _skillBindings = const [];
""",
)
replace_once(
    studio,
    """    _skillPackageStore = StorySkillPackageStore(preferences);
    _skillImporter = StorySkillPackageImporter(repository: _skillPackageStore);
    _skillBindingStore = StorySkillBindingStore(preferences);
""",
    """    _skillPackageStore = StorySkillPackageStore(preferences);
    _skillImporter = StorySkillPackageImporter(repository: _skillPackageStore);
    _skillLibrary = StorySkillLibrary(repository: _skillPackageStore);
    _skillGitHubService = StorySkillGitHubService(
      repository: _skillPackageStore,
      importer: _skillImporter,
    );
    _skillBindingStore = StorySkillBindingStore(preferences);
""",
)
replace_once(
    studio,
    """  List<Conversation> _conversations() {
""",
    """  @override
  void dispose() {
    _skillGitHubService?.close();
    super.dispose();
  }

  List<Conversation> _conversations() {
""",
)
replace_once(
    studio,
    """      final packages = await _skillPackageStore.readAll();
      final session = conversationId == null
""",
    """      final packages = await _skillPackageStore.readAll();
      final manifests = await _skillLibrary.loadAll();
      final session = conversationId == null
""",
)
replace_once(
    studio,
    """        _skillPackages = packages;
        _session = session;
""",
    """        _skillPackages = packages;
        _skillManifests = manifests;
        _session = session;
""",
)
replace_once(
    studio,
    """  bool _isSkillBound(String skillId) =>
      _skillBindings.any((item) => item.skillId == skillId && item.enabled);

  Future<void> _setSkillBound(String skillId, bool enabled) async {
    final assistantId = _selectedAssistantId();
    if (assistantId == null || assistantId.isEmpty) {
      _showMessage('当前会话没有可绑定的 Assistant。');
      return;
    }
    if (enabled) {
      await _skillBindingStore.upsert(
        StorySkillBinding(assistantId: assistantId, skillId: skillId),
      );
    } else {
      await _skillBindingStore.remove(
        assistantId: assistantId,
        skillId: skillId,
      );
    }
    await _reload();
  }
""",
    """  Future<void> _installSkillFromGitHub() async {
    if (_busy) return;
    final request = await showStorySkillGitHubInstallDialog(context);
    if (request == null || !mounted) return;
    final service = _skillGitHubService;
    if (service == null) return;
    await _runBusy(() async {
      final result = await service.install(
        repositoryUrl: request.repositoryUrl,
        ref: request.ref,
        subdirectory: request.subdirectory,
      );
      if (!mounted) return;
      final replaced = result.replacedVersions > 0
          ? ' 已替换 ${result.replacedVersions} 个旧版本。'
          : '';
      _showMessage(
        'Skill ${result.importResult.manifest.name} 已从 GitHub 安装。$replaced',
      );
    });
  }

  StoryInstalledSkillPackage? _installedSkillPackage(String skillId) {
    StoryInstalledSkillPackage? matched;
    for (final package in _skillPackages) {
      if (package.skillId != skillId) continue;
      if (matched == null || package.installedAtMs > matched.installedAtMs) {
        matched = package;
      }
    }
    return matched;
  }

  bool _isSkillEnabled(StorySkillManifest manifest) =>
      StorySkillActivationPolicy.isEnabled(
        manifest: manifest,
        assistantId: _selectedAssistantId(),
        bindings: _skillBindings,
      );

  String _skillSourceLabel(StorySkillManifest manifest) {
    final package = _installedSkillPackage(manifest.id);
    if (package != null) {
      if (package.isGitHubManaged) {
        final repo = package.sourceRepository ?? 'GitHub';
        final subdirectory = package.sourceSubdirectory;
        final path = subdirectory == null || subdirectory.isEmpty
            ? ''
            : '/$subdirectory';
        return 'GitHub · $repo$path · v${manifest.version}';
      }
      return '本地安装 · v${manifest.version}';
    }
    if (manifest.metadata['builtIn'] == true) {
      return 'Kelivo 内置 · v${manifest.version}';
    }
    return 'Skill · v${manifest.version}';
  }

  Future<void> _checkSkillUpdate(StoryInstalledSkillPackage package) async {
    if (_busy || !package.isGitHubManaged) return;
    final service = _skillGitHubService;
    if (service == null) return;
    await _runBusy(() async {
      final check = await service.checkForUpdate(package);
      if (!mounted) return;
      if (!check.updateAvailable) {
        _showMessage('该 GitHub Skill 已是最新版本。');
        return;
      }
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('发现 Skill 更新'),
          content: Text(
            '${package.sourceRepository ?? package.skillId} 有新提交。\n'
            '${check.currentCommitSha.substring(0, 12)} → '
            '${check.latestCommitSha.substring(0, 12)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('更新'),
            ),
          ],
        ),
      );
      if (shouldUpdate != true) return;
      final result = await service.update(package);
      if (mounted) {
        _showMessage('Skill ${result.importResult.manifest.name} 已更新。');
      }
    });
  }

  Future<void> _setSkillBound(String skillId, bool enabled) async {
    final assistantId = _selectedAssistantId();
    if (assistantId == null || assistantId.isEmpty) {
      _showMessage('当前会话没有可绑定的 Assistant。');
      return;
    }
    await _skillBindingStore.upsert(
      StorySkillBinding(
        assistantId: assistantId,
        skillId: skillId,
        enabled: enabled,
      ),
    );
    await _reload();
  }
""",
)
replace_once(
    studio,
    """                DropdownButtonFormField<String>(
                  value: _selectedConversationId,
""",
    """                DropdownButtonFormField<String>(
                  key: ValueKey(_selectedConversationId),
                  initialValue: _selectedConversationId,
""",
)
replace_once(
    studio,
    """                  DropdownButtonFormField<StoryAgencyMode>(
                    value: _session!.agencyMode,
""",
    """                  DropdownButtonFormField<StoryAgencyMode>(
                    key: ValueKey(_session!.agencyMode),
                    initialValue: _session!.agencyMode,
""",
)
replace_once(
    studio,
    """                _sectionTitle(context, 'Skills'),
                Text(
                  '导入 Story Skill ZIP。绑定到当前会话所属 Assistant 后，Manual / Always 类型会进入 Story MVP。',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _importSkill,
                  icon: const Icon(Icons.extension_outlined),
                  label: const Text('导入 Skill ZIP'),
                ),
                if (_skillPackages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('还没有安装 Story Skill。'),
                  ),
                for (final package in _skillPackages)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(package.skillId),
                    subtitle: Text('v${package.version}'),
                    value: _isSkillBound(package.skillId),
                    onChanged: _busy || selectedConversation == null
                        ? null
                        : (value) => _setSkillBound(package.skillId, value),
                  ),
""",
    """                _sectionTitle(context, 'Skills'),
                Text(
                  '统一显示 Kelivo 内置、GitHub 与本地 Story Skill。内置默认值可被当前 Assistant 显式关闭；GitHub 直装只允许安全的提示词/数据型 Skill。',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _importSkill,
                      icon: const Icon(Icons.extension_outlined),
                      label: const Text('导入 Skill ZIP'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _installSkillFromGitHub,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('从 GitHub 安装'),
                    ),
                  ],
                ),
                if (_skillManifests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('当前没有可用 Story Skill。'),
                  ),
                for (final manifest in _skillManifests)
                  _skillCard(
                    manifest,
                    canBind: selectedConversation != null,
                  ),
""",
)
replace_once(
    studio,
    """  Widget _profileCard(StoryReferenceStyleProfile profile) {
""",
    """  Widget _skillCard(
    StorySkillManifest manifest, {
    required bool canBind,
  }) {
    final package = _installedSkillPackage(manifest.id);
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Text(manifest.name),
            subtitle: Text(
              '${manifest.description}\n${_skillSourceLabel(manifest)}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            value: _isSkillEnabled(manifest),
            onChanged: _busy || !canBind
                ? null
                : (value) => _setSkillBound(manifest.id, value),
          ),
          if (package?.isGitHubManaged == true)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _checkSkillUpdate(package!),
                  icon: const Icon(Icons.system_update_alt_outlined),
                  label: const Text('检查更新'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profileCard(StoryReferenceStyleProfile profile) {
""",
)

# Regression coverage for default-enabled built-ins and explicit OFF overrides.
test_file = "test/story_skill_system_test.dart"
replace_once(
    test_file,
    "import 'package:Kelivo/features/story_runtime/skills/story_skill_manifest_parser.dart';\n",
    "import 'package:Kelivo/features/story_runtime/skills/story_skill_activation_policy.dart';\nimport 'package:Kelivo/features/story_runtime/skills/story_skill_manifest_parser.dart';\n",
)
replace_once(
    test_file,
    """    test('ordinary Story turn does not expose low-frequency GitHub capability', () {
""",
    """    test('default-enabled Skill is active until explicitly disabled', () {
      const defaultOn = StorySkillManifest(
        id: 'story.default_on',
        name: 'Default On',
        version: '1',
        activationModes: {StorySkillActivationMode.always},
        metadata: {'defaultEnabled': true},
      );

      expect(
        StorySkillActivationPolicy.isEnabled(
          manifest: defaultOn,
          assistantId: 'assistant-1',
          bindings: const [],
        ),
        isTrue,
      );

      const disabled = [
        StorySkillBinding(
          assistantId: 'assistant-1',
          skillId: 'story.default_on',
          enabled: false,
        ),
      ];
      expect(
        StorySkillActivationPolicy.isEnabled(
          manifest: defaultOn,
          assistantId: 'assistant-1',
          bindings: disabled,
        ),
        isFalse,
      );

      final effective = StorySkillActivationPolicy.effectiveBindings(
        assistantId: 'assistant-1',
        manifests: const [defaultOn],
        bindings: disabled,
      );
      expect(effective, hasLength(1));
      expect(effective.single.enabled, isFalse);
    });

    test('default-enabled Skill gets one synthetic binding without override', () {
      const defaultOn = StorySkillManifest(
        id: 'story.default_on',
        name: 'Default On',
        version: '1',
        activationModes: {StorySkillActivationMode.always},
        metadata: {'defaultEnabled': true},
      );
      final effective = StorySkillActivationPolicy.effectiveBindings(
        assistantId: 'assistant-1',
        manifests: const [defaultOn],
        bindings: const [],
      );
      final resolved = resolver.resolve(
        manifests: const [defaultOn],
        bindings: effective,
        context: StorySkillActivationContext(
          assistantId: 'assistant-1',
          manualEnabledSkillIds: {
            for (final binding in effective)
              if (binding.enabled) binding.skillId,
          },
        ),
      );

      expect(effective, hasLength(1));
      expect(effective.single.enabled, isTrue);
      expect(resolved.activeSkills.map((skill) => skill.id), ['story.default_on']);
    });

    test('ordinary Story turn does not expose low-frequency GitHub capability', () {
""",
)
