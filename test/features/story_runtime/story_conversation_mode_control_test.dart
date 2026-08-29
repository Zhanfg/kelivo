import '../../support/business_test_harness.dart';

import 'package:Kelivo/core/database/business_preferences.dart';
import 'package:Kelivo/features/story_runtime/ui/story_conversation_mode_control.dart';
import 'package:Kelivo/shared/widgets/interactive_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'workspace selection persists independently of a conversation',
    () async {
      final harness = await createBusinessTestHarness();
      await harness.preferences.setBool(storyWorkspaceSelectedKey, true);

      final reloaded = BusinessPreferences(harness.repository);
      await reloaded.load();

      expect(isStoryWorkspaceSelected(reloaded), isTrue);
    },
  );

  testWidgets('centered mode slot stays physically centered and tappable', (
    tester,
  ) async {
    const controlKey = ValueKey<String>('story-mode-control');
    const storyTargetKey = ValueKey<String>('story-mode-story-target');
    var storyTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            centerTitle: false,
            leading: const SizedBox(width: 56),
            titleSpacing: 2,
            title: StoryConversationModeCenteredSlot(
              controlWidth: 124,
              child: SizedBox(
                key: controlKey,
                width: 124,
                height: 36,
                child: Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    Expanded(
                      child: InkWell(
                        key: storyTargetKey,
                        onTap: () => storyTapped = true,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: const [
              SizedBox(width: 44),
              SizedBox(width: 44),
              SizedBox(width: 4),
            ],
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final screenWidth = tester.getSize(find.byType(Scaffold)).width;
    final controlRect = tester.getRect(find.byKey(controlKey));
    expect(
      controlRect.center.dx,
      moreOrLessEquals(screenWidth / 2, epsilon: 0.5),
    );

    await tester.tap(find.byKey(storyTargetKey));
    await tester.pump();
    expect(storyTapped, isTrue);
  });

  testWidgets('mode slot hides while the drawer is open', (tester) async {
    const controlKey = ValueKey<String>('story-mode-control');
    final drawerController = InteractiveDrawerController(initialValue: 1);
    addTearDown(drawerController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveDrawer(
          controller: drawerController,
          drawerWidth: 300,
          drawer: const ColoredBox(color: Colors.white),
          child: Scaffold(
            appBar: AppBar(
              title: const StoryConversationModeCenteredSlot(
                controlWidth: 124,
                child: SizedBox(key: controlKey, width: 124, height: 36),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.byKey(controlKey), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 0);
  });
}
