from pathlib import Path
import runpy

path = Path('.github/patches/composer-v8-phase1-generation.py')
text = path.read_text(encoding='utf-8')

replacements = [
    (
        "end = text.index('\\nclass _QueueManagerSheet', start)",
        "end = text.index('\\nclass _QueuedInputManager', start)",
        'queue manager boundary',
    ),
    (
        "    if (cid == null || !_chatController.isConversationLoading(cid)) return false;\\n",
        "    if (cid == null || !_chatController.isConversationLoading(cid)) {\\n      return false;\\n    }\\n",
        'pause guard braces',
    ),
]

for old, new, label in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
runpy.run_path(str(path), run_name='__main__')
