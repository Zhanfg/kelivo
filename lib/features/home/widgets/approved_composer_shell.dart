import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_input_data.dart';
import '../../../core/providers/asr_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/asr/asr_service_options.dart';
import '../../../icons/lucide_adapter.dart';
import 'chat_input_bar.dart';

/// Visible composer that mirrors the approved HTML interaction model.
///
/// The legacy [ChatInputBar] stays mounted offstage so its mature attachment,
/// clipboard/import, recovery and media-controller paths remain alive. This
/// widget is the only painted composer surface.
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
    this.hasQueuedInput = false,
    this.queuedPreviewText,
    this.onCancelQueuedInput,
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
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final VoidCallback? onCancelQueuedInput;
  final VoidCallback? onMore;
  final VoidCallback? onSelectModel;
  final VoidCallback? onConfigureReasoning;
  final VoidCallback? onStop;
  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;

  @override
  State<ApprovedComposerShell> createState() => _ApprovedComposerShellState();
}

class _ApprovedComposerShellState extends State<ApprovedComposerShell> {
  Timer? _mediaPoll;
  String _mediaFingerprint = '';
  ChatInputData _mediaSnapshot = const ChatInputData(text: '');

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
    _mediaPoll = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) => _refreshMediaSnapshot(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshMediaSnapshot());
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
    _mediaPoll?.cancel();
    widget.inputController.removeListener(_handleDraftChanged);
    widget.asrProvider.removeListener(_handleAsrChanged);
    if (_voiceOwned) unawaited(widget.asrProvider.cancel());
    _voiceEditor.dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    if (mounted) setState(() {});
  }

  void _refreshMediaSnapshot() {
    if (!mounted) return;
    final snapshot = widget.mediaController.snapshotInput(widget.inputController.text);
    final fingerprint = [
      ...snapshot.imagePaths,
      ...snapshot.documents.map((e) => '${e.path}|${e.fileName}|${e.mime}'),
    ].join('\u0000');
    if (fingerprint == _mediaFingerprint) return;
    _mediaFingerprint = fingerprint;
    _mediaSnapshot = snapshot;
    setState(() {});
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
    return selected is! SherpaOnnxAsrOptions;
  }

  Future<void> _startVoice({bool locked = false}) async {
    if (_voiceActive || widget.loading) return;
    final selected = context.read<SettingsProvider>().selectedAsrService;
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
      if (mounted) setState(() => _voiceOwned = false);
    }
  }

  Future<void> _cancelVoice() async {
    await widget.asrProvider.cancel();
    if (!mounted) return;
    setState(() {
      _voiceOwned = false;
      _voiceLocked = false;
      _voiceSettingsExpanded = false;
      _voiceEditing = false;
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
    final draft = widget.mediaController.snapshotInput(widget.inputController.text);
    if (draft.text.isEmpty && draft.imagePaths.isEmpty && draft.documents.isEmpty) {
      return;
    }
    final result = await widget.onSend?.call(draft);
    if (!mounted) return;
    if (result == ChatInputSubmissionResult.sent ||
        result == ChatInputSubmissionResult.queued) {
      widget.inputController.clear();
      widget.mediaController.clearDraft();
      _refreshMediaSnapshot();
    }
  }

  Future<void> _openFullscreenEditor() async {
    final editor = TextEditingController(text: widget.inputController.text);
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 58,
                child: Row(
                  children: [
                    const SizedBox(width: 18),
                    const Expanded(
                      child: Text(
                        '编辑消息',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Lucide.Minimize2),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: editor,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(18),
                  ),
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
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 58,
                child: Row(
                  children: [
                    const SizedBox(width: 18),
                    const Expanded(
                      child: Text(
                        '语音转写',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Lucide.Minimize2),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _voiceEditor,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '编辑语音转写',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
    bool stop = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        maximumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(stop ? 13 : 999),
        ),
        backgroundColor: primary
            ? (enabled ? cs.primary : cs.surfaceContainerHighest)
            : Colors.transparent,
        foregroundColor: primary
            ? (enabled ? cs.onPrimary : cs.onSurfaceVariant)
            : cs.onSurface,
      ),
    );
  }

  int _visualLines(BuildContext context, double maxWidth) {
    final text = widget.inputController.text;
    if (text.isEmpty) return 1;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: math.max(48, maxWidth - 56));
    return painter.computeLineMetrics().length;
  }

  Widget _buildAttachments() {
    final images = _mediaSnapshot.imagePaths;
    final docs = _mediaSnapshot.documents;
    if (images.isEmpty && docs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final path in images)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: path.startsWith('http') || path.startsWith('data:')
                      ? Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Icon(Lucide.Image, size: 20),
                        )
                      : Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Icon(Lucide.ImageOff, size: 20),
                          ),
                        ),
                ),
              ),
            ),
          for (final doc in docs)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              constraints: const BoxConstraints(maxWidth: 150),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Lucide.FileText, size: 18),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      doc.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueBanner() {
    if (!widget.hasQueuedInput) return const SizedBox.shrink();
    final preview = widget.queuedPreviewText?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Lucide.ListPlus, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (preview == null || preview.isEmpty) ? '队列中有待发送内容' : preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          if (widget.onCancelQueuedInput != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Lucide.X, size: 16),
              onPressed: widget.onCancelQueuedInput,
            ),
        ],
      ),
    );
  }

  Widget _buildNormalComposer() {
    final cs = Theme.of(context).colorScheme;
    final snapshot = widget.mediaController.snapshotInput(widget.inputController.text);
    final hasDraft = snapshot.text.isNotEmpty ||
        snapshot.imagePaths.isNotEmpty ||
        snapshot.documents.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showExpand = _visualLines(context, constraints.maxWidth) >= 6;
        return Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQueueBanner(),
                _buildAttachments(),
                if (_mediaSnapshot.imagePaths.isNotEmpty ||
                    _mediaSnapshot.documents.isNotEmpty)
                  const SizedBox(height: 6),
                Stack(
                  children: [
                    TextField(
                      controller: widget.inputController,
                      minLines: 1,
                      maxLines: 6,
                      readOnly: widget.hasQueuedInput,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: '输入消息…',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(
                          8,
                          5,
                          showExpand ? 42 : 8,
                          10,
                        ),
                      ),
                    ),
                    if (showExpand)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          tooltip: '全屏编辑',
                          icon: const Icon(Lucide.Maximize2, size: 18),
                          onPressed: _openFullscreenEditor,
                        ),
                      ),
                  ],
                ),
                if (widget.loading && hasDraft) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () => unawaited(_sendDraft()),
                      icon: const Icon(Lucide.ListPlus, size: 17),
                      label: const Text('加入队列'),
                    ),
                  ),
                ],
                Row(
                  children: [
                    _iconButton(icon: Lucide.Plus, onPressed: widget.onMore),
                    const Spacer(),
                    GestureDetector(
                      onLongPress: widget.onSelectModel,
                      child: _iconButton(
                        icon: Lucide.Brain,
                        onPressed: widget.supportsReasoning
                            ? widget.onConfigureReasoning
                            : widget.onSelectModel,
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
                      child: _iconButton(
                        icon: Lucide.Mic,
                        onPressed: widget.loading
                            ? null
                            : () => unawaited(_startVoice()),
                      ),
                    ),
                    if (widget.loading)
                      _iconButton(
                        icon: Lucide.Pause,
                        onPressed: widget.onStop,
                        primary: true,
                        stop: true,
                      )
                    else
                      _iconButton(
                        icon: Lucide.ArrowUp,
                        onPressed: hasDraft ? () => unawaited(_sendDraft()) : null,
                        primary: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceSettings() {
    final selected = context.watch<SettingsProvider>().selectedAsrService;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  Widget _buildVoiceSurface() {
    final cs = Theme.of(context).colorScheme;
    final live = _voiceOwned ? widget.asrProvider.transcript : (_voiceReadyText ?? '');
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
        padding: const EdgeInsets.all(10),
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
              height: 58,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  _iconButton(
                    icon: Lucide.X,
                    onPressed: () => unawaited(_cancelVoice()),
                  ),
                  _iconButton(
                    icon: Lucide.Settings,
                    onPressed: () => setState(
                      () => _voiceSettingsExpanded = !_voiceSettingsExpanded,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _voiceLocked
                          ? const Text('↑ 已锁定', style: TextStyle(fontSize: 11))
                          : _voiceOwned
                              ? Text(
                                  _selectedAsrStreams
                                      ? '流式录音中 · ↑锁定  ←取消'
                                      : '录音中 · 非流式 · ↑锁定  ←取消',
                                  style: const TextStyle(fontSize: 10),
                                )
                              : const Text(
                                  '转写完成 · 待发送',
                                  style: TextStyle(fontSize: 11),
                                ),
                    ),
                  ),
                  if (_voiceOwned)
                    _iconButton(
                      icon: Lucide.Square,
                      onPressed: _voiceFinishing
                          ? null
                          : () => unawaited(_finishVoice()),
                      primary: true,
                    )
                  else
                    _iconButton(
                      icon: Lucide.ArrowUp,
                      onPressed: (_voiceReadyText?.trim().isNotEmpty ?? false)
                          ? () => unawaited(_sendVoice())
                          : null,
                      primary: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Offstage(offstage: true, child: widget.child),
        SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: _voiceActive ? _buildVoiceSurface() : _buildNormalComposer(),
          ),
        ),
      ],
    );
  }
}
