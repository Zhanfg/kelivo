import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../icons/reasoning_icons.dart';

enum ComposerFullscreenAction { more, reasoning, model, voice, send }

class ComposerFullscreenEditor extends StatefulWidget {
  const ComposerFullscreenEditor({
    super.key,
    required this.initialValue,
    required this.onDraftChanged,
    required this.supportsReasoning,
    required this.reasoningBudget,
    required this.hasDraftMedia,
    required this.canOpenMore,
    required this.canUseVoice,
  });

  final TextEditingValue initialValue;
  final ValueChanged<TextEditingValue> onDraftChanged;
  final bool supportsReasoning;
  final int? reasoningBudget;
  final bool hasDraftMedia;
  final bool canOpenMore;
  final bool canUseVoice;

  @override
  State<ComposerFullscreenEditor> createState() =>
      _ComposerFullscreenEditorState();
}

class _ComposerFullscreenEditorState extends State<ComposerFullscreenEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController.fromValue(widget.initialValue);
    _controller.addListener(_syncDraft);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncDraft);
    _controller.dispose();
    super.dispose();
  }

  void _syncDraft() {
    widget.onDraftChanged(_controller.value);
    if (mounted) setState(() {});
  }

  void _finish([ComposerFullscreenAction? action]) {
    widget.onDraftChanged(_controller.value);
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSend =
        _controller.text.trim().isNotEmpty || widget.hasDraftMedia;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) widget.onDraftChanged(_controller.value);
      },
      child: Dialog.fullscreen(
        backgroundColor: cs.surface,
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
                      tooltip: 'Collapse editor',
                      icon: const Icon(Lucide.FoldVertical),
                      onPressed: _finish,
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(18, 12, 18, 18),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  children: [
                    _ActionButton(
                      tooltip: 'More',
                      icon: Lucide.Plus,
                      onTap: widget.canOpenMore
                          ? () => _finish(ComposerFullscreenAction.more)
                          : null,
                    ),
                    const Spacer(),
                    _ActionButton(
                      tooltip: widget.supportsReasoning
                          ? 'Reasoning / model'
                          : 'Model',
                      icon: widget.supportsReasoning
                          ? Lucide.Brain
                          : Lucide.Boxes,
                      onTap: () => _finish(
                        widget.supportsReasoning
                            ? ComposerFullscreenAction.reasoning
                            : ComposerFullscreenAction.model,
                      ),
                      onLongPress: () =>
                          _finish(ComposerFullscreenAction.model),
                      childBuilder: widget.supportsReasoning
                          ? (color) => ReasoningIcons.budgetIcon(
                                widget.reasoningBudget,
                                size: 20,
                                color: color,
                              )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    if (widget.canUseVoice) ...[
                      _ActionButton(
                        tooltip: 'Voice input',
                        icon: Lucide.Mic,
                        onTap: () =>
                            _finish(ComposerFullscreenAction.voice),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _ActionButton(
                      tooltip: 'Send',
                      icon: Lucide.ArrowUp,
                      primary: true,
                      onTap: canSend
                          ? () => _finish(ComposerFullscreenAction.send)
                          : null,
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.childBuilder,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget Function(Color color)? childBuilder;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final foreground = primary
        ? (enabled ? cs.onPrimary : cs.onSurfaceVariant)
        : cs.onSurface;
    final background = primary
        ? (enabled ? cs.primary : cs.surfaceContainerHighest)
        : Colors.transparent;
    final child = childBuilder?.call(foreground) ??
        Icon(icon, size: 20, color: foreground);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(width: 40, height: 40, child: Center(child: child)),
        ),
      ),
    );
  }
}
