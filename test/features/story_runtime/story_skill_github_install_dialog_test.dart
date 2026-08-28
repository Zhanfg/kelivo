import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo/features/story_runtime/ui/story_skill_github_install_dialog.dart';

void main() {
  testWidgets(
    'GitHub Skill install dialog keeps controllers alive through route pop',
    (tester) async {
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

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));

      await tester.enterText(fields.at(0), 'owner/story-skill');
      await tester.enterText(fields.at(1), 'main');
      await tester.enterText(fields.at(2), 'skills/example');
      await tester.pump();

      await tester.tap(find.text('安装'));

      // showDialog completes as soon as the route is popped, while its reverse
      // transition can still keep the TextFields mounted. Their controllers
      // must therefore remain alive until the dialog State itself is disposed.
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(result, isNotNull);
      expect(result!.repositoryUrl, 'owner/story-skill');
      expect(result!.ref, 'main');
      expect(result!.subdirectory, 'skills/example');
    },
  );
}
