from pathlib import Path


def patch_bottom_tools() -> None:
    path = Path('lib/features/chat/widgets/bottom_tools_sheet.dart')
    text = path.read_text(encoding='utf-8')

    def replace_once(old: str, new: str, label: str) -> None:
        nonlocal text
        count = text.count(old)
        if count != 1:
            raise SystemExit(f'bottom_tools/{label}: expected one match, found {count}')
        text = text.replace(old, new, 1)

    replace_once(
        """    this.onUpload,\n    this.onClear,\n    this.clearLabel,\n    this.assistantId,\n""",
        """    this.onUpload,\n    this.onSearch,\n    this.onMcp,\n    this.onQuickPhrase,\n    this.onManageQuickPhrases,\n    this.onClear,\n    this.clearLabel,\n    this.assistantId,\n""",
        'constructor callbacks',
    )
    replace_once(
        """  final VoidCallback? onUpload;\n  final VoidCallback? onClear;\n""",
        """  final VoidCallback? onUpload;\n  final VoidCallback? onSearch;\n  final VoidCallback? onMcp;\n  final VoidCallback? onQuickPhrase;\n  final VoidCallback? onManageQuickPhrases;\n  final VoidCallback? onClear;\n""",
        'callback fields',
    )

    marker = """    Widget roundedAction({\n      required IconData icon,\n      required String label,\n      VoidCallback? onTap,\n    }) {\n"""
    if text.count(marker) != 1:
        raise SystemExit('bottom_tools/roundedAction marker did not match once')
    helper = """    Widget secondaryAction({\n      required IconData icon,\n      required String label,\n      VoidCallback? onTap,\n      VoidCallback? onLongPress,\n    }) {\n      final cs = Theme.of(context).colorScheme;\n      return SizedBox(\n        height: 48,\n        child: IosCardPress(\n          borderRadius: BorderRadius.circular(14),\n          baseColor: cs.surface,\n          duration: const Duration(milliseconds: 220),\n          onTap: onTap,\n          onLongPress: onLongPress,\n          padding: const EdgeInsets.symmetric(horizontal: 12),\n          child: Row(\n            children: [\n              Icon(icon, size: 20, color: cs.onSurface),\n              const SizedBox(width: 10),\n              Expanded(\n                child: Text(\n                  label,\n                  style: TextStyle(\n                    fontSize: 15,\n                    fontWeight: AppFontWeights.medium,\n                    color: cs.onSurface,\n                  ),\n                ),\n              ),\n              Icon(\n                Lucide.ChevronRight,\n                size: 18,\n                color: cs.onSurface.withValues(alpha: 0.55),\n              ),\n            ],\n          ),\n        ),\n      );\n    }\n\n"""
    text = text.replace(marker, helper + marker, 1)

    replace_once(
        """                    const SizedBox(height: 12),\n                    _LearningAndClearSection(\n                      clearLabel: clearLabel,\n                      onClear: onClear,\n                      assistantId: assistantId,\n                    ),\n""",
        """                    if (onSearch != null ||\n                        onMcp != null ||\n                        onQuickPhrase != null) ...[\n                      const SizedBox(height: 8),\n                      if (onSearch != null)\n                        secondaryAction(\n                          icon: Lucide.Globe,\n                          label: l10n.chatInputBarOnlineSearchTooltip,\n                          onTap: onSearch,\n                        ),\n                      if (onMcp != null)\n                        secondaryAction(\n                          icon: Lucide.Hammer,\n                          label: l10n.chatInputBarMcpServersTooltip,\n                          onTap: onMcp,\n                        ),\n                      if (onQuickPhrase != null)\n                        secondaryAction(\n                          icon: Lucide.Zap,\n                          label: l10n.chatInputBarQuickPhraseTooltip,\n                          onTap: onQuickPhrase,\n                          onLongPress: onManageQuickPhrases,\n                        ),\n                    ],\n                    const SizedBox(height: 12),\n                    _LearningAndClearSection(\n                      clearLabel: clearLabel,\n                      onClear: onClear,\n                      assistantId: assistantId,\n                    ),\n""",
        'secondary low-frequency rows',
    )

    path.write_text(text, encoding='utf-8')


def patch_home_page() -> None:
    path = Path('lib/features/home/pages/home_page.dart')
    text = path.read_text(encoding='utf-8')

    old = """            onUpload: () {\n              Navigator.of(ctx).maybePop();\n              _controller.onPickFiles();\n            },\n            onClear: () async {\n"""
    new = """            onUpload: () {\n              Navigator.of(ctx).maybePop();\n              _controller.onPickFiles();\n            },\n            onSearch: () async {\n              await Navigator.of(ctx).maybePop();\n              if (!mounted) return;\n              _openSearchSettings();\n            },\n            onMcp: assistantId == null\n                ? null\n                : () async {\n                    await Navigator.of(ctx).maybePop();\n                    if (!mounted) return;\n                    final assistant =\n                        context.read<AssistantProvider>().currentAssistant;\n                    if (assistant != null) {\n                      showAssistantMcpSheet(\n                        context,\n                        assistantId: assistant.id,\n                      );\n                    }\n                  },\n            onQuickPhrase: () async {\n              await Navigator.of(ctx).maybePop();\n              if (!mounted) return;\n              await _showQuickPhraseMenu();\n            },\n            onManageQuickPhrases: () async {\n              await Navigator.of(ctx).maybePop();\n              if (!mounted) return;\n              await Navigator.of(context).push(\n                MaterialPageRoute(builder: (_) => const QuickPhrasesPage()),\n              );\n            },\n            onClear: () async {\n"""
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'home_page/tools callbacks: expected one match, found {count}')
    text = text.replace(old, new, 1)
    path.write_text(text, encoding='utf-8')


patch_bottom_tools()
patch_home_page()
print('Composer phase 1 secondary tool migration applied successfully')
