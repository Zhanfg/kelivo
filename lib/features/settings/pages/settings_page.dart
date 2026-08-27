import 'package:flutter/material.dart';

import '../../story_runtime/ui/story_skill_manager_page.dart';
import '../../story_runtime/ui/story_studio_page.dart';
import 'settings_core_page.dart' as core;

/// Kelivo settings with an explicit Story Runtime entry.
///
/// The original settings surface remains intact in [core.SettingsPage]. Story
/// capabilities are layered on top so the fork does not replace Kelivo's
/// existing settings/navigation contract.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: core.SettingsPage()),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            left: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'story-skills-settings-entry',
                  tooltip: 'Skills',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StorySkillManagerPage(),
                      ),
                    );
                  },
                  child: const Icon(Icons.extension_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'story-runtime-settings-entry',
                  tooltip: 'Story Mode',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StoryStudioPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: const Text('Story Mode'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
