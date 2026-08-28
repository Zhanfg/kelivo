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

    if 'required String repository' not in text:
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

    path.write_text(text)


if __name__ == '__main__':
    patch_home_controller()
    patch_skill_discovery()
