import 'package:flutter/material.dart';

import 'story_mode_runtime_page.dart';

/// Backward-compatible route kept for older navigation entries.
///
/// The former debug-style runtime console was intentionally removed from the
/// product surface. All Story configuration now uses the same native settings
/// UI as [StoryModeRuntimePage].
class StoryRuntimeControlPage extends StatelessWidget {
  const StoryRuntimeControlPage({super.key});

  @override
  Widget build(BuildContext context) => const StoryModeRuntimePage();
}
