import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import 'story_native_settings_widgets.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../agency/story_agency_policy.dart';
import '../orchestration/story_break_armor_mode.dart';
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
import '../voice/story_voice_routing.dart';
import '../voice/story_voice_store.dart';
import '../world_tree/story_world_tree_store.dart';

class StoryStudioPage extends StatefulWidget {
  const StoryStudioPage({super.key});

  @override
  State<StoryStudioPage> createState() => _StoryStudioPageState();
}

class _StoryStudioPageState extends State<StoryStudioPage> {
  bool _initialized = false;
  bool _loading = true;
  bool _busy = false;
  bool _breakArmorEnabled = true;
  String? _selectedConversationId;
  String? _progressText;

  late StoryRuntimeStore _runtimeStore;
  late StoryBreakArmorMode _breakArmorMode;
  late StoryReferenceDocumentStore _documentStore;
  late StoryReferenceProfileStore _profileStore;
  late StoryReferenceSelectionStore _selectionStore;
  late StoryReferenceImportService _referenceImportService;
  late StorySkillPackageStore _skillPackageStore;
  late StorySkillPackageImporter _skillImporter;
  late StorySkillBindingStore _skillBindingStore;
  late StoryWorldTreeStore _worldTreeStore;
  late StoryVoiceRoutingStore _voiceStore;

  StoryRuntimeSessionState? _session;
  String? _storyWorldTreeId;
  StoryVoiceAssignment? _narrator;
  String? _narratorServiceId;
  bool _narratorWorldlineScoped = false;
  final TextEditingController _narratorVoiceController =
      TextEditingController();
  final TextEditingController _narratorPersonaController =
      TextEditingController();
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
    _breakArmorMode = StoryBreakArmorMode(preferences);
    _breakArmorEnabled = _breakArmorMode.enabled;
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
    _worldTreeStore = StoryWorldTreeStore(preferences);
    _voiceStore = StoryVoiceRoutingStore(preferences);
    _bootstrap();
  }

  List<Conversation> _conversations() {
    final conversations = context
        .read<ChatService>()
        .getAllConversations()
        .toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  Future<void> _bootstrap() async {
    final conversations = _conversations();
    _selectedConversationId = conversations.isEmpty
        ? null
        : conversations.first.id;
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
      final tree = conversationId == null
          ? null
          : await _worldTreeStore.readForConversation(conversationId);
      final voiceRouting = tree == null
          ? null
          : await _voiceStore.readOrDefault(tree.worldTreeId);
      final narrator = voiceRouting?.narrator;
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _profiles = profiles;
        _skillPackages = packages;
        _session = session;
        _selectedReferences = selection?.invocations ?? const [];
        _skillBindings = bindings;
        _storyWorldTreeId = tree?.worldTreeId;
        _narrator = narrator;
        _narratorServiceId = narrator?.ttsServiceId;
        _narratorWorldlineScoped = narrator?.worldlineId != null;
        _narratorVoiceController.text = narrator?.voiceId ?? '';
        _narratorPersonaController.text = narrator?.personaDescription ?? '';
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

  Future<void> _setBreakArmorEnabled(bool enabled) async {
    await _breakArmorMode.setEnabled(enabled);
    if (mounted) setState(() => _breakArmorEnabled = enabled);
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

  Future<void> _saveNarratorVoice() async {
    final worldTreeId = _storyWorldTreeId;
    final serviceId = _narratorServiceId?.trim() ?? '';
    final voiceId = _narratorVoiceController.text.trim();
    if (worldTreeId == null) {
      _showMessage('请先启用 Story Mode 并完成至少一个 Story 回合，再配置旁白音色。');
      return;
    }
    if (serviceId.isEmpty || voiceId.isEmpty) {
      _showMessage('请选择 TTS 服务并填写 Voice ID。');
      return;
    }
    final current = await _voiceStore.readOrDefault(worldTreeId);
    final scopedWorldlineId = _narratorWorldlineScoped
        ? _session?.worldlineId
        : null;
    final assignment = StoryVoiceAssignment(
      characterId: '__narrator__',
      ttsServiceId: serviceId,
      voiceId: voiceId,
      personaDescription: _narratorPersonaController.text.trim(),
      worldlineId: scopedWorldlineId,
      revision: (_narrator?.revision ?? 0) + 1,
    );
    await _voiceStore.upsertState(
      StoryVoiceRoutingState(
        worldTreeId: current.worldTreeId,
        narrator: assignment,
        assignments: current.assignments,
      ),
    );
    await _reload();
    if (mounted) _showMessage('旁白音色已保存，并会复用 Kelivo 原生 TTS 服务。');
  }

  Future<void> _clearNarratorVoice() async {
    final worldTreeId = _storyWorldTreeId;
    if (worldTreeId == null) return;
    final current = await _voiceStore.readOrDefault(worldTreeId);
    await _voiceStore.upsertState(
      StoryVoiceRoutingState(
        worldTreeId: current.worldTreeId,
        assignments: current.assignments,
      ),
    );
    await _reload();
    if (mounted) _showMessage('旁白音色绑定已清除。');
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error) {
    _showMessage('操作失败：$error');
  }

  @override
  Widget build(BuildContext context) {
    final conversations = _conversations();
    final selectedConversation = _selectedConversation();
    final assistantProvider = context.watch<AssistantProvider>();
    final assistant = selectedConversation?.assistantId == null
        ? assistantProvider.currentAssistant
        : assistantProvider.getById(selectedConversation!.assistantId!);
    final settings = context.watch<SettingsProvider>();
    final enabledTtsServices = settings.ttsServices
        .where((service) => service.enabled)
        .toList(growable: false);
    final narratorServiceId =
        enabledTtsServices.any((service) => service.id == _narratorServiceId)
        ? _narratorServiceId
        : null;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zh, String en) => isZh ? zh : en;

    String conversationLabel(String id) {
      for (final conversation in conversations) {
        if (conversation.id == id) {
          return conversation.title.trim().isEmpty
              ? tr('未命名会话', 'Untitled conversation')
              : conversation.title;
        }
      }
      return tr('未命名会话', 'Untitled conversation');
    }

    String serviceLabel(String id) {
      if (id.isEmpty) return tr('未选择', 'Not selected');
      for (final service in enabledTtsServices) {
        if (service.id == id) {
          return service.name.trim().isEmpty ? service.kind.name : service.name;
        }
      }
      return tr('未选择', 'Not selected');
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('故事模式', 'Story Mode')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StoryNativeSection(
                  title: tr('故事模式', 'Story Mode'),
                  first: true,
                  footer: tr(
                    '故事模式只影响被启用的会话；普通聊天保持 Kelivo 原行为。',
                    'Story Mode only affects enabled conversations; normal Kelivo chat remains unchanged.',
                  ),
                  children: [
                    StoryNativeSwitchRow(
                      title: tr('破甲模式', 'Break Armor'),
                      subtitle: tr(
                        '仅在故事模式启用时注入叙事约束，不影响普通聊天。',
                        'Injects narrative constraints only while Story Mode is enabled.',
                      ),
                      icon: Lucide.Layers,
                      value: _breakArmorEnabled,
                      onChanged: _busy ? null : _setBreakArmorEnabled,
                    ),
                    if (conversations.isNotEmpty)
                      StoryNativeSelectRow<String>(
                        label: tr('会话', 'Conversation'),
                        subtitle: tr(
                          '选择要应用故事运行时的现有会话。',
                          'Choose the existing conversation that should use Story Runtime.',
                        ),
                        icon: Lucide.MessageCircle,
                        value:
                            _selectedConversationId ?? conversations.first.id,
                        options: conversations.map((item) => item.id).toList(),
                        labelFor: conversationLabel,
                        onSelected: _busy
                            ? null
                            : (value) => _selectConversation(value),
                      )
                    else
                      StoryNativeRow(
                        title: tr('没有可用会话', 'No conversations'),
                        subtitle: tr(
                          '先创建一个聊天会话，再回来启用故事模式。',
                          'Create a chat conversation first, then return to enable Story Mode.',
                        ),
                        icon: Lucide.MessageCircle,
                        enabled: false,
                      ),
                    StoryNativeRow(
                      title: 'Assistant',
                      subtitle:
                          assistant?.name ??
                          tr('默认 Assistant', 'Default Assistant'),
                      icon: Lucide.Bot,
                    ),
                    StoryNativeSwitchRow(
                      title: tr('启用故事模式', 'Enable Story Mode'),
                      subtitle: tr(
                        '启用 World Tree、世界线记忆、Skills、参考文风与 Story Runtime。',
                        'Enables World Tree, worldline memory, Skills, references and Story Runtime.',
                      ),
                      icon: Lucide.BookOpen,
                      value: _session?.enabled ?? false,
                      onChanged: _busy || selectedConversation == null
                          ? null
                          : _setStoryEnabled,
                    ),
                    if (_session != null)
                      StoryNativeSelectRow<StoryAgencyMode>(
                        label: tr('用户自主权', 'User agency'),
                        subtitle: tr(
                          '控制运行时允许补全用户动作的程度。',
                          'Controls how much connective user action the runtime may fill in.',
                        ),
                        icon: Lucide.User,
                        value: _session!.agencyMode,
                        options: StoryAgencyMode.values,
                        labelFor: (mode) => switch (mode) {
                          StoryAgencyMode.manual => tr(
                            'Manual · 不替用户行动',
                            'Manual',
                          ),
                          StoryAgencyMode.balanced => tr(
                            'Balanced · 仅低影响动作',
                            'Balanced',
                          ),
                          StoryAgencyMode.cinematic => tr(
                            'Cinematic · 保留关键决定',
                            'Cinematic',
                          ),
                        },
                        onSelected: _busy ? null : _setAgencyMode,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('故事语音', 'Story Voice'),
                  footer: tr(
                    '旁白继续复用 Kelivo 已配置的网络 TTS。Story 只保存服务 ID、Voice ID 与表达描述，不复制密钥或 Endpoint。',
                    'Narration reuses Kelivo network TTS. Story stores only service ID, voice ID and performance direction.',
                  ),
                  children: [
                    if (enabledTtsServices.isNotEmpty)
                      StoryNativeSelectRow<String>(
                        label: tr('旁白 TTS 服务', 'Narrator TTS service'),
                        icon: Lucide.Volume2,
                        value: narratorServiceId ?? '',
                        options: <String>[
                          '',
                          ...enabledTtsServices.map((item) => item.id),
                        ],
                        labelFor: serviceLabel,
                        onSelected: _busy
                            ? null
                            : (value) => setState(
                                () => _narratorServiceId = value.isEmpty
                                    ? null
                                    : value,
                              ),
                      )
                    else
                      StoryNativeRow(
                        title: tr('没有已启用的网络 TTS', 'No enabled network TTS'),
                        subtitle: tr(
                          '请先在“语音服务”中配置并启用一个 TTS 服务。',
                          'Configure and enable a TTS service in Voice Services first.',
                        ),
                        icon: Lucide.Volume2,
                        enabled: false,
                      ),
                    StoryNativeTextFieldRow(
                      label: tr('Voice ID / 音色名', 'Voice ID'),
                      controller: _narratorVoiceController,
                      hintText: tr(
                        '填写当前 TTS 服务原生 voice id',
                        'Use the native voice id of the selected TTS service',
                      ),
                      enabled: !_busy,
                    ),
                    StoryNativeTextFieldRow(
                      label: tr('表达描述', 'Performance direction'),
                      controller: _narratorPersonaController,
                      hintText: tr(
                        '例如：冷静、低沉、克制，重要场景略微放慢。',
                        'Example: calm, low, restrained; slow slightly for key scenes.',
                      ),
                      enabled: !_busy,
                      minLines: 2,
                      maxLines: 4,
                    ),
                    StoryNativeSwitchRow(
                      title: tr('仅当前 Worldline 使用', 'Current worldline only'),
                      subtitle: _session?.worldlineId == null
                          ? tr(
                              '首个 Story 回合建立 Worldline 后可配置。',
                              'Available after the first Story turn creates a worldline.',
                            )
                          : tr(
                              '关闭后，同一 World Tree 的其他分支也可复用该旁白。',
                              'When off, other branches in this World Tree may reuse the narrator.',
                            ),
                      icon: Lucide.GitFork,
                      value:
                          _narratorWorldlineScoped &&
                          _session?.worldlineId != null,
                      onChanged: _busy || _session?.worldlineId == null
                          ? null
                          : (value) => setState(
                              () => _narratorWorldlineScoped = value,
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: StoryNativeButton(
                              label: tr('保存旁白音色', 'Save narrator voice'),
                              icon: Lucide.Volume2,
                              primary: true,
                              enabled: !_busy && _storyWorldTreeId != null,
                              onTap: _saveNarratorVoice,
                            ),
                          ),
                          if (_narrator != null) ...[
                            const SizedBox(width: 8),
                            StoryNativeButton(
                              label: tr('清除', 'Clear'),
                              icon: Lucide.Trash2,
                              enabled: !_busy,
                              onTap: _clearNarratorVoice,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('参考资料库', 'Reference Library'),
                  footer: tr(
                    '导入后会生成抽象 Style Profile；正常 Story 回合不会把整本原文直接塞进上下文。',
                    'Imports are compiled into abstract Style Profiles; normal Story turns do not inject the entire source text.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr('导入小说 / 文本', 'Import novel / text'),
                      subtitle: tr(
                        '支持 TXT、Markdown、PDF、DOCX、EPUB。',
                        'Supports TXT, Markdown, PDF, DOCX and EPUB.',
                      ),
                      icon: Lucide.Plus,
                      onTap: _busy ? null : _importReference,
                    ),
                    if (_documents.isEmpty)
                      StoryNativeRow(
                        title: tr('还没有参考文本', 'No reference documents'),
                        icon: Lucide.BookOpen,
                        enabled: false,
                      ),
                    for (final document in _documents)
                      StoryNativeRow(
                        title: document.title,
                        subtitle: tr(
                          '${document.characterCount} 字符 · ${document.chunkCount} 分块',
                          '${document.characterCount} characters · ${document.chunkCount} chunks',
                        ),
                        icon: Lucide.BookOpen,
                        trailing: StoryNativeButton(
                          label: tr('分析', 'Analyze'),
                          icon: Lucide.Search,
                          enabled: !_busy,
                          onTap: () => _analyzeReference(document),
                        ),
                      ),
                    for (final profile in _profiles) _profileCard(profile),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('故事技能', 'Story Skills'),
                  footer: tr(
                    'ZIP 导入适合本地审核；GitHub 安装和更新请使用独立的“故事技能”设置页。',
                    'ZIP import is intended for local review. Use the dedicated Story Skills page for GitHub install and updates.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr('导入 Skill ZIP', 'Import Skill ZIP'),
                      icon: Lucide.Plus,
                      onTap: _busy ? null : _importSkill,
                    ),
                    if (_skillPackages.isEmpty)
                      StoryNativeRow(
                        title: tr(
                          '还没有安装 Story Skill',
                          'No Story Skills installed',
                        ),
                        icon: Lucide.Layers,
                        enabled: false,
                      ),
                    for (final package in _skillPackages)
                      StoryNativeSwitchRow(
                        title: package.skillId,
                        subtitle: 'v${package.version}',
                        icon: Lucide.Layers,
                        value: _isSkillBound(package.skillId),
                        onChanged: _busy || selectedConversation == null
                            ? null
                            : (value) => _setSkillBound(package.skillId, value),
                      ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 20),
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

  @override
  void dispose() {
    _narratorVoiceController.dispose();
    _narratorPersonaController.dispose();
    super.dispose();
  }

  Widget _profileCard(StoryReferenceStyleProfile profile) {
    final invocation = _referenceInvocation(profile.id);
    final enabled = invocation != null;
    final aspects = profile.aspects.map((item) => item.name).toList()..sort();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          StoryNativeSwitchRow(
            title: profile.name,
            subtitle: aspects.isEmpty ? '抽象写作风格' : aspects.join(' · '),
            icon: Lucide.BookOpen,
            value: enabled,
            onChanged: _busy || _selectedConversationId == null
                ? null
                : (value) => _setReferenceEnabled(profile, value),
          ),
          if (invocation != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 12, 8),
              child: Row(
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
                    width: 34,
                    child: Text(invocation.strength.toStringAsFixed(1)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
