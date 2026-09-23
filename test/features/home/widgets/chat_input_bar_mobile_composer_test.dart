import '../../../support/business_test_harness.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/providers/asr_provider.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/asr/asr_service_options.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  Future<({SettingsProvider settings, AsrProvider asr})> providers() async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    await settings.setAsrServices(<AsrServiceOptions>[
      SystemAsrOptions(id: 'composer-mobile-system'),
    ]);
    return (settings: settings, asr: AsrProvider());
  }

  Widget harness({
    required SettingsProvider settings,
    required AsrProvider asr,
    required TextEditingController controller,
    Future<void> Function(int budget)? onReasoningBudgetChanged,
    bool storyMode = false,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(
          value: AssistantProvider(
            preferences: createBusinessTestPreferences(),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            asrProvider: asr,
            onMore: () {},
            onConfigureReasoning: () {},
            onReasoningBudgetChanged: onReasoningBudgetChanged ?? (_) async {},
            onSelectModel: () {},
            reasoningBudget: -1,
            supportsReasoning: true,
            currentModelProvider: 'ProviderA',
            currentModelId: 'model-a',
            supportsXhighReasoning: true,
            supportsMaxReasoning: false,
            onSend: (_) async => ChatInputSubmissionResult.rejected,
            storyMode: storyMode,
          ),
        ),
      ),
    );
  }

  testWidgets('mobile idle composer exposes only four primary entrances', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await providers();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(p.asr.dispose);

    await tester.pumpWidget(
      harness(settings: p.settings, asr: p.asr, controller: controller),
    );
    await tester.pump();

    final context = tester.element(find.byType(ChatInputBar));
    final l10n = AppLocalizations.of(context)!;

    expect(find.byIcon(Lucide.Plus), findsOneWidget);
    expect(
      find.byTooltip(l10n.chatInputBarReasoningStrengthTooltip),
      findsOneWidget,
    );
    expect(find.byTooltip('Voice input'), findsOneWidget);
    expect(find.byIcon(Lucide.ArrowUp), findsOneWidget);

    // Secondary capabilities stay out of the persistent mobile row.
    expect(find.byIcon(Lucide.Globe), findsNothing);
  });

  testWidgets('story composer keeps only story primary entrances', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await providers();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(p.asr.dispose);

    await tester.pumpWidget(
      harness(
        settings: p.settings,
        asr: p.asr,
        controller: controller,
        storyMode: true,
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(ChatInputBar));
    final l10n = AppLocalizations.of(context)!;
    expect(find.byIcon(Lucide.Plus), findsOneWidget);
    expect(find.byTooltip('Voice input'), findsOneWidget);
    expect(find.byIcon(Lucide.ArrowUp), findsOneWidget);
    expect(
      find.byTooltip(l10n.chatInputBarReasoningStrengthTooltip),
      findsNothing,
    );
  });

  testWidgets('mobile reasoning button opens the anchored local popover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await providers();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(p.asr.dispose);
    int? chosenBudget;

    await tester.pumpWidget(
      harness(
        settings: p.settings,
        asr: p.asr,
        controller: controller,
        onReasoningBudgetChanged: (budget) async {
          chosenBudget = budget;
        },
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(ChatInputBar));
    final l10n = AppLocalizations.of(context)!;
    await tester.tap(find.byTooltip(l10n.chatInputBarReasoningStrengthTooltip));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('composer-reasoning-slider')),
      findsOneWidget,
    );
    expect(find.text(l10n.modelDetailSheetAdvancedTab), findsOneWidget);
    expect(find.textContaining('Speed'), findsNothing);
    expect(chosenBudget, isNull);
  });

  testWidgets('six visual lines expose fullscreen editing and preserve draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await providers();
    final controller = TextEditingController(
      text: 'one\ntwo\nthree\nfour\nfive\nsix',
    );
    addTearDown(controller.dispose);
    addTearDown(p.asr.dispose);

    await tester.pumpWidget(
      harness(settings: p.settings, asr: p.asr, controller: controller),
    );
    await tester.pump();

    expect(find.byIcon(Lucide.Maximize2), findsOneWidget);
    await tester.tap(find.byIcon(Lucide.Maximize2));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Collapse editor'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.last, 'edited in fullscreen');
    expect(controller.text, 'edited in fullscreen');

    await tester.tap(find.byTooltip('Collapse editor'));
    await tester.pumpAndSettle();
    expect(controller.text, 'edited in fullscreen');
  });
}
