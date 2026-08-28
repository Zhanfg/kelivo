import '../../../support/business_test_harness.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/composer/composer_reasoning_popover.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model adapter returns enabled provider models in configured order', () async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    await settings.setProviderConfig(
      'ProviderA',
      ProviderConfig(
        id: 'ProviderA',
        enabled: true,
        name: 'Provider A',
        apiKey: 'test-key',
        baseUrl: 'https://example.com/v1',
        providerType: ProviderKind.openai,
        models: const ['model-a'],
        modelOverrides: const {
          'model-a': {'name': 'Model A Display'},
        },
      ),
    );
    await settings.setProviderConfig(
      'Disabled',
      ProviderConfig(
        id: 'Disabled',
        enabled: false,
        name: 'Disabled',
        apiKey: 'test-key',
        baseUrl: 'https://example.com/v1',
        providerType: ProviderKind.openai,
        models: const ['hidden-model'],
      ),
    );

    final options = buildComposerModelOptions(settings);
    final visible = options.where((e) => e.providerKey == 'ProviderA').toList();
    expect(visible, hasLength(1));
    expect(visible.single.modelId, 'model-a');
    expect(visible.single.displayName, 'Model A Display');
    expect(options.any((e) => e.providerKey == 'Disabled'), isFalse);
  });

  testWidgets('primary reasoning popover is local and exposes no speed setting', (
    tester,
  ) async {
    int? chosenBudget;
    await tester.pumpWidget(
      _Harness(
        onBudgetChanged: (budget) async => chosenBudget = budget,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('anchor')));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(_Harness)))!;
    expect(find.byKey(const ValueKey('composer-reasoning-slider')), findsOneWidget);
    expect(find.text(l10n.reasoningBudgetSheetAuto), findsOneWidget);
    expect(find.text(l10n.modelDetailSheetAdvancedTab), findsOneWidget);
    expect(find.textContaining('Speed'), findsNothing);
    expect(chosenBudget, isNull);
  });

  testWidgets('advanced reasoning max respects the selected model capability', (
    tester,
  ) async {
    int? chosenBudget;
    await tester.pumpWidget(
      _Harness(
        supportsXhigh: true,
        supportsMax: false,
        onBudgetChanged: (budget) async => chosenBudget = budget,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('anchor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-reasoning-advanced')));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(_Harness)))!;
    expect(find.text(l10n.chatInputBarSelectModelTooltip), findsOneWidget);
    expect(find.text(l10n.chatInputBarReasoningStrengthTooltip), findsOneWidget);
    expect(find.textContaining('Speed'), findsNothing);

    await tester.tap(find.text(l10n.reasoningBudgetSheetMax));
    await tester.pumpAndSettle();
    expect(chosenBudget, 64000);
  });

  testWidgets('advanced model pane uses supplied real model options', (tester) async {
    String? chosenProvider;
    String? chosenModel;
    await tester.pumpWidget(
      _Harness(
        modelOptions: const [
          ComposerModelOption(
            providerKey: 'ProviderA',
            providerName: 'Provider A',
            modelId: 'model-a',
            displayName: 'Model A Display',
          ),
        ],
        onBudgetChanged: (_) async {},
        onModelChanged: (provider, model) async {
          chosenProvider = provider;
          chosenModel = model;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('anchor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-reasoning-advanced')));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(_Harness)))!;
    await tester.tap(find.text(l10n.chatInputBarSelectModelTooltip));
    await tester.pumpAndSettle();
    expect(find.text('Provider A'), findsOneWidget);
    expect(find.text('Model A Display'), findsOneWidget);

    await tester.tap(find.text('Model A Display'));
    await tester.pumpAndSettle();
    expect(chosenProvider, 'ProviderA');
    expect(chosenModel, 'model-a');
  });
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.onBudgetChanged,
    this.onModelChanged,
    this.supportsXhigh = false,
    this.supportsMax = false,
    this.modelOptions = const [],
  });

  final ComposerReasoningBudgetChanged onBudgetChanged;
  final ComposerModelChanged? onModelChanged;
  final bool supportsXhigh;
  final bool supportsMax;
  final List<ComposerModelOption> modelOptions;

  @override
  Widget build(BuildContext context) {
    final anchorKey = GlobalKey();
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: IconButton(
              key: anchorKey,
              icon: const Icon(Icons.psychology),
              onPressed: () => showComposerReasoningPopover(
                context,
                anchorKey: anchorKey,
                currentBudget: -1,
                supportsXhigh: supportsXhigh,
                supportsMax: supportsMax,
                currentProviderKey: 'ProviderA',
                currentModelId: 'model-a',
                modelOptions: modelOptions,
                onBudgetChanged: onBudgetChanged,
                onModelChanged: onModelChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
