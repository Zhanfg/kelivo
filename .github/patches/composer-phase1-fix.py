from pathlib import Path

path = Path('lib/features/home/widgets/chat_input_bar.dart')
text = path.read_text(encoding='utf-8')

old = """    switch (requestedAction) {\n      case 'more':\n        widget.onMore?.call();\n      case 'reasoning':\n        widget.onConfigureReasoning?.call();\n      case 'model':\n        widget.onSelectModel?.call();\n      case 'voice':\n        await _startVoiceInput();\n      case 'send':\n        await _handleSend();\n    }\n"""
new = """    switch (requestedAction) {\n      case 'more':\n        widget.onMore?.call();\n        break;\n      case 'reasoning':\n        widget.onConfigureReasoning?.call();\n        break;\n      case 'model':\n        widget.onSelectModel?.call();\n        break;\n      case 'voice':\n        await _startVoiceInput();\n        break;\n      case 'send':\n        await _handleSend();\n        break;\n      default:\n        break;\n    }\n"""
if text.count(old) != 1:
    raise SystemExit('fullscreen action switch: expected one match')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Composer phase 1 follow-up transform applied successfully')
