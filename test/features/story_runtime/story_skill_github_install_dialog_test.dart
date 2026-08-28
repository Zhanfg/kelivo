import 'package:Kelivo/features/story_runtime/ui/story_skill_github_install_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GitHub Skill install uses one-field bottom sheet', (tester) async {
    StorySkillGitHubInstallRequest? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showStorySkillGitHubInstallDialog(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('从 GitHub 安装 Skill'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Branch / Tag / Ref'), findsNothing);
    expect(find.textContaining('Skill 子目录'), findsNothing);

    await tester.enterText(find.byType(TextField), 'owner/story-skill');
    await tester.pump();
    await tester.tap(find.text('自动查找并安装'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNotNull);
    expect(result!.repositoryUrl, 'owner/story-skill');
    expect(result!.ref, isNull);
    expect(result!.subdirectory, isNull);
  });
}
