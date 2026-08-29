import '../../../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/world_book_provider.dart';
import 'package:Kelivo/features/chat/widgets/bottom_tools_sheet.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  testWidgets('mobile tools expose the approved 2x2 primary actions', (
    tester,
  ) async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(
            create: (_) => WorldBookProvider(preferences: harness.preferences),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BottomToolsSheet(
              onPhotos: () {},
              onCamera: () {},
              onUpload: () {},
              onDrawing: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
  });

  testWidgets('story tools replace chat-only secondary actions', (
    tester,
  ) async {
    final harness = await createBusinessTestHarness();
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(
            create: (_) => WorldBookProvider(preferences: harness.preferences),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: BottomToolsSheet(storyConversationId: 'story-1'),
          ),
        ),
      ),
    );

    expect(find.text('World Book'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Characters'), findsOneWidget);
    expect(find.text('Voices'), findsOneWidget);
    expect(find.text('References'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Online Search'), findsNothing);
  });
}
