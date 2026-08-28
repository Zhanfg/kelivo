from pathlib import Path
import runpy

path = Path('.github/patches/composer-v8-phase1-generation.py')
text = path.read_text(encoding='utf-8')
old = "end = text.index('\\nclass _QueueManagerSheet', start)"
new = "end = text.index('\\nclass _QueuedInputManager', start)"
count = text.count(old)
if count != 1:
    raise SystemExit(f'queue manager boundary fix: expected one match, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
runpy.run_path(str(path), run_name='__main__')
