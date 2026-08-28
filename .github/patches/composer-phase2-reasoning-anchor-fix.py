from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def patch_popover() -> None:
    path = Path('lib/features/home/composer/composer_reasoning_popover.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """  required GlobalKey anchorKey,\n  required int? currentBudget,\n""",
        """  required LayerLink anchorLink,\n  required Rect anchorRect,\n  required int? currentBudget,\n""",
        'popover/public anchor args',
    )
    text = replace_once(
        text,
        """  final renderObject = anchorKey.currentContext?.findRenderObject();\n  if (renderObject is! RenderBox || !renderObject.hasSize) return;\n  final anchorRect = renderObject.localToGlobal(Offset.zero) & renderObject.size;\n\n""",
        "",
        'popover/remove global key lookup',
    )
    text = replace_once(
        text,
        """    pageBuilder: (dialogContext, _, __) => _ComposerReasoningPopover(\n      anchorRect: anchorRect,\n""",
        """    pageBuilder: (dialogContext, _, __) => _ComposerReasoningPopover(\n      anchorLink: anchorLink,\n      anchorRect: anchorRect,\n""",
        'popover/pass layer link',
    )
    old_transition = """      return FadeTransition(\n        opacity: curved,\n        child: ScaleTransition(\n          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),\n          alignment: Alignment.bottomCenter,\n          child: child,\n        ),\n      );\n"""
    text = replace_once(
        text,
        old_transition,
        """      return FadeTransition(opacity: curved, child: child);\n""",
        'popover/local fade transition',
    )
    text = replace_once(
        text,
        """  const _ComposerReasoningPopover({\n    required this.anchorRect,\n""",
        """  const _ComposerReasoningPopover({\n    required this.anchorLink,\n    required this.anchorRect,\n""",
        'popover/private ctor link',
    )
    text = replace_once(
        text,
        """  final Rect anchorRect;\n  final int? currentBudget;\n""",
        """  final LayerLink anchorLink;\n  final Rect anchorRect;\n  final int? currentBudget;\n""",
        'popover/private link field',
    )

    old_position = """    final left = (widget.anchorRect.center.dx - totalWidth / 2)\n        .clamp(\n          12.0,\n          math.max(12.0, size.width - totalWidth - 12),\n        )\n        .toDouble();\n    final bottom = math.max(12.0, size.height - widget.anchorRect.top + 8);\n\n"""
    new_position = """    final horizontalOffset = size.width - 12 - widget.anchorRect.right;\n\n"""
    text = replace_once(
        text,
        old_position,
        new_position,
        'popover/follower offset',
    )

    old_panel = """          Positioned(\n            left: left,\n            bottom: bottom,\n            width: totalWidth,\n            child: ConstrainedBox(\n              constraints: BoxConstraints(maxHeight: maxHeight),\n              child: _advanced ? _buildAdvanced(context) : _buildPrimary(context),\n            ),\n          ),\n"""
    new_panel = """          CompositedTransformFollower(\n            link: widget.anchorLink,\n            showWhenUnlinked: false,\n            targetAnchor: Alignment.topRight,\n            followerAnchor: Alignment.bottomRight,\n            offset: Offset(horizontalOffset, -8),\n            child: SizedBox(\n              width: totalWidth,\n              child: ConstrainedBox(\n                constraints: BoxConstraints(maxHeight: maxHeight),\n                child: _advanced\n                    ? _buildAdvanced(context)\n                    : _buildPrimary(context),\n              ),\n            ),\n          ),\n"""
    text = replace_once(
        text,
        old_panel,
        new_panel,
        'popover/use composited follower',
    )

    path.write_text(text, encoding='utf-8')


def patch_chat_input_bar() -> None:
    path = Path('lib/features/home/widgets/chat_input_bar.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """  final GlobalKey _reasoningAnchorKey = GlobalKey(\n    debugLabel: 'composer-reasoning-anchor',\n  );\n""",
        "",
        'chat_input_bar/remove persistent anchor key',
    )

    start_marker = """  Future<void> _openComposerReasoning() async {\n"""
    end_marker = """  Future<void> _openFullscreenEditor() async {\n"""
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit('chat_input_bar/reasoning method start missing')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit('chat_input_bar/reasoning method end missing')
    method = """  Future<void> _openComposerReasoning({\n    required GlobalKey anchorKey,\n    required LayerLink anchorLink,\n  }) async {\n    if (_composerLocked || _ownsVoiceSession || widget.loading) return;\n    if (!widget.supportsReasoning) {\n      widget.onSelectModel?.call();\n      return;\n    }\n    final onBudgetChanged = widget.onReasoningBudgetChanged;\n    if (onBudgetChanged == null) {\n      widget.onConfigureReasoning?.call();\n      return;\n    }\n    final renderObject = anchorKey.currentContext?.findRenderObject();\n    if (renderObject is! RenderBox || !renderObject.hasSize) {\n      widget.onConfigureReasoning?.call();\n      return;\n    }\n    final anchorRect =\n        renderObject.localToGlobal(Offset.zero) & renderObject.size;\n    final settings = context.read<SettingsProvider>();\n    await showComposerReasoningPopover(\n      context,\n      anchorLink: anchorLink,\n      anchorRect: anchorRect,\n      currentBudget: widget.reasoningBudget,\n      supportsXhigh: widget.supportsXhighReasoning,\n      supportsMax: widget.supportsMaxReasoning,\n      currentProviderKey: widget.currentModelProvider,\n      currentModelId: widget.currentModelId,\n      modelOptions: buildComposerModelOptions(settings),\n      onBudgetChanged: onBudgetChanged,\n      onModelChanged: widget.onComposerModelChanged,\n    );\n  }\n\n"""
    text = text[:start] + method + text[end:]

    text = replace_once(
        text,
        """      case ComposerFullscreenAction.reasoning:\n        await _openComposerReasoning();\n        break;\n""",
        """      case ComposerFullscreenAction.reasoning:\n        widget.onConfigureReasoning?.call();\n        break;\n""",
        'chat_input_bar/fullscreen fallback',
    )

    old_anchor = """                                              Container(\n                                                key: _reasoningAnchorKey,\n                                                child: _CompactIconButton(\n                                                  tooltip:\n                                                      widget.supportsReasoning\n                                                      ? AppLocalizations.of(\n                                                          context,\n                                                        )!.chatInputBarReasoningStrengthTooltip\n                                                      : AppLocalizations.of(\n                                                          context,\n                                                        )!.chatInputBarSelectModelTooltip,\n                                                  icon: widget.supportsReasoning\n                                                      ? Lucide.Brain\n                                                      : Lucide.Boxes,\n                                                  active:\n                                                      widget.supportsReasoning &&\n                                                      widget.reasoningActive,\n                                                  onTap: _composerLocked\n                                                      ? null\n                                                      : () => unawaited(\n                                                          _openComposerReasoning(),\n                                                        ),\n                                                  onLongPress: _composerLocked\n                                                      ? null\n                                                      : widget.onSelectModel,\n                                                  childBuilder:\n                                                      widget.supportsReasoning\n                                                      ? (\n                                                          color,\n                                                        ) => ReasoningIcons.budgetIcon(\n                                                          widget.reasoningBudget,\n                                                          size: 20,\n                                                          color: color,\n                                                        )\n                                                      : null,\n                                                ),\n                                              ),\n"""
    new_anchor = """                                              Builder(\n                                                builder: (_) {\n                                                  final anchorKey = GlobalKey(\n                                                    debugLabel:\n                                                        'composer-reasoning-anchor',\n                                                  );\n                                                  final anchorLink = LayerLink();\n                                                  return CompositedTransformTarget(\n                                                    link: anchorLink,\n                                                    child: Container(\n                                                      key: anchorKey,\n                                                      child: _CompactIconButton(\n                                                        tooltip:\n                                                            widget.supportsReasoning\n                                                            ? AppLocalizations.of(\n                                                                context,\n                                                              )!.chatInputBarReasoningStrengthTooltip\n                                                            : AppLocalizations.of(\n                                                                context,\n                                                              )!.chatInputBarSelectModelTooltip,\n                                                        icon:\n                                                            widget.supportsReasoning\n                                                            ? Lucide.Brain\n                                                            : Lucide.Boxes,\n                                                        active:\n                                                            widget.supportsReasoning &&\n                                                            widget.reasoningActive,\n                                                        onTap: _composerLocked\n                                                            ? null\n                                                            : () => unawaited(\n                                                                _openComposerReasoning(\n                                                                  anchorKey:\n                                                                      anchorKey,\n                                                                  anchorLink:\n                                                                      anchorLink,\n                                                                ),\n                                                              ),\n                                                        onLongPress:\n                                                            _composerLocked\n                                                            ? null\n                                                            : widget\n                                                                  .onSelectModel,\n                                                        childBuilder:\n                                                            widget.supportsReasoning\n                                                            ? (\n                                                                color,\n                                                              ) => ReasoningIcons.budgetIcon(\n                                                                widget\n                                                                    .reasoningBudget,\n                                                                size: 20,\n                                                                color: color,\n                                                              )\n                                                            : null,\n                                                      ),\n                                                    ),\n                                                  );\n                                                },\n                                              ),\n"""
    text = replace_once(
        text,
        old_anchor,
        new_anchor,
        'chat_input_bar/local layer-link anchor',
    )

    path.write_text(text, encoding='utf-8')


patch_popover()
patch_chat_input_bar()
print('Composer phase 2 reasoning anchor lifecycle fix applied successfully')
