import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../reference/story_reference_analysis_service.dart';
import '../reference/story_reference_import_service.dart';
import '../reference/story_reference_kelivo_model_runner.dart';
import '../reference/story_reference_models.dart';
import '../reference/story_reference_selection_store.dart';
import '../reference/story_reference_store.dart';
import 'story_native_settings_widgets.dart';

class StoryReferenceLibraryPage extends StatefulWidget {
  const StoryReferenceLibraryPage({super.key});

  @override
  State<StoryReferenceLibraryPage> createState() =>
      _StoryReferenceLibraryPageState();
}

class _StoryReferenceLibraryPageState extends State<StoryReferenceLibraryPage> {
  bool _initialized = false;
  bool _loading = true;
  bool _busy = false;
  String? _selectedConversationId;
  String? _progressText;
  String? _analysisProviderKey;
  String? _analysisModelId;

  late StoryReferenceDocumentStore _documentStore;
  late StoryReferenceProfileStore _profileStore;
  late StoryReferenceSelectionStore _selectionStore;
  late StoryReferenceImportService _referenceImportService;

  List<StoryReferenceDocument> _documents = const [];
  List<StoryReferenceStyleProfile> _profiles = const [];
  List<StoryReferenceInvocation> _selectedReferences = const [];
  final Set<String> _selectedDocumentIds = <String>{};
  final Set<String> _selectedProfileIds = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final preferences = context.read<BusinessPreferences>();
    final settings = context.read<SettingsProvider>();
    _analysisProviderKey = settings.currentModelProvider?.trim();
    _analysisModelId = settings.currentModelId?.trim();
    _documentStore = StoryReferenceDocumentStore(preferences);
    _profileStore = StoryReferenceProfileStore(preferences);
    _selectionStore = StoryReferenceSelectionStore(preferences);
    _referenceImportService = StoryReferenceImportService(
      repository: _documentStore,
    );
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

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final conversationId = _selectedConversationId;
      final documents = await _documentStore.readAll();
      final profiles = await _profileStore.readAll();
      final selection = conversationId == null
          ? null
          : await _selectionStore.readForConversation(conversationId);
      if (!mounted) return;
      final documentIds = documents.map((item) => item.id).toSet();
      final profileIds = profiles.map((item) => item.id).toSet();
      setState(() {
        _documents = documents;
        _profiles = profiles;
        _selectedReferences = selection?.invocations ?? const [];
        _selectedDocumentIds.removeWhere((id) => !documentIds.contains(id));
        _selectedProfileIds.removeWhere((id) => !profileIds.contains(id));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _selectConversation(String? value) async {
    if (value == null || value == _selectedConversationId) return;
    setState(() => _selectedConversationId = value);
    await _reload();
  }

  Future<void> _pickAnalysisModel() async {
    if (_busy) return;
    final settings = context.read<SettingsProvider>();
    final initialProvider =
        _analysisProviderKey ?? settings.currentModelProvider;
    final initialModel = _analysisModelId ?? settings.currentModelId;
    final selected = await showModelSelector(
      context,
      initialProviderKey: initialProvider,
      initialModelId: initialModel,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _analysisProviderKey = selected.providerKey;
      _analysisModelId = selected.modelId;
    });
  }

  String _analysisModelLabel(SettingsProvider settings) {
    final provider = _analysisProviderKey?.trim();
    final model = _analysisModelId?.trim();
    if (provider == null ||
        provider.isEmpty ||
        model == null ||
        model.isEmpty) {
      return '未选择';
    }
    final config = settings.getProviderConfig(provider);
    final rawOverride = config.modelOverrides[model];
    if (rawOverride is Map) {
      final overrideName = rawOverride['name']?.toString().trim();
      if (overrideName != null && overrideName.isNotEmpty) {
        return '$overrideName · ${config.name}';
      }
    }
    final providerName = config.name.trim().isEmpty
        ? provider
        : config.name.trim();
    return '$model · $providerName';
  }

  Future<void> _importReference() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'markdown', 'pdf', 'docx', 'epub'],
      allowMultiple: true,
    );
    final paths =
        result?.files
            .map((file) => file.path?.trim())
            .whereType<String>()
            .where((path) => path.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    if (paths.isEmpty) return;

    await _runBusy(() async {
      var importedCount = 0;
      var reusedCount = 0;
      for (var index = 0; index < paths.length; index++) {
        if (mounted) {
          setState(() => _progressText = '导入 ${index + 1} / ${paths.length}');
        }
        final imported = await _referenceImportService.importFile(
          path: paths[index],
        );
        _selectedDocumentIds.add(imported.document.id);
        if (imported.deduplicated) {
          reusedCount++;
        } else {
          importedCount++;
        }
      }
      if (mounted) {
        _showMessage('已导入 $importedCount 本，复用 $reusedCount 本；已自动选中，可直接批量分析。');
      }
    });
  }

  Future<void> _analyzeSelectedDocuments() async {
    final selected = _documents
        .where((item) => _selectedDocumentIds.contains(item.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      _showMessage('请先选择至少一个参考文本。');
      return;
    }
    await _analyzeDocuments(selected);
  }

  Future<void> _analyzeDocuments(List<StoryReferenceDocument> documents) async {
    if (_busy || documents.isEmpty) return;
    final settings = context.read<SettingsProvider>();
    final provider = _analysisProviderKey?.trim();
    final model = _analysisModelId?.trim();
    if (provider == null ||
        provider.isEmpty ||
        model == null ||
        model.isEmpty) {
      _showMessage('请先选择用于参考文本分析的模型。');
      return;
    }

    final runner = StoryReferenceKelivoModelRunner(
      settings: settings,
      providerKey: provider,
      modelId: model,
    );
    const service = StoryReferenceAnalysisService();
    await _runBusy(() async {
      for (
        var documentIndex = 0;
        documentIndex < documents.length;
        documentIndex++
      ) {
        final document = documents[documentIndex];
        final source = await _referenceImportService.readNormalizedText(
          document,
        );
        await service.analyzeAndSave(
          document: document,
          sourceText: source,
          runModel: runner.call,
          profileRepository: _profileStore,
          onProgress: (stage, completed, total) {
            if (!mounted) return;
            final stageText = stage == StoryReferenceAnalysisStage.analyzeChunk
                ? '分析分块'
                : '汇总风格';
            setState(() {
              _progressText =
                  '${documentIndex + 1} / ${documents.length} · ${document.title}\n$stageText $completed / $total';
            });
          },
        );
      }
      if (mounted) {
        _showMessage('已完成 ${documents.length} 个参考文本的真实模型分析。');
      }
    });
  }

  Future<void> _deleteSelectedDocuments() async {
    if (_busy || _selectedDocumentIds.isEmpty) return;
    final ids = Set<String>.from(_selectedDocumentIds);
    final profilesToRemove = _profiles
        .where((profile) => ids.contains(profile.documentId))
        .map((profile) => profile.id)
        .toSet();
    await _runBusy(() async {
      for (final profileId in profilesToRemove) {
        await _profileStore.remove(profileId);
      }
      for (final documentId in ids) {
        await _referenceImportService.deleteDocument(documentId);
      }
      final conversationId = _selectedConversationId;
      if (conversationId != null && profilesToRemove.isNotEmpty) {
        await _selectionStore.writeForConversation(
          conversationId,
          _selectedReferences.where(
            (item) => !profilesToRemove.contains(item.profileId),
          ),
        );
      }
      _selectedDocumentIds.clear();
      _selectedProfileIds.removeAll(profilesToRemove);
      if (mounted) _showMessage('已删除 ${ids.length} 个参考文本及其 Style Profile。');
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

  Future<void> _setSelectedProfilesEnabled(bool enabled) async {
    final conversationId = _selectedConversationId;
    if (conversationId == null || _selectedProfileIds.isEmpty || _busy) return;
    final selectedProfiles = {
      for (final profile in _profiles)
        if (_selectedProfileIds.contains(profile.id)) profile.id: profile,
    };
    await _runBusy(() async {
      final next = <StoryReferenceInvocation>[
        for (final invocation in _selectedReferences)
          if (!selectedProfiles.containsKey(invocation.profileId)) invocation,
      ];
      if (enabled) {
        for (final profile in selectedProfiles.values) {
          final existing = _referenceInvocation(profile.id);
          next.add(
            StoryReferenceInvocation(
              profileId: profile.id,
              strength: existing?.strength ?? 0.65,
              enabledAspects: existing?.enabledAspects.isNotEmpty == true
                  ? existing!.enabledAspects
                  : profile.aspects,
            ),
          );
        }
      }
      await _selectionStore.writeForConversation(conversationId, next);
      if (mounted) {
        _showMessage(enabled ? '已批量启用 Style Profile。' : '已批量停用 Style Profile。');
      }
    });
  }

  Future<void> _deleteSelectedProfiles() async {
    if (_selectedProfileIds.isEmpty || _busy) return;
    final ids = Set<String>.from(_selectedProfileIds);
    await _runBusy(() async {
      for (final id in ids) {
        await _profileStore.remove(id);
      }
      final conversationId = _selectedConversationId;
      if (conversationId != null) {
        await _selectionStore.writeForConversation(
          conversationId,
          _selectedReferences.where((item) => !ids.contains(item.profileId)),
        );
      }
      _selectedProfileIds.clear();
      if (mounted) _showMessage('已删除 ${ids.length} 个 Style Profile。');
    });
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

  void _toggleDocumentSelection(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedDocumentIds.add(id);
      } else {
        _selectedDocumentIds.remove(id);
      }
    });
  }

  void _toggleProfileSelection(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedProfileIds.add(id);
      } else {
        _selectedProfileIds.remove(id);
      }
    });
  }

  void _toggleAllDocuments() {
    setState(() {
      if (_documents.isNotEmpty &&
          _selectedDocumentIds.length == _documents.length) {
        _selectedDocumentIds.clear();
      } else {
        _selectedDocumentIds
          ..clear()
          ..addAll(_documents.map((item) => item.id));
      }
    });
  }

  void _toggleAllProfiles() {
    setState(() {
      if (_profiles.isNotEmpty &&
          _selectedProfileIds.length == _profiles.length) {
        _selectedProfileIds.clear();
      } else {
        _selectedProfileIds
          ..clear()
          ..addAll(_profiles.map((item) => item.id));
      }
    });
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
    final settings = context.watch<SettingsProvider>();
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

    final allDocumentsSelected =
        _documents.isNotEmpty &&
        _selectedDocumentIds.length == _documents.length;
    final allProfilesSelected =
        _profiles.isNotEmpty && _selectedProfileIds.length == _profiles.length;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: StoryNativeBackButton(tooltip: tr('返回', 'Back')),
        title: Text(tr('参考文本', 'Reference Texts')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StoryNativeSection(
                  title: tr('分析模型', 'Analysis model'),
                  first: true,
                  footer: tr(
                    '这里选择的模型只用于参考文本分析，不会改动当前聊天模型。',
                    'This model is used only for reference analysis and does not change the active chat model.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr('用于分析的模型', 'Model for analysis'),
                      subtitle: _analysisModelLabel(settings),
                      icon: Lucide.Bot,
                      onTap: _busy ? null : _pickAnalysisModel,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('应用目标', 'Apply to'),
                  footer: tr(
                    '参考文本库全局保存；Style Profile 可按会话独立启用。',
                    'Reference texts are stored globally; Style Profiles can be enabled per conversation.',
                  ),
                  children: [
                    if (conversations.isNotEmpty)
                      StoryNativeSelectRow<String>(
                        label: tr('会话', 'Conversation'),
                        icon: Lucide.MessageCircle,
                        value:
                            _selectedConversationId ?? conversations.first.id,
                        options: conversations.map((item) => item.id).toList(),
                        labelFor: conversationLabel,
                        onSelected: _busy ? null : _selectConversation,
                      )
                    else
                      StoryNativeRow(
                        title: tr('没有可用会话', 'No conversations'),
                        subtitle: tr(
                          '仍可导入和分析文本；创建会话后再启用 Style Profile。',
                          'You can still import and analyze texts; enable a Style Profile after creating a conversation.',
                        ),
                        icon: Lucide.MessageCircle,
                        enabled: false,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: tr('参考文本库', 'Reference Library'),
                  footer: tr(
                    '支持一次选择多本书。分析会逐本执行真实模型调用并生成抽象 Style Profile。',
                    'Select multiple books at once. Analysis executes real model calls for each document and generates abstract Style Profiles.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr('批量导入小说 / 文本', 'Import novels / texts'),
                      subtitle: tr(
                        '支持 TXT、Markdown、PDF、DOCX、EPUB，可一次多选。',
                        'Supports TXT, Markdown, PDF, DOCX and EPUB with multi-select.',
                      ),
                      icon: Lucide.Import,
                      onTap: _busy ? null : _importReference,
                    ),
                    if (_documents.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StoryNativeButton(
                              label: allDocumentsSelected
                                  ? tr('取消全选', 'Clear all')
                                  : tr('全选', 'Select all'),
                              icon: Lucide.ListChecks,
                              enabled: !_busy,
                              onTap: _toggleAllDocuments,
                            ),
                            StoryNativeButton(
                              label: tr(
                                '分析所选 (${_selectedDocumentIds.length})',
                                'Analyze selected (${_selectedDocumentIds.length})',
                              ),
                              icon: Lucide.Search,
                              primary: true,
                              enabled:
                                  !_busy && _selectedDocumentIds.isNotEmpty,
                              onTap: _analyzeSelectedDocuments,
                            ),
                            StoryNativeButton(
                              label: tr('删除所选', 'Delete selected'),
                              icon: Lucide.Trash2,
                              enabled:
                                  !_busy && _selectedDocumentIds.isNotEmpty,
                              onTap: _deleteSelectedDocuments,
                            ),
                          ],
                        ),
                      ),
                    if (_documents.isEmpty)
                      StoryNativeRow(
                        title: tr('还没有参考文本', 'No reference texts'),
                        icon: Lucide.FileText,
                        enabled: false,
                      ),
                    for (final document in _documents)
                      _SelectableDocumentRow(
                        document: document,
                        selected: _selectedDocumentIds.contains(document.id),
                        enabled: !_busy,
                        onSelected: (value) =>
                            _toggleDocumentSelection(document.id, value),
                        onAnalyze: () => _analyzeDocuments([document]),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: 'Style Profiles',
                  children: [
                    if (_profiles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StoryNativeButton(
                              label: allProfilesSelected
                                  ? tr('取消全选', 'Clear all')
                                  : tr('全选', 'Select all'),
                              icon: Lucide.ListChecks,
                              enabled: !_busy,
                              onTap: _toggleAllProfiles,
                            ),
                            StoryNativeButton(
                              label: tr('批量启用', 'Enable selected'),
                              icon: Lucide.Check,
                              primary: true,
                              enabled:
                                  !_busy &&
                                  _selectedConversationId != null &&
                                  _selectedProfileIds.isNotEmpty,
                              onTap: () => _setSelectedProfilesEnabled(true),
                            ),
                            StoryNativeButton(
                              label: tr('批量停用', 'Disable selected'),
                              icon: Lucide.CircleOff,
                              enabled:
                                  !_busy &&
                                  _selectedConversationId != null &&
                                  _selectedProfileIds.isNotEmpty,
                              onTap: () => _setSelectedProfilesEnabled(false),
                            ),
                            StoryNativeButton(
                              label: tr('删除所选', 'Delete selected'),
                              icon: Lucide.Trash2,
                              enabled: !_busy && _selectedProfileIds.isNotEmpty,
                              onTap: _deleteSelectedProfiles,
                            ),
                          ],
                        ),
                      ),
                    if (_profiles.isEmpty)
                      StoryNativeRow(
                        title: tr('还没有 Style Profile', 'No Style Profiles'),
                        icon: Lucide.Sparkles,
                        enabled: false,
                      ),
                    for (final profile in _profiles) _profileCard(profile),
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

  Widget _profileCard(StoryReferenceStyleProfile profile) {
    final invocation = _referenceInvocation(profile.id);
    final enabled = invocation != null;
    final selected = _selectedProfileIds.contains(profile.id);
    final aspects = profile.aspects.map((item) => item.name).toList()..sort();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: _busy
                        ? null
                        : (value) => _toggleProfileSelection(
                            profile.id,
                            value == true,
                          ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: _busy
                          ? null
                          : () =>
                                _toggleProfileSelection(profile.id, !selected),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile.name),
                            const SizedBox(height: 2),
                            Text(
                              aspects.isEmpty ? '抽象写作风格' : aspects.join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: _busy || _selectedConversationId == null
                        ? null
                        : (value) => _setReferenceEnabled(profile, value),
                  ),
                ],
              ),
              if (invocation != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(44, 0, 4, 6),
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
                              : (value) =>
                                    _setReferenceStrength(profile, value),
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
        ),
      ),
    );
  }
}

class _SelectableDocumentRow extends StatelessWidget {
  const _SelectableDocumentRow({
    required this.document,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.onAnalyze,
  });

  final StoryReferenceDocument document;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onSelected;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => onSelected(!selected) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: enabled
                    ? (value) => onSelected(value == true)
                    : null,
              ),
              Icon(Lucide.NotebookTabs, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(document.title),
                    const SizedBox(height: 2),
                    Text(
                      zh
                          ? '${document.characterCount} 字符 · ${document.chunkCount} 分块'
                          : '${document.characterCount} characters · ${document.chunkCount} chunks',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StoryNativeButton(
                label: zh ? '分析' : 'Analyze',
                icon: Lucide.Search,
                enabled: enabled,
                onTap: onAnalyze,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
