from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def patch_chat_input_bar() -> None:
    path = Path('lib/features/home/widgets/chat_input_bar.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        "import '../composer/composer_fullscreen_editor.dart';\n",
        "import '../composer/composer_fullscreen_editor.dart';\nimport '../composer/composer_reasoning_popover.dart';\n",
        'chat_input_bar/import',
    )
    text = replace_once(
        text,
        """    this.onMore,\n    this.onConfigureReasoning,\n    this.moreOpen = false,\n""",
        """    this.onMore,\n    this.onConfigureReasoning,\n    this.onReasoningBudgetChanged,\n    this.onComposerModelChanged,\n    this.currentModelProvider,\n    this.currentModelId,\n    this.supportsXhighReasoning = false,\n    this.supportsMaxReasoning = false,\n    this.moreOpen = false,\n""",
        'chat_input_bar/constructor',
    )
    text = replace_once(
        text,
        """  final VoidCallback? onMore;\n  final VoidCallback? onConfigureReasoning;\n  final bool moreOpen;\n""",
        """  final VoidCallback? onMore;\n  final VoidCallback? onConfigureReasoning;\n  final ComposerReasoningBudgetChanged? onReasoningBudgetChanged;\n  final ComposerModelChanged? onComposerModelChanged;\n  final String? currentModelProvider;\n  final String? currentModelId;\n  final bool supportsXhighReasoning;\n  final bool supportsMaxReasoning;\n  final bool moreOpen;\n""",
        'chat_input_bar/fields',
    )
    text = replace_once(
        text,
        """  final GlobalKey _contextMgmtAnchorKey = GlobalKey(\n    debugLabel: 'context-mgmt-anchor',\n  );\n""",
        """  final GlobalKey _contextMgmtAnchorKey = GlobalKey(\n    debugLabel: 'context-mgmt-anchor',\n  );\n  final GlobalKey _reasoningAnchorKey = GlobalKey(\n    debugLabel: 'composer-reasoning-anchor',\n  );\n""",
        'chat_input_bar/reasoning anchor',
    )

    method_marker = """  Future<void> _openFullscreenEditor() async {\n"""
    method = """  Future<void> _openComposerReasoning() async {\n    if (_composerLocked || _ownsVoiceSession || widget.loading) return;\n    if (!widget.supportsReasoning) {\n      widget.onSelectModel?.call();\n      return;\n    }\n    final onBudgetChanged = widget.onReasoningBudgetChanged;\n    if (onBudgetChanged == null) {\n      widget.onConfigureReasoning?.call();\n      return;\n    }\n    final settings = context.read<SettingsProvider>();\n    await showComposerReasoningPopover(\n      context,\n      anchorKey: _reasoningAnchorKey,\n      currentBudget: widget.reasoningBudget,\n      supportsXhigh: widget.supportsXhighReasoning,\n      supportsMax: widget.supportsMaxReasoning,\n      currentProviderKey: widget.currentModelProvider,\n      currentModelId: widget.currentModelId,\n      modelOptions: buildComposerModelOptions(settings),\n      onBudgetChanged: onBudgetChanged,\n      onModelChanged: widget.onComposerModelChanged,\n    );\n  }\n\n"""
    if text.count(method_marker) != 1:
        raise SystemExit('chat_input_bar/fullscreen marker missing')
    text = text.replace(method_marker, method + method_marker, 1)

    text = replace_once(
        text,
        """      case ComposerFullscreenAction.reasoning:\n        widget.onConfigureReasoning?.call();\n        break;\n""",
        """      case ComposerFullscreenAction.reasoning:\n        await _openComposerReasoning();\n        break;\n""",
        'chat_input_bar/fullscreen reasoning action',
    )

    old_mobile = """                                            if (isMobileLayout) ...[\n                                              _CompactIconButton(\n                                                tooltip:\n                                                    widget.supportsReasoning\n                                                    ? AppLocalizations.of(\n                                                        context,\n                                                      )!.chatInputBarReasoningStrengthTooltip\n                                                    : AppLocalizations.of(\n                                                        context,\n                                                      )!.chatInputBarSelectModelTooltip,\n                                                icon: widget.supportsReasoning\n                                                    ? Lucide.Brain\n                                                    : Lucide.Boxes,\n                                                active:\n                                                    widget.supportsReasoning &&\n                                                    widget.reasoningActive,\n                                                onTap: _composerLocked\n                                                    ? null\n                                                    : (widget.supportsReasoning\n                                                          ? widget\n                                                                .onConfigureReasoning\n                                                          : widget\n                                                                .onSelectModel),\n                                                onLongPress: _composerLocked\n                                                    ? null\n                                                    : widget.onSelectModel,\n                                                childBuilder:\n                                                    widget.supportsReasoning\n                                                    ? (\n                                                        color,\n                                                      ) => ReasoningIcons.budgetIcon(\n                                                        widget.reasoningBudget,\n                                                        size: 20,\n                                                        color: color,\n                                                      )\n                                                    : null,\n                                              ),\n                                              const SizedBox(width: 8),\n                                            ],\n"""
    new_mobile = """                                            if (isMobileLayout) ...[\n                                              Container(\n                                                key: _reasoningAnchorKey,\n                                                child: _CompactIconButton(\n                                                  tooltip:\n                                                      widget.supportsReasoning\n                                                      ? AppLocalizations.of(\n                                                          context,\n                                                        )!.chatInputBarReasoningStrengthTooltip\n                                                      : AppLocalizations.of(\n                                                          context,\n                                                        )!.chatInputBarSelectModelTooltip,\n                                                  icon: widget.supportsReasoning\n                                                      ? Lucide.Brain\n                                                      : Lucide.Boxes,\n                                                  active:\n                                                      widget.supportsReasoning &&\n                                                      widget.reasoningActive,\n                                                  onTap: _composerLocked\n                                                      ? null\n                                                      : () => unawaited(\n                                                          _openComposerReasoning(),\n                                                        ),\n                                                  onLongPress: _composerLocked\n                                                      ? null\n                                                      : widget.onSelectModel,\n                                                  childBuilder:\n                                                      widget.supportsReasoning\n                                                      ? (\n                                                          color,\n                                                        ) => ReasoningIcons.budgetIcon(\n                                                          widget.reasoningBudget,\n                                                          size: 20,\n                                                          color: color,\n                                                        )\n                                                      : null,\n                                                ),\n                                              ),\n                                              const SizedBox(width: 8),\n                                            ],\n"""
    text = replace_once(
        text,
        old_mobile,
        new_mobile,
        'chat_input_bar/mobile reasoning control',
    )

    path.write_text(text, encoding='utf-8')


def patch_chat_input_section() -> None:
    path = Path('lib/features/home/widgets/chat_input_section.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """    this.onOpenSearch,\n    this.onConfigureReasoning,\n    this.onSend,\n""",
        """    this.onOpenSearch,\n    this.onConfigureReasoning,\n    this.onReasoningBudgetChanged,\n    this.onComposerModelChanged,\n    this.onSend,\n""",
        'chat_input_section/constructor',
    )
    text = replace_once(
        text,
        """  final VoidCallback? onOpenSearch;\n  final VoidCallback? onConfigureReasoning;\n  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;\n""",
        """  final VoidCallback? onOpenSearch;\n  final VoidCallback? onConfigureReasoning;\n  final Future<void> Function(int budget)? onReasoningBudgetChanged;\n  final Future<void> Function(String providerKey, String modelId)?\n  onComposerModelChanged;\n  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;\n""",
        'chat_input_section/fields',
    )
    text = replace_once(
        text,
        """          onConfigureReasoning: onConfigureReasoning,\n          reasoningActive: isReasoningEnabled(\n""",
        """          onConfigureReasoning: onConfigureReasoning,\n          onReasoningBudgetChanged: onReasoningBudgetChanged,\n          onComposerModelChanged: onComposerModelChanged,\n          currentModelProvider: pk,\n          currentModelId: mid,\n          supportsXhighReasoning: pk != null && mid != null\n              ? settings.supportsXhighReasoning(pk, mid)\n              : false,\n          supportsMaxReasoning: pk != null && mid != null\n              ? settings.supportsMaxReasoning(pk, mid)\n              : false,\n          reasoningActive: isReasoningEnabled(\n""",
        'chat_input_section/pass reasoning data',
    )

    path.write_text(text, encoding='utf-8')


def patch_home_page() -> None:
    path = Path('lib/features/home/pages/home_page.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """      onConfigureReasoning: () async {\n        final assistantProvider = context.read<AssistantProvider>();\n        final settingsProvider = context.read<SettingsProvider>();\n        final assistant = assistantProvider.currentAssistant;\n        if (assistant != null) {\n          if (assistant.thinkingBudget != null) {\n            settingsProvider.setThinkingBudget(assistant.thinkingBudget);\n          }\n          await _openReasoningSettings();\n          if (!mounted) return;\n          final chosen = settingsProvider.thinkingBudget;\n          await assistantProvider.updateAssistant(\n            assistant.copyWith(thinkingBudget: chosen),\n          );\n        }\n      },\n      onSend: (text) async {\n""",
        """      onConfigureReasoning: () async {\n        final assistantProvider = context.read<AssistantProvider>();\n        final settingsProvider = context.read<SettingsProvider>();\n        final assistant = assistantProvider.currentAssistant;\n        if (assistant != null) {\n          if (assistant.thinkingBudget != null) {\n            settingsProvider.setThinkingBudget(assistant.thinkingBudget);\n          }\n          await _openReasoningSettings();\n          if (!mounted) return;\n          final chosen = settingsProvider.thinkingBudget;\n          await assistantProvider.updateAssistant(\n            assistant.copyWith(thinkingBudget: chosen),\n          );\n        }\n      },\n      onReasoningBudgetChanged: _setComposerReasoningBudget,\n      onComposerModelChanged: _setComposerModel,\n      onSend: (text) async {\n""",
        'home_page/pass composer callbacks',
    )

    marker = """  Future<void> _openReasoningSettings() async {\n"""
    methods = """  Future<void> _setComposerReasoningBudget(int budget) async {\n    final settings = context.read<SettingsProvider>();\n    await settings.setThinkingBudget(budget);\n    if (!mounted) return;\n    final assistantProvider = context.read<AssistantProvider>();\n    final assistant = assistantProvider.currentAssistant;\n    if (assistant != null && assistant.thinkingBudget != budget) {\n      await assistantProvider.updateAssistant(\n        assistant.copyWith(thinkingBudget: budget),\n      );\n    }\n  }\n\n  Future<void> _setComposerModel(\n    String providerKey,\n    String modelId,\n  ) async {\n    final assistantProvider = context.read<AssistantProvider>();\n    final assistant = assistantProvider.currentAssistant;\n    if (assistant != null) {\n      await assistantProvider.updateAssistant(\n        assistant.copyWith(\n          chatModelProvider: providerKey,\n          chatModelId: modelId,\n        ),\n      );\n      return;\n    }\n    await context.read<SettingsProvider>().setCurrentModel(providerKey, modelId);\n  }\n\n"""
    if text.count(marker) != 1:
        raise SystemExit('home_page/reasoning settings marker missing')
    text = text.replace(marker, methods + marker, 1)
    path.write_text(text, encoding='utf-8')


def patch_mobile_test() -> None:
    path = Path('test/features/home/widgets/chat_input_bar_mobile_composer_test.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """    required AsrProvider asr,\n    required TextEditingController controller,\n  }) {\n""",
        """    required AsrProvider asr,\n    required TextEditingController controller,\n    Future<void> Function(int budget)? onReasoningBudgetChanged,\n  }) {\n""",
        'mobile_test/harness callback',
    )
    text = replace_once(
        text,
        """            onConfigureReasoning: () {},\n            onSelectModel: () {},\n            reasoningBudget: -1,\n            supportsReasoning: true,\n""",
        """            onConfigureReasoning: () {},\n            onReasoningBudgetChanged:\n                onReasoningBudgetChanged ?? (_) async {},\n            onSelectModel: () {},\n            reasoningBudget: -1,\n            supportsReasoning: true,\n            currentModelProvider: 'ProviderA',\n            currentModelId: 'model-a',\n            supportsXhighReasoning: true,\n            supportsMaxReasoning: false,\n""",
        'mobile_test/harness reasoning props',
    )

    insert_before = """  testWidgets('six visual lines expose fullscreen editing and preserve draft', (\n"""
    test_block = """  testWidgets('mobile reasoning button opens the anchored local popover', (\n    tester,\n  ) async {\n    tester.view.physicalSize = const Size(390, 844);\n    tester.view.devicePixelRatio = 1;\n    addTearDown(tester.view.resetPhysicalSize);\n    addTearDown(tester.view.resetDevicePixelRatio);\n\n    final p = await providers();\n    final controller = TextEditingController();\n    addTearDown(controller.dispose);\n    addTearDown(p.asr.dispose);\n    int? chosenBudget;\n\n    await tester.pumpWidget(\n      harness(\n        settings: p.settings,\n        asr: p.asr,\n        controller: controller,\n        onReasoningBudgetChanged: (budget) async {\n          chosenBudget = budget;\n        },\n      ),\n    );\n    await tester.pump();\n\n    final context = tester.element(find.byType(ChatInputBar));\n    final l10n = AppLocalizations.of(context)!;\n    await tester.tap(\n      find.byTooltip(l10n.chatInputBarReasoningStrengthTooltip),\n    );\n    await tester.pumpAndSettle();\n\n    expect(\n      find.byKey(const ValueKey('composer-reasoning-slider')),\n      findsOneWidget,\n    );\n    expect(find.text(l10n.modelDetailSheetAdvancedTab), findsOneWidget);\n    expect(find.textContaining('Speed'), findsNothing);\n    expect(chosenBudget, isNull);\n  });\n\n"""
    if text.count(insert_before) != 1:
        raise SystemExit('mobile_test/insert marker missing')
    text = text.replace(insert_before, test_block + insert_before, 1)
    path.write_text(text, encoding='utf-8')


patch_chat_input_bar()
patch_chat_input_section()
patch_home_page()
patch_mobile_test()
print('Composer phase 2 reasoning integration applied successfully')
