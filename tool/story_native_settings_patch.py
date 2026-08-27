from pathlib import Path
import re

settings = Path('lib/features/settings/pages/settings_page.dart')
settings.write_text("export 'settings_core_page.dart' show SettingsPage;\n")

core = Path('lib/features/settings/pages/settings_core_page.dart')
s = core.read_text()
import_anchor = "import '../../world_book/pages/world_book_page.dart';\n"
story_imports = (
    "import '../../story_runtime/ui/story_skill_manager_page.dart';\n"
    "import '../../story_runtime/ui/story_studio_page.dart';\n"
)
if story_imports not in s:
    if import_anchor not in s:
        raise SystemExit('settings core import anchor not found')
    s = s.replace(import_anchor, import_anchor + story_imports, 1)

label_anchor = "    final settings = context.watch<SettingsProvider>();\n"
labels = (
    "    final languageCode = Localizations.localeOf(context).languageCode;\n"
    "    final storyModeLabel = languageCode == 'zh' ? '故事模式' : 'Story Mode';\n"
    "    final storySkillsLabel = languageCode == 'zh' ? '故事技能' : 'Story Skills';\n"
)
if 'final storyModeLabel =' not in s:
    if label_anchor not in s:
        raise SystemExit('settings core label anchor not found')
    s = s.replace(label_anchor, label_anchor + labels, 1)

marker = """              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Zap,
"""
story_rows = """              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.BookOpen,
                label: storyModeLabel,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StoryStudioPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Layers,
                label: storySkillsLabel,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StorySkillManagerPage(),
                    ),
                  );
                },
              ),
"""
if 'label: storyModeLabel' not in s:
    if marker not in s:
        raise SystemExit('settings core insertion marker not found')
    s = s.replace(marker, story_rows + marker, 1)
core.write_text(s)

more = Path('lib/features/settings/pages/more_page.dart')
m = more.read_text()
m = m.replace("import '../../story_runtime/ui/story_runtime_control_page.dart';\n", '')
m = m.replace("import '../../story_runtime/ui/story_skill_manager_page.dart';\n", '')
m = m.replace("import '../../story_runtime/ui/story_studio_page.dart';\n", '')
m2, count = re.subn(
    r"\s*title\('Story'\),\n\s*Card\(.*?\n\s*// LeaderBoard section",
    "\n              // LeaderBoard section",
    m,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f'MorePage Story block removal matched {count} times')
more.write_text(m2)
