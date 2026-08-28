from pathlib import Path
import re


def patch_home_controller() -> None:
    path = Path('lib/features/home/controllers/home_page_controller.dart')
    text = path.read_text()

    import_line = (
        "import '../../story_runtime/orchestration/"
        "story_native_lifecycle_bridge.dart';"
    )
    playback_import = (
        "import '../../story_runtime/voice/"
        "story_voice_playback_service.dart';"
    )
    if playback_import not in text:
        if import_line not in text:
            raise RuntimeError('Story lifecycle import anchor missing')
        text = text.replace(import_line, import_line + '\n' + playback_import, 1)

    old = "\n".join(
        [
            '    final selectedService = sp.selectedTtsService;',
            '    if (selectedService != null && selectedService.enabled) {',
            '      var routedService = selectedService;',
            '      try {',
            '        final preferences = _context.read<BusinessPreferences>();',
            '        routedService = await StoryNativeLifecycleBridge(',
            '          preferences,',
            '        ).routeNarrator(message: message, selectedService: selectedService);',
            '      } catch (error) {',
            "        debugPrint('Story narrator routing failed: $error');",
            '      }',
            '      await tts.speakWithNetworkService(routedService, text);',
            '      return;',
            '    }',
            '',
            '    await tts.speak(text);',
        ]
    )
    new = "\n".join(
        [
            '    try {',
            '      final preferences = _context.read<BusinessPreferences>();',
            '      final bridge = StoryNativeLifecycleBridge(preferences);',
            '      final narrator = await bridge.resolveNarratorAssignment(message);',
            '      if (narrator != null) {',
            '        final voiceContext = await bridge.resolveNarratorContext(message);',
            '        await StoryVoicePlaybackService(',
            '          preferences: preferences,',
            '          ttsProvider: tts,',
            '        ).speakAssignment(',
            '          assignment: narrator,',
            '          text: text,',
            '          context: voiceContext,',
            '        );',
            '        return;',
            '      }',
            '    } catch (error) {',
            "      debugPrint('Story narrator playback failed: $error');",
            '    }',
            '',
            '    final selectedService = sp.selectedTtsService;',
            '    if (selectedService != null && selectedService.enabled) {',
            '      await tts.speakWithNetworkService(selectedService, text);',
            '      return;',
            '    }',
            '',
            '    await tts.speak(text);',
        ]
    )
    if old in text:
        text = text.replace(old, new, 1)
    elif 'Story narrator playback failed:' not in text:
        raise RuntimeError('TTS playback replacement anchor missing')

    path.write_text(text)


def patch_skill_discovery() -> None:
    path = Path(
        'lib/features/story_runtime/skills/story_skill_github_source.dart'
    )
    text = path.read_text()

    call_old = '_selectSkillRoot(relative, source.subdirectory)'
    call_new = "\n".join(
        [
            '_selectSkillRoot(',
            '      relative,',
            '      source.subdirectory,',
            '      repository: source.repository,',
            '    )',
        ]
    )
    if call_old in text:
        text = text.replace(call_old, call_new, 1)

    old_signature = "\n".join(
        [
            'String _selectSkillRoot(',
            '  Map<String, ArchiveFile> entries,',
            '  String? requestedSubdirectory,',
            ') {',
        ]
    )
    if old_signature in text:
        pattern = re.compile(
            r'String _selectSkillRoot\(\n.*?\n\}\n\n'
            r'Map<String, String> _parseFrontmatter',
            re.S,
        )
        replacement = "\n".join(
            [
                'String _selectSkillRoot(',
                '  Map<String, ArchiveFile> entries,',
                '  String? requestedSubdirectory, {',
                '  required String repository,',
                '}) {',
                '  final requested = _normalizeSubdirectory(requestedSubdirectory);',
                '  if (requested != null) {',
                "    final path = '$requested/SKILL.md';",
                '    final entry = entries[path];',
                '    if (entry != null && entry.isFile) return requested;',
                '    throw StorySkillGitHubException(',
                "      'skill_subdirectory_missing',",
                '      detail: requested,',
                '    );',
                '  }',
                "  if (entries.containsKey('SKILL.md')) return '';",
                '',
                '  final candidates = entries.keys',
                "      .where((path) => path.endsWith('/SKILL.md'))",
                "      .map((path) => path.substring(0, path.length - '/SKILL.md'.length))",
                '      .toList(growable: false);',
                '  if (candidates.isEmpty) {',
                "    throw const StorySkillGitHubException('skill_markdown_missing');",
                '  }',
                '',
                '  String slug(String value) => value',
                '      .toLowerCase()',
                "      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')",
                "      .replaceAll(RegExp(r'^-+|-+$'), '');",
                '  final repositorySlug = slug(repository);',
                '',
                '  int score(String candidate) {',
                "    final normalized = candidate.replaceAll('\\\\', '/');",
                "    final segments = normalized.split('/').where((item) => item.isNotEmpty).toList(growable: false);",
                '    final leaf = segments.isEmpty ? normalized : segments.last;',
                '    var value = segments.length * 20;',
                '    if (slug(leaf) == repositorySlug) value -= 1000;',
                "    if (entries.containsKey('$candidate/manifest.json')) value -= 250;",
                '    final lower = normalized.toLowerCase();',
                "    if (lower.startsWith('skills/') ||",
                "        lower.startsWith('.agents/skills/') ||",
                "        lower.startsWith('.claude/skills/') ||",
                "        lower.startsWith('.github/skills/')) {",
                '      value -= 120;',
                '    }',
                "    if (lower.contains('/skills/')) value -= 60;",
                '    return value;',
                '  }',
                '',
                '  candidates.sort((a, b) {',
                '    final scoreCompare = score(a).compareTo(score(b));',
                '    if (scoreCompare != 0) return scoreCompare;',
                "    final depthCompare = a.split('/').length.compareTo(b.split('/').length);",
                '    if (depthCompare != 0) return depthCompare;',
                '    return a.compareTo(b);',
                '  });',
                '  return candidates.first;',
                '}',
                '',
                'Map<String, String> _parseFrontmatter',
            ]
        )
        text, count = pattern.subn(lambda _: replacement, text, count=1)
        if count != 1:
            raise RuntimeError('Skill root function replacement anchor missing')
    elif 'repository: source.repository' in text and 'required String repository,' not in text:
        raise RuntimeError('Skill root signature is inconsistent')

    path.write_text(text)


def patch_lucide_aliases() -> None:
    path = Path('lib/icons/lucide_adapter.dart')
    text = path.read_text()
    if 'static const IconData CircleCheck =' in text:
        return
    anchor = '  static const IconData Coins = lucide.LucideIcons.coins;\n}'
    aliases = "\n".join(
        [
            '  static const IconData Coins = lucide.LucideIcons.coins;',
            '  static const IconData CircleCheck = CheckCircle;',
            '  static const IconData HardDriveDownload = Download;',
            '  static const IconData FolderInput = Import2;',
            '  static const IconData CircleOff = XCircle;',
            '  static const IconData Users = User;',
            '  static const IconData Cpu = Activity;',
            '  static const IconData Cloud = Network;',
            '}',
        ]
    )
    if anchor not in text:
        raise RuntimeError('Lucide adapter anchor missing')
    path.write_text(text.replace(anchor, aliases, 1))


def patch_voice_context_nullability() -> None:
    path = Path(
        'lib/features/story_runtime/orchestration/story_native_lifecycle_bridge.dart'
    )
    text = path.read_text()
    old = '  Future<StoryVoiceContextWindow> resolveNarratorContext('
    new = '  Future<StoryVoiceContextWindow?> resolveNarratorContext('
    if old in text:
        text = text.replace(old, new, 1)
    elif new not in text:
        raise RuntimeError('Narrator context return type anchor missing')
    path.write_text(text)


def patch_transition_lint() -> None:
    path = Path(
        'lib/features/story_runtime/orchestration/story_mode_transition_service.dart'
    )
    text = path.read_text()
    directive = '// ignore_for_file: prefer_initializing_formals\n\n'
    if not text.startswith('// ignore_for_file: prefer_initializing_formals'):
        text = directive + text
    path.write_text(text)


def patch_voice_manager_async_context() -> None:
    path = Path('lib/features/story_runtime/ui/story_voice_manager_page.dart')
    text = path.read_text()
    marker = "    final zh = Localizations.localeOf(context).languageCode == 'zh';\n"
    prefs_line = '    final preferences = context.read<BusinessPreferences>();\n'
    start = text.find('  Future<void> _editSelectedCharacters() async {')
    end = text.find('  Future<void> _saveAssignment({', start)
    if start < 0 or end < 0:
        raise RuntimeError('Voice batch edit function anchor missing')
    block = text[start:end]
    if prefs_line not in block:
        if marker not in block:
            raise RuntimeError('Voice batch preferences anchor missing')
        block = block.replace(marker, marker + prefs_line, 1)
    block = block.replace(
        'final store = StoryVoiceRoutingStore(context.read<BusinessPreferences>());',
        'final store = StoryVoiceRoutingStore(preferences);',
        1,
    )
    text = text[:start] + block + text[end:]
    path.write_text(text)


if __name__ == '__main__':
    patch_home_controller()
    patch_skill_discovery()
    patch_lucide_aliases()
    patch_voice_context_nullability()
    patch_transition_lint()
    patch_voice_manager_async_context()
