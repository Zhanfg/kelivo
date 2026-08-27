import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import 'story_native_settings_widgets.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/providers/assistant_provider.dart';
import '../skills/story_skill_binding_store.dart';
import '../skills/story_skill_github_source.dart';
import '../skills/story_skill_library.dart';
import '../skills/story_skill_models.dart';
import '../skills/story_skill_package_importer.dart';
import '../skills/story_skill_package_store.dart';
import 'story_skill_github_install_dialog.dart';

class StorySkillManagerPage extends StatefulWidget {
  const StorySkillManagerPage({super.key});

  @override
  State<StorySkillManagerPage> createState() => _StorySkillManagerPageState();
}

class _StorySkillManagerPageState extends State<StorySkillManagerPage> {
  bool _initialized = false;
  bool _loading = true;
  bool _busy = false;
  String? _status;
  String? _assistantId;

  late StorySkillPackageStore _packageStore;
  late StorySkillPackageImporter _importer;
  late StorySkillLibrary _library;
  late StorySkillGitHubService _github;
  late StorySkillBindingStore _bindingStore;

  List<StoryInstalledSkillPackage> _packages = const [];
  List<StorySkillManifest> _manifests = const [];
  List<StorySkillBinding> _bindings = const [];
  final Map<String, StorySkillGitHubUpdateCheck> _updateChecks = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final preferences = context.read<BusinessPreferences>();
    final assistantProvider = context.read<AssistantProvider>();
    _assistantId = assistantProvider.currentAssistant?.id;
    _packageStore = StorySkillPackageStore(preferences);
    _importer = StorySkillPackageImporter(repository: _packageStore);
    _library = StorySkillLibrary(repository: _packageStore);
    _bindingStore = StorySkillBindingStore(preferences);
    _github = StorySkillGitHubService(
      repository: _packageStore,
      importer: _importer,
    );
    _reload();
  }

  @override
  void dispose() {
    if (_initialized) _github.close();
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final assistantProvider = context.read<AssistantProvider>();
      await assistantProvider.loaded;
      final assistants = assistantProvider.assistants;
      var assistantId = _assistantId;
      if (assistantId == null ||
          !assistants.any((assistant) => assistant.id == assistantId)) {
        assistantId = assistantProvider.currentAssistant?.id;
      }

      final packagesFuture = _packageStore.readAll();
      final manifestsFuture = _library.loadAll();
      final bindingsFuture = assistantId == null
          ? Future.value(const <StorySkillBinding>[])
          : _bindingStore.readForAssistant(assistantId);
      final packages = await packagesFuture;
      final manifests = await manifestsFuture;
      final bindings = await bindingsFuture;
      if (!mounted) return;
      setState(() {
        _assistantId = assistantId;
        _packages = packages;
        _manifests = manifests;
        _bindings = bindings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _selectAssistant(String? assistantId) async {
    if (assistantId == null || assistantId == _assistantId) return;
    setState(() {
      _assistantId = assistantId;
      _bindings = const [];
    });
    try {
      final bindings = await _bindingStore.readForAssistant(assistantId);
      if (!mounted || _assistantId != assistantId) return;
      setState(() => _bindings = bindings);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  bool _isSkillEnabled(StorySkillManifest manifest) {
    for (final binding in _bindings) {
      if (binding.skillId == manifest.id) return binding.enabled;
    }
    return manifest.metadata['defaultEnabled'] == true;
  }

  Future<void> _setSkillEnabled(
    StorySkillManifest manifest,
    bool enabled,
  ) async {
    final assistantId = _assistantId;
    if (assistantId == null || _busy) return;
    await _runBusy(
      enabled ? '正在启用 ${manifest.name}…' : '正在停用 ${manifest.name}…',
      () async {
        await _bindingStore.upsert(
          StorySkillBinding(
            assistantId: assistantId,
            skillId: manifest.id,
            enabled: enabled,
          ),
        );
        final bindings = await _bindingStore.readForAssistant(assistantId);
        if (mounted && _assistantId == assistantId) {
          setState(() => _bindings = bindings);
        }
      },
      reload: false,
    );
  }

  Future<void> _installFromGitHub() async {
    if (_busy) return;
    final request = await showStorySkillGitHubInstallDialog(context);
    if (request == null || !mounted) return;
    await _runBusy('正在从 GitHub 安装…', () async {
      final result = await _github.install(
        repositoryUrl: request.repositoryUrl,
        ref: request.ref,
        subdirectory: request.subdirectory,
      );
      _updateChecks.remove(_key(result.package));
      if (mounted) {
        _showMessage(
          '已安装 ${result.importResult.manifest.name} · ${_shortSha(result.commitSha)}',
        );
      }
    });
  }

  Future<void> _checkOne(StoryInstalledSkillPackage package) async {
    if (_busy || !package.isGitHubManaged) return;
    await _runBusy('正在检查 ${package.skillId}…', () async {
      final check = await _github.checkForUpdate(package);
      if (!mounted) return;
      setState(() => _updateChecks[_key(package)] = check);
      _showMessage(check.updateAvailable ? '发现新版本。' : '已经是最新版本。');
    }, reload: false);
  }

  Future<void> _checkAll() async {
    if (_busy) return;
    final managed = _packages.where((item) => item.isGitHubManaged).toList();
    if (managed.isEmpty) {
      _showMessage('没有由 GitHub 管理的 Skill。');
      return;
    }
    await _runBusy('正在检查 ${managed.length} 个 GitHub Skill…', () async {
      var updates = 0;
      for (var index = 0; index < managed.length; index++) {
        final package = managed[index];
        if (mounted) {
          setState(() => _status = '检查更新 ${index + 1} / ${managed.length}');
        }
        final check = await _github.checkForUpdate(package);
        _updateChecks[_key(package)] = check;
        if (check.updateAvailable) updates++;
      }
      if (mounted) {
        setState(() {});
        _showMessage(updates == 0 ? '全部已是最新版本。' : '发现 $updates 个可更新 Skill。');
      }
    }, reload: false);
  }

  Future<void> _updateOne(StoryInstalledSkillPackage package) async {
    if (_busy || !package.isGitHubManaged) return;
    await _runBusy('正在更新 ${package.skillId}…', () async {
      final result = await _github.update(package);
      _updateChecks.remove(_key(package));
      if (mounted) {
        _showMessage('已更新到 ${_shortSha(result.commitSha)}。');
      }
    });
  }

  Future<void> _updateAll() async {
    if (_busy) return;
    final targets = <StoryInstalledSkillPackage>[];
    for (final package in _packages.where((item) => item.isGitHubManaged)) {
      final check = _updateChecks[_key(package)];
      if (check?.updateAvailable == true) targets.add(package);
    }
    if (targets.isEmpty) {
      _showMessage('请先“检查全部更新”；当前没有已确认的可更新 Skill。');
      return;
    }
    await _runBusy('正在更新 ${targets.length} 个 Skill…', () async {
      for (var index = 0; index < targets.length; index++) {
        final package = targets[index];
        if (mounted) {
          setState(() => _status = '更新 ${index + 1} / ${targets.length}');
        }
        await _github.update(package);
        _updateChecks.remove(_key(package));
      }
      if (mounted) _showMessage('已完成 ${targets.length} 个 Skill 更新。');
    });
  }

  Future<void> _runBusy(
    String status,
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = status;
    });
    try {
      await action();
      if (reload) await _reload();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  StoryInstalledSkillPackage? _packageFor(StorySkillManifest manifest) {
    for (final package in _packages.reversed) {
      if (package.skillId == manifest.id &&
          package.version == manifest.version) {
        return package;
      }
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error) {
    _showMessage('操作失败：$error');
  }

  @override
  Widget build(BuildContext context) {
    final assistants = context.watch<AssistantProvider>().assistants;
    final selectedAssistantId =
        assistants.any((assistant) => assistant.id == _assistantId)
        ? _assistantId
        : null;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zh, String en) => isZh ? zh : en;

    String assistantLabel(String id) {
      for (final assistant in assistants) {
        if (assistant.id == id) return assistant.name;
      }
      return tr('未选择', 'Not selected');
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('故事技能', 'Story Skills')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StoryNativeSection(
                  title: tr('技能设置', 'Skill settings'),
                  first: true,
                  footer: tr(
                    'Skill 按 Assistant 独立启用。GitHub 直装固定到具体 commit；涉及 MCP、工具、内存权限或 Hook 的包仍要求本地审核。',
                    'Skills are enabled per Assistant. GitHub installs are pinned to a commit; packages declaring MCP, tool, memory or hook permissions still require local review.',
                  ),
                  children: [
                    if (assistants.isNotEmpty)
                      StoryNativeSelectRow<String>(
                        label: 'Assistant',
                        icon: Lucide.Bot,
                        value: selectedAssistantId ?? assistants.first.id,
                        options: assistants.map((item) => item.id).toList(),
                        labelFor: assistantLabel,
                        onSelected: _busy ? null : _selectAssistant,
                      )
                    else
                      StoryNativeRow(
                        title: tr('没有可用 Assistant', 'No Assistants'),
                        icon: Lucide.Bot,
                        enabled: false,
                      ),
                    StoryNativeRow(
                      title: tr('从 GitHub 安装', 'Install from GitHub'),
                      subtitle: tr(
                        '解析仓库、固定 commit，并按 Skill manifest 导入。',
                        'Resolve the repository, pin a commit and import from the Skill manifest.',
                      ),
                      icon: Lucide.Plus,
                      onTap: _busy ? null : _installFromGitHub,
                    ),
                    StoryNativeRow(
                      title: tr('检查全部更新', 'Check all updates'),
                      icon: Lucide.Search,
                      onTap: _busy ? null : _checkAll,
                    ),
                    StoryNativeRow(
                      title: tr('更新全部', 'Update all'),
                      subtitle: tr(
                        '只更新已经确认存在新版本的 GitHub Skill。',
                        'Updates only GitHub Skills already confirmed to have a newer version.',
                      ),
                      icon: Lucide.Download,
                      onTap: _busy ? null : _updateAll,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('可用 Skills', 'Available Skills'),
                  children: [
                    if (_manifests.isEmpty)
                      StoryNativeRow(
                        title: tr('没有可用 Skill', 'No Skills available'),
                        icon: Lucide.Layers,
                        enabled: false,
                      ),
                    for (final manifest in _manifests)
                      _skillCard(manifest, _packageFor(manifest)),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(_status!, textAlign: TextAlign.center),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _skillCard(
    StorySkillManifest manifest,
    StoryInstalledSkillPackage? package,
  ) {
    final builtIn = manifest.metadata['builtIn'] == true && package == null;
    final defaultEnabled = manifest.metadata['defaultEnabled'] == true;
    final managed = package?.isGitHubManaged == true;
    final check = package == null ? null : _updateChecks[_key(package)];
    final description = manifest.description.trim();
    final sourceRepository = _githubSourceRepository(package);
    final subtitle = <String>[
      builtIn
          ? '内置'
          : managed
          ? 'GitHub'
          : '本地安装',
      'v${manifest.version}',
      if (defaultEnabled) '默认启用',
      if (sourceRepository != null) sourceRepository,
      if (check?.updateAvailable == true) '有更新',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StoryNativeSwitchRow(
            title: manifest.name,
            subtitle: description.isEmpty
                ? subtitle
                : '$subtitle\n$description',
            icon: Lucide.Layers,
            value: _isSkillEnabled(manifest),
            onChanged: _busy || _assistantId == null
                ? null
                : (value) => _setSkillEnabled(manifest, value),
          ),
          if (managed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StoryNativeButton(
                    label: '检查更新',
                    icon: Lucide.Search,
                    enabled: !_busy,
                    onTap: () => _checkOne(package!),
                  ),
                  if (check?.updateAvailable == true)
                    StoryNativeButton(
                      label: '更新',
                      icon: Lucide.Download,
                      primary: true,
                      enabled: !_busy,
                      onTap: () => _updateOne(package!),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _key(StoryInstalledSkillPackage package) =>
    '${package.skillId}@${package.version}';

String _shortSha(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);

String? _githubSourceRepository(StoryInstalledSkillPackage? package) {
  if (package == null || !package.isGitHubManaged) return null;
  return package.sourceRepository;
}
