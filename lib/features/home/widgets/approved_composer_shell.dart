import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_input_data.dart';
import '../../../core/providers/asr_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/asr/asr_service_options.dart';
import '../../../icons/lucide_adapter.dart';
import 'chat_input_bar.dart';

/// Presentation layer for the approved Kelivo composer interaction model.
///
/// [ChatInputBar] remains the source of truth for attachments, paste/import,
/// submission recovery and desktop keyboard behavior. This shell owns only the
/// compact four-action surface, six-line fullscreen affordance and the voice
/// recording/transcript presentation.
class ApprovedComposerShell extends StatefulWidget {
  const ApprovedComposerShell({
    super.key,
    required this.child,
    required this.inputController,
    required this.mediaController,
    required this.asrProvider,
    required this.loading,
    required this.reasoningBudget,
    required this.supportsReasoning,
    this.onMore,
    this.onSelectModel,
    this.onConfigureReasoning,
    this.onStop,
    this.onSend,
  });

  final Widget child;
  final TextEditingController inputController;
  final ChatInputBarController mediaController;
  final AsrProvider asrProvider;
  final bool loading;
  final int? reasoningBudget;
  final bool supportsReasoning;
  final VoidCallback? onMore;
  final VoidCallback? onSelectModel;
  final VoidCallback? onConfigureReasoning;
  final VoidCallback? onStop;
  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;

  @override
  State<ApprovedComposerShell> createState() => _ApprovedComposerShellState();
}

class _ApprovedComposerShellState extends State<ApprovedComposerShell> {
  bool _voiceOwned = false;
  bool _voiceLocked = false;
  bool _voiceSettingsExpanded = false;
  bool _voiceEditing = false;
  bool _voiceFinishing = false;
  String _voiceBaseText = '';
  String? _voiceReadyText;
  late final TextEditingController _voiceEditor;

  @override
  void initState() {
    super.initState();
    _voiceEditor = TextEditingController();
    widget.inputController.addListener(_handleDraftChanged);
    widget.asrProvider.addListener(_handleAsrChanged);
  }

  @override
  void didUpdateWidget(covariant ApprovedComposerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.inputController, widget.inputController)) {
      oldWidget.inputController.removeListener(_handleDraftChanged);
      widget.inputController.addListener(_handleDraftChanged);
    }
    if (!identical(oldWidget.asrProvider, widget.asrProvider)) {
      oldWidget.asrProvider.removeListener(_handleAsrChanged);
      widget.asrProvider.addListener(_handleAsrChanged);
    }
  }

  @override
  void dispose() {
    widget.inputController.removeListener(_handleDraftChanged);
    widget.asrProvider.removeListener(_handleAsrChanged);
    if (_voiceOwned) {
      unawaited(widget.asrProvider.cancel());
    }
    _voiceEditor.dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    if (mounted) setState(() {});
  }

  void _handleAsrChanged() {
    if (!_voiceOwned || !mounted) return;
    final transcript = widget.asrProvider.transcript;
    if (!_voiceEditing && transcript.isNotEmpty) {
      _voiceEditor.value = TextEditingValue(
        text: transcript,
        selection: TextSelection.collapsed(offset: transcript.length),
      );
    }
    setState(() {});
  }

  bool get _voiceActive => _voiceOwned || _voiceReadyText != null;

  bool get _selectedAsrStreams {
    final selected = context.read<SettingsProvider>().selectedAsrService;
    // Sherpa local ASR returns a complete transcript after capture. System and
    // cloud services already publish partial transcripts through AsrProvider.
    return selected is! SherpaOnnxAsrOptions;
  }

  int get _lineCount {
    final value = widget.inputController.text;
    if (value.isEmpty) return 1;
    return '\n'.allMatches(value).length + 1;
  }

  Future<void> _startVoice({bool locked = false}) async {
    if (_voiceActive || widget.loading) return;
    final settings = context.read<SettingsProvider>();
    final selected = settings.selectedAsrService;
    if (selected == null || !widget.asrProvider.canUse(selected)) return;

    _voiceBaseText = widget.inputController.text.trimRight();
    setState(() {
      _voiceOwned = true;
      _voiceLocked = locked;
      _voiceSettingsExpanded = false;
      _voiceEditing = false;
      _voiceFinishing = false;
      _voiceReadyText = null;
      _voiceEditor.clear();
    });

    try {
      await widget.asrProvider.start(selected);
    } catch (_) {
      if (!mounted) return;
      setState(() => _voiceOwned = false);
    }
  }

  Future<void> _cancelVoice() async {
    await widget.asrProvider.cancel();
    if (!mounted) return;
    setState(() {
      _voiceOwned = false;
      _voiceLocked = false;
      _voiceEditing = false;
      _voiceSettingsExpanded = false;
      _voiceFinishing = false;
      _voiceReadyText = null;
      _voiceEditor.clear();
    });
  }

  Future<void> _finishVoice() async {
    if (!_voiceOwned || _voiceFinishing) return;
    setState(() => _voiceFinishing = true);
    try {
      final result = await widget.asrProvider.finish();
      if (!mounted) return;
      final edited = _voiceEditor.text.trim();
      final transcript = edited.isNotEmpty ? edited : result.trim();
      setState(() {
        _voiceOwned = false;
        _voiceLocked = false;
        _voiceFinishing = false;
        _voiceReadyText = transcript;
        _voiceEditor.value = TextEditingValue(
          text: transcript,
          selection: TextSelection.collapsed(offset: transcript.length),
        );
      });
    } catch (_) {
      if (mounted) setState(() => _voiceFinishing = false);
    }
  }

  Future<void> _sendVoice() async {
    final transcript = (_voiceReadyText ?? _voiceEditor.text).trim();
    if (transcript.isEmpty) return;
    final prefix = _voiceBaseText.trim();
    final text = prefix.isEmpty ? transcript : '$prefix $transcript';
    final result = await widget.onSend?.call(ChatInputData(text: text));
    if (!mounted) return;
    if (result == ChatInputSubmissionResult.sent ||
        result == ChatInputSubmissionResult.queued) {
      setState(() {
        _voiceReadyText = null;
        _voiceEditor.clear();
        _voiceBaseText = '';
      });
    }
  }

  Future<void> _sendDraft() async {
    final draft = widget.mediaController.snapshotInput(
      widget.inputController.text,
    );
    if (draft.text.isEmpty && !widget.mediaController.hasDraftMedia) return;
    final result = await widget.onSend?.call(draft);
    if (!mounted) return;
    if (result == ChatInputSubmissionResult.sent ||
        result == ChatInputSubmissionResult.queued) {
      widget.inputController.clear();
      widget.mediaController.clearDraft();
    }
  }

  Future<void> _openFullscreenEditor() async {
    final editor = TextEditingController(text: widget.inputController.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 12,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '编辑消息',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Lucide.FoldVertical),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
              Expanded(
                child: TextField(
                  controller: editor,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) widget.inputController.value = editor.value;
    editor.dispose();
  }

  Future<void> _openVoiceFullscreenEditor() async {
    setState(() => _voiceEditing = true);
    final focusNode = FocusNode();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 12,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: TextField(
            controller: _voiceEditor,
            focusNode: focusNode,
            autofocus: true,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: '编辑语音转写',
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
    focusNode.dispose();
  }

  Widget _actionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    bool primary = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final button = IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        maximumSize: const Size(40, 40),
        backgroundColor: primary ? cs.primary : Colors.transparent,
        foregroundColor: primary ? cs.onPrimary : cs.onSurface,
      ),
    );
    if (onLongPress == null) return button;
    return GestureDetector(onLongPress: onLongPress, child: button);
  }

  Widget _buildCompactActions() {
    final hasDraft = widget.inputController.text.trim().isNotEmpty ||
        widget.mediaController.hasDraftMedia;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            _actionButton(icon: Lucide.Plus, onPressed: widget.onMore),
            const Spacer(),
            Tooltip(
              message: widget.reasoningBudget == -1
                  ? '模型与思考 · 自动'
                  : '模型与思考',
              child: _actionButton(
                icon: Lucide.Brain,
                onPressed: widget.supportsReasoning
                    ? widget.onConfigureReasoning
                    : widget.onSelectModel,
                onLongPress: widget.onSelectModel,
              ),
            ),
            GestureDetector(
              onLongPressStart: (_) => unawaited(_startVoice()),
              onLongPressMoveUpdate: (details) {
                if (!_voiceOwned) return;
                final delta = details.localOffsetFromOrigin;
                if (delta.dy < -44 && !_voiceLocked) {
                  setState(() => _voiceLocked = true);
                } else if (delta.dx < -56) {
                  unawaited(_cancelVoice());
                }
              },
              onLongPressEnd: (_) {
                if (_voiceOwned && !_voiceLocked) {
                  unawaited(_finishVoice());
                }
              },
              child: _actionButton(
                icon: Lucide.Mic,
                onPressed: () => unawaited(_startVoice()),
              ),
            ),
            if (widget.loading)
              _actionButton(
                icon: Lucide.Square,
                onPressed: widget.onStop,
                primary: true,
              )
            else
              _actionButton(
                icon: Lucide.ArrowUp,
                onPressed: hasDraft ? () => unawaited(_sendDraft()) : null,
                primary: hasDraft,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSurface() {
    final cs = Theme.of(context).colorScheme;
    final live = _voiceOwned
        ? widget.asrProvider.transcript
        : (_voiceReadyText ?? '');
    if (!_voiceEditing && live.isNotEmpty && _voiceEditor.text != live) {
      _voiceEditor.value = TextEditingValue(
        text: live,
        selection: TextSelection.collapsed(offset: live.length),
      );
    }

    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_voiceEditing || live.isNotEmpty || !_selectedAsrStreams)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: TextField(
                  controller: _voiceEditor,
                  readOnly: !_voiceEditing,
                  onTap: () => setState(() => _voiceEditing = true),
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: _selectedAsrStreams
                        ? '正在流式转写…'
                        : (_voiceOwned ? '结束录音后显示完整转写' : '转写完成'),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Lucide.Maximize2, size: 18),
                      onPressed: _openVoiceFullscreenEditor,
                    ),
                  ),
                ),
              ),
            if (_voiceSettingsExpanded) _buildVoiceSettings(),
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  _actionButton(
                    icon: Lucide.X,
                    onPressed: () => unawaited(_cancelVoice()),
                  ),
                  _actionButton(
                    icon: Lucide.Settings,
                    onPressed: () => setState(
                      () => _voiceSettingsExpanded = !_voiceSettingsExpanded,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _voiceLocked
                            ? '已锁定'
                            : _voiceOwned
                                ? (_selectedAsrStreams
                                    ? '流式录音中'
                                    : '录音中 · 非流式')
                                : '转写完成 · 待发送',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  if (_voiceOwned)
                    _actionButton(
                      icon: Lucide.Square,
                      onPressed: _voiceFinishing
                          ? null
                          : () => unawaited(_finishVoice()),
                      primary: true,
                    )
                  else
                    _actionButton(
                      icon: Lucide.ArrowUp,
                      onPressed: (_voiceReadyText?.trim().isNotEmpty ?? false)
                          ? () => unawaited(_sendVoice())
                          : null,
                      primary: _voiceReadyText?.trim().isNotEmpty ?? false,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSettings() {
    final selected = context.watch<SettingsProvider>().selectedAsrService;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _settingsRow('识别模型', selected?.name ?? '未配置'),
          _settingsRow('转写能力', _selectedAsrStreams ? '支持流式' : '非流式'),
          _settingsRow('降噪', '跟随服务设置'),
        ],
      ),
    );
  }

  Widget _settingsRow(String label, String value) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(value, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          bottom: 4,
          child: _voiceActive
              ? _buildVoiceSurface()
              : _buildCompactActions(),
        ),
        if (!_voiceActive && _lineCount >= 6)
          Positioned(
            right: 18,
            bottom: 54,
            child: IconButton.filledTonal(
              tooltip: '全屏编辑',
              icon: const Icon(Lucide.Maximize2, size: 18),
              onPressed: _openFullscreenEditor,
            ),
          ),
      ],
    );
  }
}
