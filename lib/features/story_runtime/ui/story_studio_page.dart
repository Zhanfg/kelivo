import 'package:flutter/material.dart';

import 'story_mode_runtime_page.dart';

/// Backward-compatible entry point retained for existing Settings navigation.
class StoryStudioPage extends StatelessWidget {
  const StoryStudioPage({super.key});

  @override
  Widget build(BuildContext context) => const StoryModeRuntimePage();
}
