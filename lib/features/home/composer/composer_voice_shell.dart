import 'package:flutter/material.dart';

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
    return supportsLiveTranscript
        ? (zh ? '流式' : 'Streaming')
        : (zh ? '非流式' : 'Non-streaming');
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
                        _MetaRow(
                          label: zh ? '语言' : 'Language',
                          value: languageLabel,
                        ),
                        _MetaRow(
                          label: zh ? '识别模型' : 'Recognition model',
                          value: modelLabel,
                        ),
                        _MetaRow(
                          label: zh ? '转写能力' : 'Transcription',
                          value: _capability(context),
                        ),
                        _MetaRow(
                          label: zh ? '降噪' : 'Noise reduction',
                          value: zh ? '跟随服务设置' : 'Follow service settings',
                        ),
                        if (serviceName != modelLabel)
                          _MetaRow(
                            label: zh ? '服务' : 'Service',
                            value: serviceName,
                          ),
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
                                color: cancelArmed
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  cancelArmed
                                      ? (zh ? '松开取消' : 'Release to cancel')
                                      : (zh
                                            ? '↑ 锁定 · ← 取消'
                                            : '↑ Lock · ← Cancel'),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cancelArmed
                                        ? cs.error
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : activity,
                  ),
                ),
                const SizedBox(width: 7),
                KeyedSubtree(
                  key: ValueKey(
                    ready
                        ? 'voice-state-ready'
                        : transcribing
                        ? 'voice-state-transcribing'
                        : locked
                        ? 'voice-state-locked'
                        : pttActive
                        ? 'voice-state-ptt'
                        : 'voice-state-recording',
                  ),
                  child: Text(
                    _stateLabel(context),
                    key: const ValueKey('voice-state-label'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  key: const ValueKey('voice-capability'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
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
