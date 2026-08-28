from pathlib import Path

path = Path('lib/features/home/widgets/chat_input_bar.dart')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    "  bool _isExpanded = false; // Track expand/collapse state for input field\n",
    "",
    'remove legacy local expand flag',
)

replace_once(
    """  /// Returns the number of lines in the input text (minimum 1).\n  int get _lineCount {\n    final text = _controller.text;\n    if (text.isEmpty) return 1;\n    return text.split('\\n').length;\n  }\n\n  /// Whether to show the expand/collapse button (when text has 3+ lines).\n  bool get _showExpandButton => _lineCount >= 3;\n\n  // ---------------------------------------------------------------------------\n  // Voice input\n""",
    """  int _visualLineCount(BuildContext context, double maxWidth) {\n    final value = _controller.text;\n    if (value.isEmpty) return 1;\n    final isDesktop =\n        Platform.isWindows || Platform.isLinux || Platform.isMacOS;\n    final painter = TextPainter(\n      text: TextSpan(\n        text: value,\n        style: TextStyle(fontSize: isDesktop ? 14 : 15),\n      ),\n      textDirection: Directionality.of(context),\n      textScaler: MediaQuery.textScalerOf(context),\n    )..layout(maxWidth: math.max(48, maxWidth));\n    return math.max(1, painter.computeLineMetrics().length);\n  }\n\n  Future<void> _openFullscreenEditor() async {\n    if (_composerLocked || _ownsVoiceSession) return;\n    final editor = TextEditingController.fromValue(_controller.value);\n    String? requestedAction;\n    final theme = Theme.of(context);\n    final settings = context.read<SettingsProvider>();\n    final selectedAsrService = settings.selectedAsrService;\n    final asr = widget.asrProvider;\n    final canUseVoice =\n        asr != null &&\n        selectedAsrService != null &&\n        asr.canUse(selectedAsrService) &&\n        !widget.loading;\n\n    await showDialog<void>(\n      context: context,\n      useSafeArea: false,\n      builder: (dialogContext) {\n        return Dialog.fullscreen(\n          backgroundColor: theme.colorScheme.surface,\n          child: SafeArea(\n            child: Column(\n              children: [\n                SizedBox(\n                  height: 58,\n                  child: Row(\n                    children: [\n                      const SizedBox(width: 18),\n                      Expanded(\n                        child: Text(\n                          AppLocalizations.of(context)!.chatInputBarHint,\n                          style: const TextStyle(fontWeight: FontWeight.w600),\n                        ),\n                      ),\n                      IconButton(\n                        tooltip: 'Collapse editor',\n                        icon: const Icon(Lucide.FoldVertical),\n                        onPressed: () => Navigator.of(dialogContext).pop(),\n                      ),\n                      const SizedBox(width: 8),\n                    ],\n                  ),\n                ),\n                Expanded(\n                  child: Focus(\n                    onKeyEvent: _handleKeyEvent,\n                    child: TextField(\n                      controller: editor,\n                      autofocus: true,\n                      expands: true,\n                      minLines: null,\n                      maxLines: null,\n                      keyboardType: TextInputType.multiline,\n                      textAlignVertical: TextAlignVertical.top,\n                      decoration: const InputDecoration(\n                        border: InputBorder.none,\n                        contentPadding: EdgeInsets.fromLTRB(18, 12, 18, 18),\n                      ),\n                    ),\n                  ),\n                ),\n                Padding(\n                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),\n                  child: Row(\n                    children: [\n                      _CompactIconButton(\n                        icon: Lucide.Plus,\n                        onTap: widget.onMore == null\n                            ? null\n                            : () {\n                                requestedAction = 'more';\n                                Navigator.of(dialogContext).pop();\n                              },\n                      ),\n                      const Spacer(),\n                      _CompactIconButton(\n                        icon: widget.supportsReasoning\n                            ? Lucide.Brain\n                            : Lucide.Boxes,\n                        onTap: () {\n                          requestedAction = widget.supportsReasoning\n                              ? 'reasoning'\n                              : 'model';\n                          Navigator.of(dialogContext).pop();\n                        },\n                        childBuilder: widget.supportsReasoning\n                            ? (color) => ReasoningIcons.budgetIcon(\n                                  widget.reasoningBudget,\n                                  size: 20,\n                                  color: color,\n                                )\n                            : null,\n                      ),\n                      const SizedBox(width: 8),\n                      if (canUseVoice) ...[\n                        _CompactIconButton(\n                          icon: Lucide.Mic,\n                          onTap: () {\n                            requestedAction = 'voice';\n                            Navigator.of(dialogContext).pop();\n                          },\n                        ),\n                        const SizedBox(width: 8),\n                      ],\n                      _CompactSendButton(\n                        enabled: editor.text.trim().isNotEmpty || _hasDraftMedia,\n                        onSend: () {\n                          requestedAction = 'send';\n                          Navigator.of(dialogContext).pop();\n                        },\n                        color: theme.colorScheme.primary,\n                        icon: Lucide.ArrowUp,\n                      ),\n                    ],\n                  ),\n                ),\n              ],\n            ),\n          ),\n        );\n      },\n    );\n\n    if (!mounted) {\n      editor.dispose();\n      return;\n    }\n    _controller.value = editor.value;\n    editor.dispose();\n    setState(() {});\n    switch (requestedAction) {\n      case 'more':\n        widget.onMore?.call();\n      case 'reasoning':\n        widget.onConfigureReasoning?.call();\n      case 'model':\n        widget.onSelectModel?.call();\n      case 'voice':\n        await _startVoiceInput();\n      case 'send':\n        await _handleSend();\n    }\n  }\n\n  // ---------------------------------------------------------------------------\n  // Voice input\n""",
    'replace newline-count expand with visual-line fullscreen editor',
)

replace_once(
    """    final size = MediaQuery.sizeOf(context);\n    final viewInsets = MediaQuery.viewInsetsOf(context);\n    final bool isMobileLayout = size.width < AppBreakpoints.tablet;\n""",
    """    final size = MediaQuery.sizeOf(context);\n    final viewInsets = MediaQuery.viewInsetsOf(context);\n    final bool isMobileLayout = size.width < AppBreakpoints.tablet;\n    final visualTextWidth = math.max(48.0, size.width - 72.0);\n    final showExpandButton =\n        _visualLineCount(context, visualTextWidth) >= 6;\n""",
    'compute six visual line threshold',
)

replace_once(
    "maxLines: _isExpanded ? 25 : 5,",
    "maxLines: 6,",
    'cap inline editor at six lines',
)

replace_once(
    "if (_showExpandButton)",
    "if (showExpandButton)",
    'show fullscreen control at six visual lines',
)

replace_once(
    """                                    onTap: () {\n                                      setState(\n                                        () => _isExpanded = !_isExpanded,\n                                      );\n                                      _ensureCaretVisible();\n                                    },\n                                    child: Icon(\n                                      _isExpanded\n                                          ? Lucide.ChevronsDownUp\n                                          : Lucide.ChevronsUpDown,\n""",
    """                                    onTap: () =>\n                                        unawaited(_openFullscreenEditor()),\n                                    child: Icon(\n                                      Lucide.Maximize2,\n""",
    'replace inline expand toggle with fullscreen affordance',
)

replace_once(
    """                                        Expanded(\n                                          child: _buildResponsiveLeftActions(\n                                            context,\n                                          ),\n                                        ),\n                                        Row(\n""",
    """                                        if (!isMobileLayout)\n                                          Expanded(\n                                            child: _buildResponsiveLeftActions(\n                                              context,\n                                            ),\n                                          )\n                                        else if (widget.showMoreButton)\n                                          _CompactIconButton(\n                                            tooltip: AppLocalizations.of(\n                                              context,\n                                            )!.chatInputBarMoreTooltip,\n                                            icon: Lucide.Plus,\n                                            active: widget.moreOpen,\n                                            onTap: _composerLocked\n                                                ? null\n                                                : widget.onMore,\n                                          ),\n                                        Row(\n""",
    'make plus the only left primary control on mobile',
)

replace_once(
    "if (widget.showMoreButton) ...[",
    "if (widget.showMoreButton && !isMobileLayout) ...[",
    'avoid duplicate plus on mobile',
)

replace_once(
    """                                            if (showVoiceInput) ...[\n""",
    """                                            if (isMobileLayout) ...[\n                                              _CompactIconButton(\n                                                tooltip: widget.supportsReasoning\n                                                    ? AppLocalizations.of(\n                                                        context,\n                                                      )!\n                                                        .chatInputBarReasoningStrengthTooltip\n                                                    : AppLocalizations.of(\n                                                        context,\n                                                      )!\n                                                        .chatInputBarSelectModelTooltip,\n                                                icon: widget.supportsReasoning\n                                                    ? Lucide.Brain\n                                                    : Lucide.Boxes,\n                                                active: widget.supportsReasoning &&\n                                                    widget.reasoningActive,\n                                                onTap: _composerLocked\n                                                    ? null\n                                                    : (widget.supportsReasoning\n                                                          ? widget\n                                                              .onConfigureReasoning\n                                                          : widget.onSelectModel),\n                                                onLongPress: _composerLocked\n                                                    ? null\n                                                    : widget.onSelectModel,\n                                                childBuilder:\n                                                    widget.supportsReasoning\n                                                    ? (color) => ReasoningIcons\n                                                          .budgetIcon(\n                                                            widget\n                                                                .reasoningBudget,\n                                                            size: 20,\n                                                            color: color,\n                                                          )\n                                                    : null,\n                                              ),\n                                              const SizedBox(width: 8),\n                                            ],\n                                            if (showVoiceInput) ...[\n""",
    'add combined model reasoning primary control on mobile',
)

path.write_text(text, encoding='utf-8')
print('Composer phase 1 source transform applied successfully')
