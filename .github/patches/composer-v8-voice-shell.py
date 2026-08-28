from pathlib import Path
import re


def fail(label, detail):
    raise SystemExit(f"{label}: {detail}")


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        fail(label, f"expected 1 match, found {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def regex_once(path, pattern, repl, label):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    new_text, count = re.subn(pattern, repl, text, count=1, flags=re.M | re.S)
    if count != 1:
        fail(label, f"expected 1 regex match, found {count}")
    p.write_text(new_text, encoding="utf-8")


def create_voice_shell():
    path = Path("lib/features/home/composer/composer_voice_shell.dart")
    if path.exists():
        fail("voice-shell", "target file already exists")
    path.write_text(r'''import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

class ComposerVoiceShell extends StatelessWidget {
  const ComposerVoiceShell({
    super.key,
    required this.controller,
    required this.editable,
    required this.transcribing,
    required this.ready,
    required this.locked,
    required this.pttActive,
    required this.cancelArmed,
    required this.settingsExpanded,
    required this.supportsLiveTranscript,
    required this.serviceName,
    required this.modelLabel,
    required this.languageLabel,
    required this.activity,
    required this.onChanged,
    required this.onCancel,
    required this.onToggleSettings,
    required this.onStop,
    required this.onSend,
    required this.onFullscreen,
    required this.cancelTooltip,
    required this.stopTooltip,
    this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool editable;
  final bool transcribing;
  final bool ready;
  final bool locked;
  final bool pttActive;
  final bool cancelArmed;
  final bool settingsExpanded;
  final bool supportsLiveTranscript;
  final String serviceName;
  final String modelLabel;
  final String languageLabel;
  final Widget activity;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onToggleSettings;
  final VoidCallback? onStop;
  final VoidCallback? onSend;
  final VoidCallback onFullscreen;
  final String cancelTooltip;
  final String stopTooltip;

  String _stateLabel(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (ready) return zh ? '待发送' : 'Ready';
    if (transcribing) return zh ? '转写中…' : 'Transcribing…';
    if (locked) return zh ? '已锁定' : 'Locked';
    if (pttActive) return zh ? '按住说话' : 'Hold to talk';
    return zh ? '录音中' : 'Recording';
  }

  String _capability(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return supportsLiveTranscript ? (zh ? '流式' : 'Streaming') : (zh ? '非流式' : 'Non-streaming');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      key: const ValueKey('composer-voice-shell'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: Stack(
              children: [
                TextField(
                  key: const ValueKey('voice-transcript-field'),
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  readOnly: !editable,
                  minLines: 1,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: transcribing
                        ? (zh ? '正在生成完整转写…' : 'Building final transcript…')
                        : (zh ? '语音转写会显示在这里' : 'Transcript appears here'),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(8, 4, 34, 6),
                  ),
                ),
                PositionedDirectional(
                  top: 2,
                  end: 2,
                  child: IconButton(
                    key: const ValueKey('voice-fullscreen'),
                    tooltip: zh ? '全屏编辑转写' : 'Edit transcript fullscreen',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    onPressed: onFullscreen,
                    icon: const Icon(Lucide.Maximize2),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: settingsExpanded
                ? Container(
                    key: const ValueKey('voice-settings-inline'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Column(
                      children: [
                        _MetaRow(label: zh ? '语言' : 'Language', value: languageLabel),
                        _MetaRow(label: zh ? '识别模型' : 'Recognition model', value: modelLabel),
                        _MetaRow(label: zh ? '转写能力' : 'Transcription', value: _capability(context)),
                        _MetaRow(label: zh ? '降噪' : 'Noise reduction', value: zh ? '跟随服务设置' : 'Follow service settings'),
                        _MetaRow(label: zh ? '服务' : 'Service', value: serviceName),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Container(
            key: const ValueKey('voice-pill'),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.34),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('voice-cancel'),
                  tooltip: cancelTooltip,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: transcribing ? null : onCancel,
                  icon: const Icon(Lucide.X),
                ),
                IconButton(
                  key: const ValueKey('voice-settings-button'),
                  tooltip: zh ? '语音设置' : 'Voice settings',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onToggleSettings,
                  icon: const Icon(Lucide.Settings2),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: SizedBox(
                    key: const ValueKey('voice-activity'),
                    height: 32,
                    child: pttActive && !locked
                        ? Row(
                            key: const ValueKey('voice-ptt-hint'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                cancelArmed ? Lucide.ArrowLeft : Lucide.ArrowUp,
                                size: 14,
                                color: cancelArmed ? cs.error : cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  cancelArmed
                                      ? (zh ? '松开取消' : 'Release to cancel')
                                      : (zh ? '↑ 锁定 · ← 取消' : '↑ Lock · ← Cancel'),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cancelArmed ? cs.error : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : activity,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _stateLabel(context),
                  key: const ValueKey('voice-state-label'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  key: const ValueKey('voice-capability'),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _capability(context),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                if (transcribing)
                  const SizedBox(
                    key: ValueKey('voice-transcribing'),
                    width: 40,
                    child: Center(child: Icon(Lucide.Sparkles, size: 18)),
                  )
                else if (ready)
                  IconButton(
                    key: const ValueKey('voice-send'),
                    tooltip: zh ? '发送转写' : 'Send transcript',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: onSend,
                    icon: const Icon(Lucide.ArrowUp),
                  )
                else
                  IconButton(
                    key: const ValueKey('voice-stop'),
                    tooltip: stopTooltip,
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: onStop,
                    icon: const Icon(Lucide.Square),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ComposerVoiceMicTrigger extends StatelessWidget {
  const ComposerVoiceMicTrigger({
    super.key,
    required this.tooltip,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: const ValueKey('voice-mic-trigger'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: Icon(
              Lucide.Mic,
              size: 20,
              color: onTap == null
                  ? cs.onSurface.withValues(alpha: 0.34)
                  : cs.onSurface.withValues(alpha: 0.82),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
''', encoding="utf-8")


def patch_input_bar():
    path = "lib/features/home/widgets/chat_input_bar.dart"
    replace_once(
        path,
        "import '../composer/composer_reasoning_popover.dart';\n",
        "import '../composer/composer_reasoning_popover.dart';\nimport '../composer/composer_voice_shell.dart';\n",
        "import-voice-shell",
    )
    replace_once(
        path,
        """  bool _voiceSettingsExpanded = false;
  bool _ownsVoiceSession = false;
  bool _finishingVoice = false;
""",
        """  bool _voiceSettingsExpanded = false;
  bool _ownsVoiceSession = false;
  bool _finishingVoice = false;
  bool _voiceReady = false;
  bool _voicePttPending = false;
  bool _voicePttActive = false;
  bool _voicePttLocked = false;
  bool _voicePttCancelArmed = false;
  bool _voicePttReleasePending = false;
""",
        "voice-state-fields",
    )

    replace_once(
        path,
        """  Future<void> _startVoiceInput() async {
    final asr = widget.asrProvider;
""",
        """  Future<void> _startVoiceInput({bool ptt = false}) async {
    final asr = widget.asrProvider;
""",
        "voice-start-signature",
    )
    replace_once(
        path,
        """    _voiceBaseValue = _controller.value;
    _voiceLastObservedTranscript = '';
    _voiceTranscriptEditing = false;
    _voiceSettingsExpanded = false;
    _ownsVoiceSession = true;
""",
        """    _voiceBaseValue = _controller.value;
    _voiceLastObservedTranscript = '';
    _voiceTranscriptEditing = false;
    _voiceSettingsExpanded = false;
    _voiceReady = false;
    if (!ptt) _resetVoicePttState();
    _ownsVoiceSession = true;
""",
        "voice-start-reset",
    )

    replace_once(
        path,
        """      _voiceBaseValue = null;
      _ownsVoiceSession = false;
      _finishingVoice = false;
      _voiceLevels.clear();
      _resetVoiceTranscriptTracking();
      _reportVoiceFailure(error);
""",
        """      _voiceBaseValue = null;
      _ownsVoiceSession = false;
      _finishingVoice = false;
      _voiceReady = false;
      _voiceLevels.clear();
      _resetVoicePttState();
      _resetVoiceTranscriptTracking();
      _reportVoiceFailure(error);
""",
        "voice-error-state",
    )
    replace_once(
        path,
        """      final detectedSpeech = asr.transcript.trim().isNotEmpty;
      _voiceBaseValue = null;
      _ownsVoiceSession = false;
      _voiceLevels.clear();
      _resetVoiceTranscriptTracking();
      if (!detectedSpeech) _reportNoSpeech();
""",
        """      final detectedSpeech = asr.transcript.trim().isNotEmpty;
      _ownsVoiceSession = false;
      _voiceReady = detectedSpeech;
      if (!detectedSpeech) _voiceBaseValue = null;
      _voiceLevels.clear();
      _resetVoicePttState();
      _resetVoiceTranscriptTracking();
      if (!detectedSpeech) _reportNoSpeech();
""",
        "voice-auto-final-ready",
    )

    regex_once(
        path,
        r"""  Future<void> _cancelVoiceInput\(\) async \{.*?\n  \}\n\n  Future<void> _finishVoiceInput\(\) async \{""",
        r'''  Future<void> _cancelVoiceInput() async {
    if (!_ownsVoiceSession && !_voiceReady) return;
    _stopVoiceLevelSampling();
    final asr = widget.asrProvider;
    final original = _voiceBaseValue;
    final wasActive = _ownsVoiceSession;
    _voiceBaseValue = null;
    _ownsVoiceSession = false;
    _finishingVoice = false;
    _voiceReady = false;
    _voiceSettingsExpanded = false;
    _voiceLevels.clear();
    _resetVoicePttState();
    _resetVoiceTranscriptTracking();
    if (original != null) _controller.value = original;
    if (mounted) setState(() {});
    if (!wasActive) return;
    try {
      await asr?.cancel();
    } catch (error) {
      if (mounted) _reportVoiceFailure(error);
    }
  }

  Future<void> _finishVoiceInput() async {''',
        "voice-cancel-ready",
    )
    replace_once(
        path,
        """      final detectedSpeech = transcript.trim().isNotEmpty;
      _voiceBaseValue = null;
      _ownsVoiceSession = false;
      _voiceLevels.clear();
      _resetVoiceTranscriptTracking();
      setState(() {});
""",
        """      final detectedSpeech = transcript.trim().isNotEmpty;
      _ownsVoiceSession = false;
      _voiceReady = detectedSpeech;
      if (!detectedSpeech) _voiceBaseValue = null;
      _voiceLevels.clear();
      _resetVoicePttState();
      _resetVoiceTranscriptTracking();
      setState(() {});
""",
        "voice-finish-ready",
    )
    replace_once(
        path,
        """        _voiceBaseValue = null;
        _ownsVoiceSession = false;
        _voiceLevels.clear();
        _resetVoiceTranscriptTracking();
""",
        """        _voiceBaseValue = null;
        _ownsVoiceSession = false;
        _voiceReady = false;
        _voiceLevels.clear();
        _resetVoicePttState();
        _resetVoiceTranscriptTracking();
""",
        "voice-finish-error",
    )

    old_recording = r'''  /// Recording row stays intentionally compact: cancel, one continuous
  /// waveform/transcribing surface, and Stop. Sending is only available after
  /// transcription returns to the normal Composer action row.
  Widget _buildVoiceRecordingRow(BuildContext context, ThemeData theme) {'''
    if old_recording not in Path(path).read_text(encoding="utf-8"):
        fail("voice-recording-anchor", "anchor missing")

    helper_block = r'''  void _resetVoicePttState() {
    _voicePttPending = false;
    _voicePttActive = false;
    _voicePttLocked = false;
    _voicePttCancelArmed = false;
    _voicePttReleasePending = false;
  }

  Future<void> _submitVoiceReady() async {
    if (!_voiceReady || _finishingVoice) return;
    _voiceReady = false;
    _voiceBaseValue = null;
    _voiceSettingsExpanded = false;
    if (mounted) setState(() {});
    await _handleSend();
  }

  void _toggleVoiceShellSettings() {
    if (!_ownsVoiceSession && !_voiceReady) return;
    setState(() => _voiceSettingsExpanded = !_voiceSettingsExpanded);
  }

  void _beginVoicePtt(LongPressStartDetails _) {
    final settings = context.read<SettingsProvider>();
    final selected = settings.selectedAsrService;
    final asr = widget.asrProvider;
    if (_composerLocked ||
        widget.loading ||
        selected == null ||
        asr == null ||
        !asr.canUse(selected) ||
        _ownsVoiceSession ||
        _voiceReady ||
        _voicePttPending) {
      return;
    }
    _voicePttPending = true;
    _voicePttActive = false;
    _voicePttLocked = false;
    _voicePttCancelArmed = false;
    _voicePttReleasePending = false;
    setState(() {});
    unawaited(
      _startVoiceInput(ptt: true).then((_) async {
        if (!mounted) return;
        _voicePttPending = false;
        if (!_ownsVoiceSession) {
          _resetVoicePttState();
          setState(() {});
          return;
        }
        _voicePttActive = true;
        setState(() {});
        if (_voicePttCancelArmed) {
          await _cancelVoiceInput();
        } else if (_voicePttReleasePending && !_voicePttLocked) {
          await _finishVoiceInput();
        }
      }),
    );
  }

  void _updateVoicePtt(LongPressMoveUpdateDetails details) {
    if (!_voicePttPending && !_voicePttActive) return;
    final offset = details.offsetFromOrigin;
    final cancel = offset.dx <= -56;
    final lock = !cancel && offset.dy <= -44;
    if (cancel == _voicePttCancelArmed && (!lock || _voicePttLocked)) return;
    setState(() {
      _voicePttCancelArmed = cancel;
      if (lock) _voicePttLocked = true;
    });
  }

  void _endVoicePtt(LongPressEndDetails _) {
    if (_voicePttPending && !_voicePttActive) {
      _voicePttReleasePending = true;
      return;
    }
    if (!_voicePttActive) return;
    if (_voicePttCancelArmed) {
      unawaited(_cancelVoiceInput());
    } else if (!_voicePttLocked) {
      unawaited(_finishVoiceInput());
    }
  }

  String _voiceModelLabel(AsrServiceOptions service) {
    return switch (service) {
      SherpaOnnxAsrOptions value => value.modelId.trim().isEmpty ? value.name : value.modelId,
      SystemAsrOptions value => value.name,
      OpenAiRealtimeAsrOptions value => value.model,
      DashScopeAsrOptions value => value.model,
      QwenAudioAsrOptions value => value.model,
      VolcengineAsrOptions value => value.resourceId,
      MimoAsrOptions value => value.model,
      StepAsrOptions value => value.model,
    };
  }

  String _voiceLanguageLabel(BuildContext context, AsrServiceOptions service) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final raw = switch (service) {
      SherpaOnnxAsrOptions value => value.language,
      SystemAsrOptions value => value.localeId,
      OpenAiRealtimeAsrOptions value => value.language,
      DashScopeAsrOptions value => value.language,
      QwenAudioAsrOptions _ => '',
      VolcengineAsrOptions value => value.language,
      MimoAsrOptions value => value.language,
      StepAsrOptions value => value.language,
    };
    if (raw.trim().isEmpty || raw.trim().toLowerCase() == 'auto') {
      return zh ? '自动' : 'Auto';
    }
    return raw.trim();
  }

  Future<void> _openVoiceTranscriptEditor() async {
    if (!_ownsVoiceSession && !_voiceReady) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final editorFocus = FocusNode();
    try {
      await showDialog<void>(
        context: context,
        useSafeArea: false,
        builder: (dialogContext) => Dialog.fullscreen(
          child: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('voice-editor-close'),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Lucide.ArrowLeft),
                      ),
                      Expanded(
                        child: Text(
                          zh ? '编辑语音转写' : 'Edit voice transcript',
                          style: TextStyle(fontWeight: AppFontWeights.semibold),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          _ownsVoiceSession
                              ? (zh ? '录音继续' : 'Recording continues')
                              : (zh ? '待发送' : 'Ready'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      key: const ValueKey('voice-fullscreen-field'),
                      controller: _controller,
                      focusNode: editorFocus,
                      autofocus: true,
                      onChanged: _onTextChanged,
                      readOnly:
                          _ownsVoiceSession &&
                          widget.asrProvider?.supportsLiveTranscript != true,
                      minLines: null,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      editorFocus.dispose();
    }
  }

  Widget _buildComposerVoiceShell(
    BuildContext context,
    ThemeData theme,
    AsrServiceOptions service,
  ) {
    final asr = widget.asrProvider;
    final live = asr?.supportsLiveTranscript == true;
    final editable = _voiceReady || (_ownsVoiceSession && !_finishingVoice && live);
    final l10n = AppLocalizations.of(context)!;
    final activity = _finishingVoice
        ? _VoiceTranscribingIndicator(
            key: const ValueKey('voice-transcribing-indicator'),
            label: l10n.chatInputBarVoiceTranscribing,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          )
        : ValueListenableBuilder<int>(
            valueListenable: _voiceLevelsVersion,
            builder: (context, _, _) => _VoiceWaveform(
              key: const ValueKey('voice-waveform'),
              levels: _voiceLevels,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          );
    return ComposerVoiceShell(
      controller: _controller,
      focusNode: widget.focusNode,
      editable: editable,
      transcribing: _finishingVoice,
      ready: _voiceReady,
      locked: _voicePttLocked,
      pttActive: _voicePttActive,
      cancelArmed: _voicePttCancelArmed,
      settingsExpanded: _voiceSettingsExpanded,
      supportsLiveTranscript: live,
      serviceName: service.name,
      modelLabel: _voiceModelLabel(service),
      languageLabel: _voiceLanguageLabel(context, service),
      activity: activity,
      onChanged: _onTextChanged,
      onCancel: () => unawaited(_cancelVoiceInput()),
      onToggleSettings: _toggleVoiceShellSettings,
      onStop: _finishingVoice ? null : () => unawaited(_finishVoiceInput()),
      onSend: _voiceReady ? () => unawaited(_submitVoiceReady()) : null,
      onFullscreen: () => unawaited(_openVoiceTranscriptEditor()),
      cancelTooltip: l10n.chatInputBarVoiceCancelTooltip,
      stopTooltip: l10n.chatInputBarVoiceStopTooltip,
    );
  }

'''
    replace_once(path, old_recording, helper_block + old_recording, "voice-helpers")

    replace_once(
        path,
        """    final voiceTranscriptEditable =
        _ownsVoiceSession &&
        !_finishingVoice &&
        asr?.supportsLiveTranscript == true;
""",
        """    final voiceTranscriptEditable =
        _ownsVoiceSession &&
        !_finishingVoice &&
        asr?.supportsLiveTranscript == true;
    final showVoiceShell =
        selectedAsrService != null && (_ownsVoiceSession || _voiceReady);
""",
        "build-voice-shell-state",
    )
    replace_once(
        path,
        """                          if (widget.hasQueuedInput) ...[
""",
        """                          if (widget.hasQueuedInput && !showVoiceShell) ...[
""",
        "hide-queue-during-voice",
    )
    replace_once(
        path,
        """                          if (showGenerationDraftActions)
""",
        """                          if (showVoiceShell)
                            _buildComposerVoiceShell(
                              context,
                              theme,
                              selectedAsrService,
                            ),
                          if (showGenerationDraftActions && !showVoiceShell)
""",
        "insert-voice-shell",
    )
    replace_once(
        path,
        """                          if (hasDocs || hasImages)
                            _buildInlineAttachmentPreviews(context, isDark),
                          // Input field with expand/collapse button
                          Stack(
""",
        """                          if ((hasDocs || hasImages) && !showVoiceShell)
                            _buildInlineAttachmentPreviews(context, isDark),
                          // Input field with expand/collapse button
                          if (!showVoiceShell)
                            Stack(
""",
        "hide-attachments-field",
    )
    replace_once(
        path,
        """                          AnimatedSize(
                            duration: const Duration(milliseconds: 180),
""",
        """                          if (!showVoiceShell)
                            AnimatedSize(
                            duration: const Duration(milliseconds: 180),
""",
        "hide-idle-settings",
    )
    replace_once(
        path,
        """                          // Bottom buttons row (no divider)
                          Padding(
""",
        """                          // Bottom buttons row (no divider)
                          if (!showVoiceShell)
                            Padding(
""",
        "hide-normal-actions",
    )

    mic_pattern = r"""                                            if \(showVoiceInput\) \.\.\.\[\n\s+_CompactIconButton\(\n\s+tooltip: AppLocalizations\.of\(\n\s+context,\n\s+\)!\.chatInputBarVoiceInputTooltip,\n\s+icon: Lucide\.Mic,\n\s+active: _voiceSettingsExpanded,\n\s+onTap:\n\s+_composerLocked \|\|\n\s+widget\.loading\n\s+\? null\n\s+: selectedVoiceServiceUsable\n\s+\? \(\) => unawaited\(\n\s+_startVoiceInput\(\),\n\s+\)\n\s+: _toggleInlineVoiceSettings,\n\s+onLongPress:\n\s+_composerLocked \|\|\n\s+widget\.loading\n\s+\? null\n\s+: _toggleInlineVoiceSettings,\n\s+allowLongPressOnDesktop:\n\s+isMobileLayout,\n\s+\),\n\s+const SizedBox\(width: 8\),\n\s+\],"""
    mic_repl = r'''                                            if (showVoiceInput) ...[
                                              ComposerVoiceMicTrigger(
                                                tooltip: AppLocalizations.of(
                                                  context,
                                                )!.chatInputBarVoiceInputTooltip,
                                                onTap:
                                                    _composerLocked || widget.loading
                                                    ? null
                                                    : selectedVoiceServiceUsable
                                                    ? () => unawaited(
                                                        _startVoiceInput(),
                                                      )
                                                    : _toggleInlineVoiceSettings,
                                                onLongPressStart:
                                                    _composerLocked ||
                                                        widget.loading ||
                                                        !selectedVoiceServiceUsable
                                                    ? null
                                                    : _beginVoicePtt,
                                                onLongPressMoveUpdate:
                                                    selectedVoiceServiceUsable
                                                    ? _updateVoicePtt
                                                    : null,
                                                onLongPressEnd:
                                                    selectedVoiceServiceUsable
                                                    ? _endVoicePtt
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                            ],'''
    regex_once(path, mic_pattern, mic_repl, "replace-mic-trigger")

    replace_once(
        path,
        """    if (_isSubmitting ||
        _hasUnreadyImages ||
        _ownsVoiceSession ||
        _finishingVoice) {
""",
        """    if (_isSubmitting ||
        _hasUnreadyImages ||
        _ownsVoiceSession ||
        _finishingVoice) {
""",
        "submit-guard-unchanged",
    )


def patch_asr_tests():
    path = "test/features/home/widgets/chat_input_bar_asr_test.dart"
    regex_once(
        path,
        r"""  testWidgets\(\n    'long-press mic opens inline service switcher and selection collapses it',.*?\n  \);\n\n  testWidgets\('system ASR replaces partials from a stable draft base'""",
        r'''  testWidgets(
    'long-press mic enters PTT and upward drag locks recording',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      await settings.loaded;
      final option = SystemAsrOptions(id: 'system-ptt', name: 'System PTT');
      await settings.setAsrServices(<AsrServiceOptions>[option]);
      await settings.setSelectedAsrServiceId(option.id);
      final backend = _FakeSystemBackend();
      final asr = AsrProvider(systemService: SystemAsrService(backend: backend));
      final controller = TextEditingController();
      addTearDown(asr.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        harness(settings: settings, asr: asr, controller: controller),
      );
      final mic = find.byKey(const ValueKey('voice-mic-trigger'));
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 650));
      backend.emitTranscript('ptt text', false);
      await tester.pump();

      expect(find.byKey(const ValueKey('composer-voice-shell')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-ptt-hint')), findsOneWidget);

      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(find.text('Locked'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(asr.isActive, isTrue);

      await tester.tap(find.byKey(const ValueKey('voice-stop')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-send')), findsOneWidget);
    },
  );

  testWidgets('system ASR replaces partials from a stable draft base' ''',
        "replace-longpress-test",
    )

    replace_once(
        path,
        """    expect(controller.text, 'draft hello world');
    expect(find.byTooltip('Voice input'), findsOneWidget);
""",
        """    expect(controller.text, 'draft hello world');
    expect(find.byKey(const ValueKey('composer-voice-shell')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-send')), findsOneWidget);
""",
        "system-ready-shell",
    )
    replace_once(
        path,
        """    expect(sendCalls, 0);
    expect(controller.text, 'draft hello brave world again');
    expect(find.byTooltip('Voice input'), findsOneWidget);
""",
        """    expect(sendCalls, 0);
    expect(controller.text, 'draft hello brave world again');
    expect(find.byKey(const ValueKey('voice-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-voice-shell')), findsOneWidget);
""",
        "editable-ready-shell",
    )
    replace_once(
        path,
        """    expect(
      find.byKey(const ValueKey('voice-transcribing-indicator')),
      findsNothing,
    );
  });
""",
        """    expect(
      find.byKey(const ValueKey('voice-transcribing-indicator')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('voice-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-capability')), findsOneWidget);
  });
""",
        "local-ready-shell",
    )

    marker = """  testWidgets('cancelling ASR restores the exact original editing value', (
"""
    extra = r'''  testWidgets('voice settings stay inside the same shell and fullscreen uses IME field', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    final option = SystemAsrOptions(id: 'system-shell', name: 'System Shell');
    await settings.setAsrServices(<AsrServiceOptions>[option]);
    await settings.setSelectedAsrServiceId(option.id);
    final backend = _FakeSystemBackend();
    final asr = AsrProvider(systemService: SystemAsrService(backend: backend));
    final controller = TextEditingController();
    addTearDown(asr.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness(settings: settings, asr: asr, controller: controller),
    );
    await tester.tap(find.byTooltip('Voice input'));
    await tester.pump();
    backend.emitTranscript('editable transcript', false);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('voice-settings-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('voice-settings-inline')), findsOneWidget);
    expect(find.text('System Shell'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-fullscreen-field')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byKey(const ValueKey('voice-editor-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('voice-stop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-send')), findsOneWidget);
  });

'''
    replace_once(path, marker, extra + marker, "add-shell-settings-test")


def validate():
    bar = Path("lib/features/home/widgets/chat_input_bar.dart").read_text(encoding="utf-8")
    for token in [
        "composer_voice_shell.dart",
        "_voiceReady",
        "_beginVoicePtt",
        "_openVoiceTranscriptEditor",
        "ComposerVoiceMicTrigger",
        "_buildComposerVoiceShell",
    ]:
        if token not in bar:
            fail("validate-input-bar", f"missing {token}")
    shell = Path("lib/features/home/composer/composer_voice_shell.dart").read_text(encoding="utf-8")
    for token in [
        "composer-voice-shell",
        "voice-pill",
        "voice-ptt-hint",
        "voice-settings-inline",
        "voice-send",
        "voice-transcribing",
    ]:
        if token not in shell:
            fail("validate-shell", f"missing {token}")


create_voice_shell()
patch_input_bar()
patch_asr_tests()
validate()
print("Composer v8 voice shell patch applied")
