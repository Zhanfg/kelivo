from pathlib import Path

path = Path('lib/features/home/widgets/chat_input_bar.dart')
text = path.read_text(encoding='utf-8')
old = "import '../../../core/providers/asr_provider.dart';\n"
new = (
    "import '../../../core/providers/asr_provider.dart';\n"
    "import '../../../core/services/asr/asr_service_options.dart';\n"
)
count = text.count(old)
if count != 1:
    raise SystemExit(f'voice-settings/asr options import: expected exactly one match, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Composer phase 3b ASR option import applied successfully')
