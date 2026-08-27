import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../agency/story_agency_policy.dart';
import '../reference/story_reference_analysis_service.dart';
import '../reference/story_reference_import_service.dart';
import '../reference/story_reference_kelivo_model_runner.dart';
import '../reference/story_reference_models.dart';
import '../reference/story_reference_selection_store.dart';
import '../reference/story_reference_store.dart';
import '../skills/story_skill_binding_store.dart';
import '../skills/story_skill_models.dart';
import '../skills/story_skill_package_importer.dart';
import '../skills/story_skill_package_store.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';

class StoryStudioPage extends StatefulWidget {
  const StoryStudioPage({super.key});

  @override
  State<StoryStudioPage> createState() => _StoryStudioPageState();
}

class _StoryStudioPageState extends State<StoryStudioPage> {
  bool _initialized = false;
  bool _loading = true;
  bool _busy = false;
  String? _selectedConversationId;
  String? _progressText;

  late StoryRuntimeStore _runtimeStore;
  late StoryReferenceDocumentStore _documentStore;
  late StoryReferenceProfileStore _profileStore;
  late StoryReferenceSelectionStore _selectionStore;
  late StoryReferenceImportService _referenceImportService;
  late StorySkillPackageStore _skillPackageStore;
  late StorySkillPackageImporter _skillImporter;
  late StorySkillBindingStore _skillBindingStore;

  StoryRuntimeSessionState? _session;
  List<StoryReferenceDocument> _documents = const [];
  List<StoryReferenceStyleProfile> _profiles = const [];
  List<StoryReferenceInvocation> _selectedReferences = const [];
  List<StoryInstalledSkillPackage> _skillPackages = const [];
  List<StorySkillBinding> _skillBindings = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final preferences = context.read<BusinessPreferences>();
    _runtimeStore = StoryRuntimeStore(preferences);
    _documentStore = StoryReferenceDocumentStore(preferences);
    _profileStore = StoryReferenceProfileStore(preferences);
    _selectionStore = StoryReferenceSelectionStore(preferences);
    _referenceImportService = StoryReferenceImportService(
      repository: _documentStore,
    );
    _skillPackageStore = StorySkillPackageStore(preferences);
    _skillImporter = StorySkillPackageImporter(repository: _skillPackageStore);
    _skillBindingStore = StorySkillBindingStore(preferences);
    _bootstrap();
  }

  List<Conversation> _conversations() {
    final conversations = context.read<ChatService>().getAllConversations().toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  Future<void> _bootstrap() async {
    final conversations = _conversations();
    _selectedConversationId = conversations.isEmpty ? null : conversations.first.id;
    await _reload();
  }

  Conversation? _selectedConversation() {
    final id = _selectedConversationId;
    if (id == null) return null;
    for (final conversation in _conversations()) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  String? _selectedAssistantId() {
    final conversation = _selectedConversation();
    final explicit = conversation?.assistantId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return context.read<AssistantProvider>().currentAssistantId;
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final conversationId = _selectedConversationId;
      final assistantId = _selectedAssistantId();
      final documents = await _documentStore.readAll();
      final profiles = await _profileStore.readAll();
      final packages = await _skillPackageStore.readAll();
      final session = conversationId == null
          ? null
          : await _runtimeStore.readOrDefault(conversationId);
      final selection = conversationId == null
          ? null
          : await _selectionStore.readForConversation(conversationId);
      final bindings = assistantId == null
          ? const <StorySkillBinding>[]
          : await _skillBindingStore.readForAssistant(assistantId);
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _profiles = profiles;
        _skillPackages = packages;
        _session = session;
        _selectedReferences = selection?.invocations ?? const [];
        _skillBindings = bindings;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _selectConversation(String? value) async {
    if (value == _selectedConversationId) return;
    setState(() => _selectedConversationId = value);
    await _reload();
  }

  Future<void> _setStoryEnabled(bool enabled) async {
    final id = _selectedConversationId;
    if (id == null) return;
    await _runtimeStore.setEnabled(id, enabled);
    await _reload();
  }

  Future<void> _setAgencyMode(StoryAgencyMode mode) async {
    final state = _session;
    if (state == null) return;
    await _runtimeStore.upsert(state.copyWith(agencyMode: mode));
    await _reload();
  }

  Future<void> _importReference() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'markdown', 'pdf', 'docx', 'epub'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return;

    await _runBusy(() async {
      final imported = await _referenceImportService.importFile(path: path);
      if (mounted) {
        _showMessage(
          imported.deduplicated
              ? '参考文本已存在，已复用。'
              : '参考文本已导入。现在可以分析成 Style Profile。',
        );
      }
    });
  }

  Future<void> _analyzeReference(StoryReferenceDocument document) async {
    if (_busy) return;
    final settings = context.read<SettingsProvider>();
    final provider = settings.currentModelProvider?.trim();
    final model = settings.currentModelId?.trim();
    if (provider == null ||
        provider.isEmpty ||
        model == null ||
        model.isEmpty) {
      _showMessage('请先在 Kelivo 中选择一个聊天模型，再分析参考文本。');
      return;
    }

    await _runBusy(() async {
      final source = await _referenceImportService.readNormalizedText(document);
      final runner = StoryReferenceKelivoModelRunner(
        settings: settings,
        providerKey: provider,
        modelId: model,
      );
      const service = StoryReferenceAnalysisService();
      await service.analyzeAndSave(
        document: document,
        sourceText: source,
        runModel: runner.call,
        profileRepository: _profileStore,
        onProgress: (stage, completed, total) {
          if (!mounted) return;
          setState(() {
            _progressText = stage == StoryReferenceAnalysisStage.analyzeChunk
                ? '分析文本 $completed / $total'
                : '汇总风格 $completed / $total';
          });
        },
      );
      if (mounted) _showMessage('Style Profile 已生成，可以对当前故事启用。');
    });
  }

  StoryReferenceInvocation? _referenceInvocation(String profileId) {
    for (final invocation in _selectedReferences) {
      if (invocation.profileId == profileId) return invocation;
    }
    return null;
  }

  Future<void> _setReferenceEnabled(
    StoryReferenceStyleProfile profile,
    bool enabled,
  ) async {
    final conversationId = _selectedConversationId;
    if (conversationId == null) return;
    final next = _selectedReferences
        .where((item) => item.profileId != profile.id)
        .toList();
    if (enabled) {
      next.add(
        StoryReferenceInvocation(
          profileId: profile.id,
          strength: 0.65,
          enabledAspects: profile.aspects,
        ),
      );
    }
    await _selectionStore.writeForConversation(conversationId, next);
    await _reload();
  }

  Future<void> _setReferenceStrength(
    StoryReferenceStyleProfile profile,
    double strength,
  ) async {
    final conversationId = _selectedConversationId;
    final current = _referenceInvocation(profile.id);
    if (conversationId == null || current == null) return;
    final next = <StoryReferenceInvocation>[
      for (final item in _selectedReferences)
        if (item.profileId == profile.id)
          StoryReferenceInvocation(
            profileId: item.profileId,
            strength: strength,
            enabledAspects: item.enabledAspects,
          )
        else
          item,
    ];
    await _selectionStore.writeForConversation(conversationId, next);
    if (!mounted) return;
    setState(() => _selectedReferences = next);
  }

  Future<void> _importSkill() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return;
    await _runBusy(() async {
      final imported = await _skillImporter.importZip(path);
      if (mounted) {
        _showMessage(
          imported.deduplicated
              ? 'Skill 已安装，已复用相同版本。'
              : 'Skill ${imported.manifest.name} 已安装。',
        );
      }
    });
  }

  bool _isSkillBound(String skillId) =>
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

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progressText = null;
    });
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progressText = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error) {
    _showMessage('操作失败：$error');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversations = _conversations();
    final selectedConversation = _selectedConversation();
    final assistantProvider = context.watch<AssistantProvider>();
    final assistant = selectedConversation?.assistantId == null
        ? assistantProvider.currentAssistant
        : assistantProvider.getById(selectedConversation!.assistantId!);

    return Scaffold(
      appBar: AppBar(title: const Text('Story Studio')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _sectionTitle(context, 'Story Mode'),
                Text(
                  '选择一个已有会话。Story Mode 只影响被启用的会话，普通 Chat 不变。',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedConversationId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '会话',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final conversation in conversations)
                      DropdownMenuItem(
                        value: conversation.id,
                        child: Text(
                          conversation.title.trim().isEmpty
                              ? '未命名会话'
                              : conversation.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy ? null : _selectConversation,
                ),
                const SizedBox(height: 8),
                if (selectedConversation != null)
                  Text(
                    'Assistant：${assistant?.name ?? '默认 Assistant'}',
                    style: theme.textTheme.bodySmall,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用 Story Mode'),
                  subtitle: const Text('开启后，该会话使用 Story MVP 叙事协议、Skill 与参考文风。'),
                  value: _session?.enabled ?? false,
                  onChanged: _busy || selectedConversation == null
                      ? null
                      : _setStoryEnabled,
                ),
                if (_session != null)
                  DropdownButtonFormField<StoryAgencyMode>(
                    value: _session!.agencyMode,
                    decoration: const InputDecoration(
                      labelText: '用户自主权',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: StoryAgencyMode.manual,
                        child: Text('Manual · 不替用户行动'),
                      ),
                      DropdownMenuItem(
                        value: StoryAgencyMode.balanced,
                        child: Text('Balanced · 只补全低影响动作'),
                      ),
                      DropdownMenuItem(
                        value: StoryAgencyMode.cinematic,
                        child: Text('Cinematic · 更连贯但保留关键决定'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) _setAgencyMode(value);
                          },
                  ),
                const SizedBox(height: 24),
                _sectionTitle(context, 'Reference Library'),
                Text(
                  '导入小说后先生成抽象 Style Profile。正常 Story 回合不会把整本小说塞进上下文。',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _importReference,
                  icon: const Icon(Icons.library_add_outlined),
                  label: const Text('导入小说 / 文本'),
                ),
                if (_documents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('还没有参考文本。支持 TXT、Markdown、PDF、DOCX、EPUB。'),
                  ),
                for (final document in _documents)
                  Card(
                    child: ListTile(
                      title: Text(document.title),
                      subtitle: Text(
                        '${document.characterCount} 字符 · ${document.chunkCount} 分块',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _busy ? null : () => _analyzeReference(document),
                        child: const Text('分析'),
                      ),
                    ),
                  ),
                if (_profiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('可调用 Style Profiles', style: theme.textTheme.titleSmall),
                ],
                for (final profile in _profiles) _profileCard(profile),
                const SizedBox(height: 24),
                _sectionTitle(context, 'Skills'),
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
                if (_busy) ...[
                  const SizedBox(height: 24),
                  const LinearProgressIndicator(),
                  if (_progressText != null) ...[
                    const SizedBox(height: 8),
                    Text(_progressText!, textAlign: TextAlign.center),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _profileCard(StoryReferenceStyleProfile profile) {
    final invocation = _referenceInvocation(profile.id);
    final enabled = invocation != null;
    final aspects = profile.aspects.map((item) => item.name).toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(profile.name),
              subtitle: Text(
                aspects.isEmpty ? '抽象写作风格' : aspects.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: enabled,
              onChanged: _busy || _selectedConversationId == null
                  ? null
                  : (value) => _setReferenceEnabled(profile, value),
            ),
            if (invocation != null)
              Row(
                children: [
                  const Text('参考强度'),
                  Expanded(
                    child: Slider(
                      value: invocation.strength,
                      min: 0.1,
                      max: 1,
                      divisions: 9,
                      label: invocation.strength.toStringAsFixed(1),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _selectedReferences = [
                                for (final item in _selectedReferences)
                                  if (item.profileId == profile.id)
                                    StoryReferenceInvocation(
                                      profileId: item.profileId,
                                      strength: value,
                                      enabledAspects: item.enabledAspects,
                                    )
                                  else
                                    item,
                              ];
                            }),
                      onChangeEnd: _busy
                          ? null
                          : (value) => _setReferenceStrength(profile, value),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(invocation.strength.toStringAsFixed(1)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Widget _sectionTitle(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(text, style: Theme.of(context).textTheme.titleLarge),
);
