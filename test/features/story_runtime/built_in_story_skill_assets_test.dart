import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all runtime-loaded built-in Story skill assets are bundled', () async {
    const assets = <String>[
      'assets/story_skills/lieflat-less-ai-tone/SKILL.md',
      'assets/story_skills/lieflat-less-ai-tone/prompts/10_kelivo_human_writing_core.md',
      'assets/story_skills/visual-taste-basics/SKILL.md',
      'assets/story_skills/github-story-serialization/SKILL.md',
    ];

    for (final asset in assets) {
      final contents = await rootBundle.loadString(asset);
      expect(contents.trim(), isNotEmpty, reason: 'Missing or empty asset: $asset');
    }
  });
}
