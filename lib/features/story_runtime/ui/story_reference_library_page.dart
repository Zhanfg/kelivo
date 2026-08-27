import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
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

  late StoryReferenceDocumentStore _documentStore;
  late StoryReferenceProfileStore _profileStore;
  late StoryReferenceSelectionStore _selectionStore;
  late StoryReferenceImportService _referenceImportService;

  List<StoryReferenceDocument> _documents = const [];
  List<StoryReferenceStyleProfile> _profiles = const [];
  List<StoryReferenceInvocation> _selectedReferences = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final preferences = context.read<BusinessPreferences>();
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
      setState(() {
        _documents = documents;
        _profiles = profiles;
        _selectedReferences = selection?.invocations ?? const [];
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
      if (mounted) _showMessage('Style Profile 已生成。');
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
                  title: tr('应用目标', 'Apply to'),
                  first: true,
                  footer: tr(
                    '参考文本库全局保存；Style Profile 可按会话独立启用。它是独立能力，不属于故事模式设置。',
                    'Reference texts are stored globally; Style Profiles can be enabled per conversation. This is an independent capability, not a Story Mode setting.',
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
                    '导入后可生成抽象 Style Profile；正常推理不会把整本原文直接塞进上下文。',
                    'Imports can be compiled into abstract Style Profiles; normal inference does not inject the full source text.',
                  ),
                  children: [
                    StoryNativeRow(
                      title: tr('导入小说 / 文本', 'Import novel / text'),
                      subtitle: tr(
                        '支持 TXT、Markdown、PDF、DOCX、EPUB。',
                        'Supports TXT, Markdown, PDF, DOCX and EPUB.',
                      ),
                      icon: Lucide.Import,
                      onTap: _busy ? null : _importReference,
                    ),
                    if (_documents.isEmpty)
                      StoryNativeRow(
                        title: tr('还没有参考文本', 'No reference texts'),
                        icon: Lucide.FileText,
                        enabled: false,
                      ),
                    for (final document in _documents)
                      StoryNativeRow(
                        title: document.title,
                        subtitle: tr(
                          '${document.characterCount} 字符 · ${document.chunkCount} 分块',
                          '${document.characterCount} characters · ${document.chunkCount} chunks',
                        ),
                        icon: Lucide.NotebookTabs,
                        trailing: StoryNativeButton(
                          label: tr('分析', 'Analyze'),
                          icon: Lucide.Search,
                          enabled: !_busy,
                          onTap: () => _analyzeReference(document),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                StoryNativeSection(
                  title: 'Style Profiles',
                  children: [
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
    final aspects = profile.aspects.map((item) => item.name).toList()..sort();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          StoryNativeSwitchRow(
            title: profile.name,
            subtitle: aspects.isEmpty ? '抽象写作风格' : aspects.join(' · '),
            icon: Lucide.Sparkles,
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
