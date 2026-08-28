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
        """import '../composer/composer_reasoning_popover.dart';\n""",
        """import '../composer/composer_reasoning_popover.dart';\nimport '../../settings/pages/tts_services_page.dart';\n""",
        'voice-settings/import voice services page',
    )

    text = replace_once(
        text,
        """  bool _voiceTranscriptEditing = false;\n  bool _ownsVoiceSession = false;\n""",
        """  bool _voiceTranscriptEditing = false;\n  bool _voiceSettingsExpanded = false;\n  bool _ownsVoiceSession = false;\n""",
        'voice-settings/state flag',
    )

    marker = """  Future<void> _startVoiceInput() async {\n"""
    if marker not in text:
        raise SystemExit('voice-settings/start voice marker missing')
    methods = r'''  void _toggleInlineVoiceSettings() {
    final settings = context.read<SettingsProvider>();
    if (_composerLocked ||
        widget.loading ||
        _ownsVoiceSession ||
        _finishingVoice ||
        settings.asrServices.isEmpty) {
      return;
    }
    setState(() => _voiceSettingsExpanded = !_voiceSettingsExpanded);
  }

  Future<void> _selectInlineVoiceService(AsrServiceOptions service) async {
    if (_composerLocked ||
        widget.loading ||
        _ownsVoiceSession ||
        _finishingVoice) {
      return;
    }
    final settings = context.read<SettingsProvider>();
    await settings.setSelectedAsrServiceId(service.id);
    if (service is SherpaOnnxAsrOptions) {
      await widget.asrProvider?.refreshAvailability(service);
    }
    if (!mounted) return;
    setState(() => _voiceSettingsExpanded = false);
  }

  Future<void> _openVoiceServicesSettings() async {
    if (_ownsVoiceSession || _finishingVoice) return;
    setState(() => _voiceSettingsExpanded = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TtsServicesPage()),
    );
  }

'''
    text = text.replace(marker, methods + marker, 1)

    text = replace_once(
        text,
        """    _voiceBaseValue = _controller.value;\n    _voiceLastObservedTranscript = '';\n    _voiceTranscriptEditing = false;\n    _ownsVoiceSession = true;\n""",
        """    _voiceBaseValue = _controller.value;\n    _voiceLastObservedTranscript = '';\n    _voiceTranscriptEditing = false;\n    _voiceSettingsExpanded = false;\n    _ownsVoiceSession = true;\n""",
        'voice-settings/collapse on start',
    )

    build_marker = """  @override\n  Widget build(BuildContext context) {\n"""
    helper = r'''  Widget _buildInlineVoiceSettings(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final selectedId = settings.selectedAsrServiceId;
    final services = settings.asrServices;

    return Padding(
      key: const ValueKey('voice-settings-inline'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: [
              Icon(
                Lucide.Mic,
                size: 16,
                color: cs.onSurface.withValues(alpha: 0.64),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0; index < services.length; index++) ...[
                        _InlineVoiceServiceChip(
                          key: ValueKey('voice-service-chip:${services[index].id}'),
                          label: services[index].name,
                          selected: selectedId == services[index].id,
                          onTap: () => unawaited(
                            _selectInlineVoiceService(services[index]),
                          ),
                        ),
                        if (index != services.length - 1)
                          const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _CompactIconButton(
                tooltip: l10n.ttsServicesPageTitle,
                icon: Lucide.Settings2,
                onTap: () => unawaited(_openVoiceServicesSettings()),
              ),
              _CompactIconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: Lucide.X,
                onTap: () => setState(() => _voiceSettingsExpanded = false),
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
    if build_marker not in text:
        raise SystemExit('voice-settings/build marker missing')
    text = text.replace(build_marker, helper + build_marker, 1)

    text = replace_once(
        text,
        """                          // Bottom buttons row (no divider)\n                          Padding(\n""",
        """                          AnimatedSize(\n                            duration: const Duration(milliseconds: 180),\n                            curve: Curves.easeOutCubic,\n                            alignment: Alignment.topCenter,\n                            child:\n                                _voiceSettingsExpanded &&\n                                    !_ownsVoiceSession &&\n                                    settings.asrServices.isNotEmpty\n                                ? _buildInlineVoiceSettings(context, settings)\n                                : const SizedBox.shrink(\n                                    key: ValueKey('voice-settings-collapsed'),\n                                  ),\n                          ),\n                          // Bottom buttons row (no divider)\n                          Padding(\n""",
        'voice-settings/inline placement',
    )

    text = replace_once(
        text,
        """                                                icon: Lucide.Mic,\n                                                onTap:\n                                                    _composerLocked ||\n                                                        widget.loading\n                                                    ? null\n                                                    : () => unawaited(\n                                                        _startVoiceInput(),\n                                                      ),\n""",
        """                                                icon: Lucide.Mic,\n                                                active: _voiceSettingsExpanded,\n                                                onTap:\n                                                    _composerLocked ||\n                                                        widget.loading\n                                                    ? null\n                                                    : () => unawaited(\n                                                        _startVoiceInput(),\n                                                      ),\n                                                onLongPress:\n                                                    _composerLocked ||\n                                                        widget.loading\n                                                    ? null\n                                                    : _toggleInlineVoiceSettings,\n""",
        'voice-settings/mic long press',
    )

    class_marker = """// New compact send button for the integrated input bar\nclass _CompactSendButton extends StatelessWidget {\n"""
    chip = r'''class _InlineVoiceServiceChip extends StatelessWidget {
  const _InlineVoiceServiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = selected
        ? cs.secondaryContainer
        : cs.surfaceContainerHighest.withValues(alpha: 0.54);
    final foreground = selected ? cs.onSecondaryContainer : cs.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Lucide.Check, size: 14, color: foreground),
                const SizedBox(width: 4),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: selected
                        ? AppFontWeights.semibold
                        : AppFontWeights.medium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// New compact send button for the integrated input bar
class _CompactSendButton extends StatelessWidget {
'''
    text = replace_once(
        text,
        class_marker,
        chip,
        'voice-settings/chip widget',
    )

    path.write_text(text, encoding='utf-8')


def patch_asr_tests() -> None:
    path = Path('test/features/home/widgets/chat_input_bar_asr_test.dart')
    text = path.read_text(encoding='utf-8')
    marker = """  testWidgets('system ASR replaces partials from a stable draft base', (\n"""
    test = r'''  testWidgets('long-press mic opens inline service switcher and selection collapses it', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    final first = SystemAsrOptions(id: 'system-a', name: 'System A');
    final second = SystemAsrOptions(id: 'system-b', name: 'System B');
    await settings.setAsrServices(<AsrServiceOptions>[first, second]);
    await settings.setSelectedAsrServiceId(first.id);
    final backend = _FakeSystemBackend();
    final asr = AsrProvider(systemService: SystemAsrService(backend: backend));
    final controller = TextEditingController();
    addTearDown(asr.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness(settings: settings, asr: asr, controller: controller),
    );
    await tester.longPress(find.byTooltip('Voice input'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-settings-inline')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('System A'), findsOneWidget);
    expect(find.text('System B'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('voice-service-chip:system-b')),
    );
    await tester.pumpAndSettle();

    expect(settings.selectedAsrServiceId, second.id);
    expect(find.byKey(const ValueKey('voice-settings-inline')), findsNothing);
    expect(find.byTooltip('Voice input'), findsOneWidget);
  });

'''
    if marker not in text:
        raise SystemExit('voice-settings/test insertion marker missing')
    text = text.replace(marker, test + marker, 1)
    path.write_text(text, encoding='utf-8')


patch_chat_input_bar()
patch_asr_tests()
print('Composer phase 3b inline voice settings applied successfully')
