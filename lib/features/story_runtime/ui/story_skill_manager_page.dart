import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final theme = Theme.of(context);
    final assistants = context.watch<AssistantProvider>().assistants;
    final selectedAssistantId =
        assistants.any((assistant) => assistant.id == _assistantId)
        ? _assistantId
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Skill 管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Skill 按 Assistant 独立启用。内置默认 Skill 可以显式关闭；手动 Skill 只有开启后才进入 Story Runtime。',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedAssistantId,
                  decoration: const InputDecoration(
                    labelText: 'Assistant',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final assistant in assistants)
                      DropdownMenuItem<String>(
                        value: assistant.id,
                        child: Text(
                          assistant.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy ? null : _selectAssistant,
                ),
                const SizedBox(height: 20),
                Text(
                  'GitHub 直装固定到具体 commit，并只导入 Prompt / Assets / WorldBooks / Templates。上游若声明 MCP、工具、内存权限或 Hook，会要求改走本地 ZIP 审核。',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _installFromGitHub,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('从 GitHub 安装'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _checkAll,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('检查全部更新'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _updateAll,
                      icon: const Icon(Icons.system_update_alt_outlined),
                      label: const Text('更新全部'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(_status!, textAlign: TextAlign.center),
                  ],
                ],
                const SizedBox(height: 24),
                Text('可用 Skills', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_manifests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('没有可用 Skill。'),
                  ),
                for (final manifest in _manifests)
                  _skillCard(manifest, _packageFor(manifest)),
              ],
            ),
    );
  }

  Widget _skillCard(
    StorySkillManifest manifest,
    StoryInstalledSkillPackage? package,
  ) {
    final theme = Theme.of(context);
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
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(manifest.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (check?.updateAvailable == true)
                  const Chip(label: Text('有更新')),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(child: Text('在所选 Assistant 中启用')),
                Switch(
                  value: _isSkillEnabled(manifest),
                  onChanged: _busy || _assistantId == null
                      ? null
                      : (value) => _setSkillEnabled(manifest, value),
                ),
              ],
            ),
            if (managed) ...[
              const SizedBox(height: 4),
              Text(
                '当前 ${_shortSha(package!.sourceCommitSha!)}${check == null ? '' : ' · 远端 ${_shortSha(check.latestCommitSha)}'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : () => _checkOne(package),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('检查更新'),
                  ),
                  if (check?.updateAvailable == true)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _updateOne(package),
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: const Text('更新'),
                    ),
                ],
              ),
            ],
          ],
        ),
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
