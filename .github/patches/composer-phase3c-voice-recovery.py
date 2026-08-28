from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def patch_chat_input_bar() -> None:
    path = Path('lib/features/home/widgets/chat_input_bar.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """    final showVoiceInput =\n        asr != null &&\n        selectedAsrService != null &&\n        asr.canUse(selectedAsrService) &&\n        !asr.isActive;\n""",
        """    final selectedVoiceServiceUsable =\n        asr != null &&\n        selectedAsrService != null &&\n        asr.canUse(selectedAsrService);\n    // Voice input is opt-in, but a broken/unavailable selected service must not\n    // hide the recovery entrance. Keep the mic whenever at least one service\n    // exists; tapping an unusable selection opens the inline service switcher.\n    final showVoiceInput =\n        asr != null && settings.asrServices.isNotEmpty && !asr.isActive;\n""",
        'voice-recovery/show mic for configured service list',
    )

    text = replace_once(
        text,
        """                                                onTap:\n                                                    _composerLocked ||\n                                                        widget.loading\n                                                    ? null\n                                                    : () => unawaited(\n                                                        _startVoiceInput(),\n                                                      ),\n""",
        """                                                onTap:\n                                                    _composerLocked ||\n                                                        widget.loading\n                                                    ? null\n                                                    : selectedVoiceServiceUsable\n                                                    ? () => unawaited(\n                                                        _startVoiceInput(),\n                                                      )\n                                                    : _toggleInlineVoiceSettings,\n""",
        'voice-recovery/mic short tap routing',
    )

    path.write_text(text, encoding='utf-8')


def patch_tests() -> None:
    path = Path('test/features/home/widgets/chat_input_bar_asr_test.dart')
    text = path.read_text(encoding='utf-8')

    marker = """  testWidgets(\n    'long-press mic opens inline service switcher and selection collapses it',\n"""
    test = r'''  testWidgets(
    'unavailable selected ASR keeps mic and tap opens recovery switcher',
    (tester) async {
      final settings = SettingsProvider(createBusinessTestPreferences());
      await settings.loaded;
      final unavailable = SherpaOnnxAsrOptions(
        id: 'offline-missing',
        name: 'Missing Offline',
        modelId: 'missing-model',
      );
      final fallback = SystemAsrOptions(id: 'system-fallback', name: 'System');
      await settings.setAsrServices(<AsrServiceOptions>[unavailable, fallback]);
      await settings.setSelectedAsrServiceId(unavailable.id);
      final backend = _FakeSystemBackend();
      final asr = AsrProvider(
        systemService: SystemAsrService(backend: backend),
        localModelInstalledChecker: (_) async => false,
      );
      final controller = TextEditingController();
      addTearDown(asr.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        harness(settings: settings, asr: asr, controller: controller),
      );
      await tester.pump();

      expect(asr.canUse(unavailable), isFalse);
      expect(find.byTooltip('Voice input'), findsOneWidget);

      await tester.tap(find.byTooltip('Voice input'));
      await tester.pumpAndSettle();

      expect(asr.isActive, isFalse);
      expect(
        find.byKey(const ValueKey('voice-settings-inline')),
        findsOneWidget,
      );
      expect(find.text('Missing Offline'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('voice-service-chip:system-fallback')),
      );
      await tester.pumpAndSettle();

      expect(settings.selectedAsrServiceId, fallback.id);
      expect(find.byKey(const ValueKey('voice-settings-inline')), findsNothing);
      expect(find.byTooltip('Voice input'), findsOneWidget);
    },
  );

'''
    if marker not in text:
        raise SystemExit('voice-recovery/test insertion marker missing')
    text = text.replace(marker, test + marker, 1)
    path.write_text(text, encoding='utf-8')


patch_chat_input_bar()
patch_tests()
print('Composer phase 3c unavailable ASR recovery applied successfully')
