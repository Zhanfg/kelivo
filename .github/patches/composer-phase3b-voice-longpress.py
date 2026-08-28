from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)

path = Path('lib/features/home/widgets/chat_input_bar.dart')
text = path.read_text(encoding='utf-8')

text = replace_once(
    text,
    """  final VoidCallback? onLongPress;\n  final String? tooltip;\n""",
    """  final VoidCallback? onLongPress;\n  final bool allowLongPressOnDesktop;\n  final String? tooltip;\n""",
    'compact-button/long press field',
)

text = replace_once(
    text,
    """    this.onLongPress,\n    this.tooltip,\n""",
    """    this.onLongPress,\n    this.allowLongPressOnDesktop = false,\n    this.tooltip,\n""",
    'compact-button/long press ctor',
)

text = replace_once(
    text,
    """      // Disable long press on desktop platforms\n      onLongPress: isDesktop ? null : onLongPress,\n""",
    """      // Model/reasoning long-press stays disabled on desktop, while\n      // controls that explicitly opt in can use long-press in a mobile-width\n      // Composer even when widget tests run on a desktop host.\n      onLongPress: isDesktop && !allowLongPressOnDesktop ? null : onLongPress,\n""",
    'compact-button/long press behavior',
)

text = replace_once(
    text,
    """                                                onLongPress:\n                                                    _composerLocked ||\n                                                        widget.loading\n                                                    ? null\n                                                    : _toggleInlineVoiceSettings,\n""",
    """                                                onLongPress:\n                                                    _composerLocked ||\n                                                        widget.loading\n                                                    ? null\n                                                    : _toggleInlineVoiceSettings,\n                                                allowLongPressOnDesktop:\n                                                    isMobileLayout,\n""",
    'mic/mobile layout opt in',
)

path.write_text(text, encoding='utf-8')
print('Composer phase 3b mobile-layout voice long press applied successfully')
