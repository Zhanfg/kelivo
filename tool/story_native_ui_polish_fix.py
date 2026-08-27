from pathlib import Path

p = Path('tool/story_native_ui_polish.py')
s = p.read_text()
replacements = {
    'pattern.subn(studio_build + "\\n  @override\\n  void dispose()", s, count=1)':
        'pattern.subn(lambda _: studio_build + "\\n  @override\\n  void dispose()", s, count=1)',
    'profile_pattern.subn(profile_method, s, count=1)':
        'profile_pattern.subn(lambda _: profile_method, s, count=1)',
    'skill_pattern.subn(skill_build + "\\n  Widget _skillCard(", m, count=1)':
        'skill_pattern.subn(lambda _: skill_build + "\\n  Widget _skillCard(", m, count=1)',
    'skill_card_pattern.subn(new_skill_card, m, count=1)':
        'skill_card_pattern.subn(lambda _: new_skill_card, m, count=1)',
}
for old, new in replacements.items():
    if old not in s:
        raise SystemExit(f'missing patch target: {old}')
    s = s.replace(old, new, 1)
s = s.replace('Lucide.GitBranch', 'Lucide.GitFork')
p.write_text(s)
