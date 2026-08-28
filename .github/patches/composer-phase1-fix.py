from pathlib import Path

path = Path('lib/features/home/widgets/chat_input_bar.dart')
text = path.read_text(encoding='utf-8')

import_marker = "import 'package:Kelivo/theme/app_font_weights.dart';\n"
import_line = "import '../composer/composer_fullscreen_editor.dart';\n"
if import_line not in text:
    if text.count(import_marker) != 1:
        raise SystemExit('fullscreen editor import marker did not match exactly once')
    text = text.replace(import_marker, import_marker + import_line, 1)

start_marker = "  Future<void> _openFullscreenEditor() async {\n"
end_marker = "  // ---------------------------------------------------------------------------\n  // Voice input\n"
start = text.find(start_marker)
if start < 0:
    raise SystemExit('fullscreen editor method start not found')
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit('fullscreen editor method end not found')

method = """  Future<void> _openFullscreenEditor() async {\n    if (_composerLocked || _ownsVoiceSession) return;\n    final settings = context.read<SettingsProvider>();\n    final selectedAsrService = settings.selectedAsrService;\n    final asr = widget.asrProvider;\n    final canUseVoice =\n        asr != null &&\n        selectedAsrService != null &&\n        asr.canUse(selectedAsrService) &&\n        !widget.loading;\n\n    final action = await showDialog<ComposerFullscreenAction>(\n      context: context,\n      useSafeArea: false,\n      builder: (_) => ComposerFullscreenEditor(\n        initialValue: _controller.value,\n        onDraftChanged: (value) {\n          if (!mounted) return;\n          _controller.value = value;\n        },\n        supportsReasoning: widget.supportsReasoning,\n        reasoningBudget: widget.reasoningBudget,\n        hasDraftMedia: _hasDraftMedia,\n        canOpenMore: widget.onMore != null,\n        canUseVoice: canUseVoice,\n      ),\n    );\n    if (!mounted) return;\n\n    switch (action) {\n      case ComposerFullscreenAction.more:\n        widget.onMore?.call();\n        break;\n      case ComposerFullscreenAction.reasoning:\n        widget.onConfigureReasoning?.call();\n        break;\n      case ComposerFullscreenAction.model:\n        widget.onSelectModel?.call();\n        break;\n      case ComposerFullscreenAction.voice:\n        await _startVoiceInput();\n        break;\n      case ComposerFullscreenAction.send:\n        await _handleSend();\n        break;\n      case null:\n        break;\n    }\n  }\n\n"""

text = text[:start] + method + text[end:]
path.write_text(text, encoding='utf-8')
print('Composer phase 1 fullscreen ownership fix applied successfully')
