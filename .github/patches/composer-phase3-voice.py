from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def replace_between(text: str, start_marker: str, end_marker: str, replacement: str, label: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'{label}: start marker missing')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'{label}: end marker missing')
    return text[:start] + replacement + text[end:]


def patch_asr_provider() -> None:
    path = Path('lib/core/providers/asr_provider.dart')
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        """  bool get isListening => _state == AsrSessionState.listening;\n\n  bool canUse(AsrServiceOptions? options) {\n""",
        """  bool get isListening => _state == AsrSessionState.listening;\n\n  /// Whether the active recognizer can publish transcript updates before\n  /// recording finishes. Offline Sherpa currently buffers the whole clip and\n  /// only transcribes after Stop; system and cloud sessions publish partials.\n  bool get supportsLiveTranscript => switch (_activeService) {\n    SherpaOnnxAsrOptions() => false,\n    null => false,\n    _ => true,\n  };\n\n  bool canUse(AsrServiceOptions? options) {\n""",
        'asr/live transcript capability',
    )
    path.write_text(text, encoding='utf-8')


def patch_chat_input_bar() -> None:
    path = Path('lib/features/home/widgets/chat_input_bar.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """  TextEditingValue? _voiceBaseValue;\n  bool _ownsVoiceSession = false;\n""",
        """  TextEditingValue? _voiceBaseValue;\n  String _voiceLastObservedTranscript = '';\n  bool _voiceTranscriptEditing = false;\n  bool _ownsVoiceSession = false;\n""",
        'chat_input_bar/voice edit state',
    )

    text = replace_once(
        text,
        """  // Instance method for onChanged to avoid recreating the callback on every build\n  void _onTextChanged(String _) => setState(() {});\n""",
        """  // Instance method for onChanged to avoid recreating the callback on every build.\n  // Programmatic controller writes do not invoke TextField.onChanged, so this\n  // is also the boundary where a live ASR transcript becomes user-owned text.\n  void _onTextChanged(String _) {\n    final asr = widget.asrProvider;\n    if (_ownsVoiceSession &&\n        !_finishingVoice &&\n        asr?.supportsLiveTranscript == true) {\n      _voiceTranscriptEditing = true;\n      final composing = _controller.value.composing;\n      if (!composing.isValid || composing.isCollapsed) {\n        WidgetsBinding.instance.addPostFrameCallback((_) {\n          if (!mounted ||\n              !_ownsVoiceSession ||\n              !_voiceTranscriptEditing ||\n              _finishingVoice) {\n            return;\n          }\n          final activeAsr = widget.asrProvider;\n          if (activeAsr?.supportsLiveTranscript == true) {\n            _applyVoiceTranscript(activeAsr!.transcript);\n            if (mounted) setState(() {});\n          }\n        });\n      }\n    }\n    setState(() {});\n  }\n""",
        'chat_input_bar/on text changed',
    )

    text = replace_once(
        text,
        """    _voiceBaseValue = _controller.value;\n    _ownsVoiceSession = true;\n    _finishingVoice = false;\n    _lastReportedVoiceError = null;\n    _voiceLevels.clear();\n""",
        """    _voiceBaseValue = _controller.value;\n    _voiceLastObservedTranscript = '';\n    _voiceTranscriptEditing = false;\n    _ownsVoiceSession = true;\n    _finishingVoice = false;\n    _lastReportedVoiceError = null;\n    _voiceLevels.clear();\n""",
        'chat_input_bar/start voice edit reset',
    )

    handle_asr = """  void _handleAsrChanged() {\n    if (!mounted || !_ownsVoiceSession) return;\n    final asr = widget.asrProvider;\n    if (asr == null) return;\n\n    _applyVoiceTranscript(asr.transcript);\n    final error = asr.error;\n    if (error != null && error.trim().isNotEmpty) {\n      _stopVoiceLevelSampling();\n      _voiceBaseValue = null;\n      _ownsVoiceSession = false;\n      _finishingVoice = false;\n      _voiceLevels.clear();\n      _resetVoiceTranscriptTracking();\n      _reportVoiceFailure(error);\n      scheduleMicrotask(asr.clearError);\n    } else if (!asr.isActive && !_finishingVoice) {\n      // Some system recognizers publish a final result and stop on their own.\n      _stopVoiceLevelSampling();\n      final detectedSpeech = asr.transcript.trim().isNotEmpty;\n      _voiceBaseValue = null;\n      _ownsVoiceSession = false;\n      _voiceLevels.clear();\n      _resetVoiceTranscriptTracking();\n      if (!detectedSpeech) _reportNoSpeech();\n    }\n    setState(() {});\n    if (!_voiceTranscriptEditing) _ensureCaretVisible();\n  }\n\n  void _resetVoiceTranscriptTracking() {\n    _voiceLastObservedTranscript = '';\n    _voiceTranscriptEditing = false;\n  }\n\n"""
    text = replace_between(
        text,
        "  void _handleAsrChanged() {\n",
        "  void _startVoiceLevelSampling() {\n",
        handle_asr,
        'chat_input_bar/handle asr changed',
    )

    apply_transcript = """  void _applyVoiceTranscript(String transcript) {\n    final baseValue = _voiceBaseValue;\n    if (baseValue == null) return;\n    final spoken = transcript.trim();\n\n    if (_voiceTranscriptEditing) {\n      final composing = _controller.value.composing;\n      // Never mutate the controller while an IME composition is active. The\n      // latest provider transcript remains available and will be reconciled on\n      // the next provider/user event or when recording finishes.\n      if (composing.isValid && !composing.isCollapsed) return;\n\n      final previous = _voiceLastObservedTranscript;\n      if (spoken == previous) return;\n      if (spoken.isNotEmpty &&\n          spoken.startsWith(previous) &&\n          spoken.length > previous.length) {\n        final delta = spoken.substring(previous.length).trimLeft();\n        if (delta.isNotEmpty) {\n          final current = _controller.value;\n          final oldLength = current.text.length;\n          final text = _joinVoiceText(current.text, delta);\n          final selection = current.selection;\n          final nextSelection = selection.isValid\n              ? selection.copyWith(\n                  baseOffset: selection.baseOffset == oldLength\n                      ? text.length\n                      : selection.baseOffset,\n                  extentOffset: selection.extentOffset == oldLength\n                      ? text.length\n                      : selection.extentOffset,\n                )\n              : TextSelection.collapsed(offset: text.length);\n          _controller.value = current.copyWith(\n            text: text,\n            selection: nextSelection,\n            composing: TextRange.empty,\n          );\n        }\n      }\n      // If the recognizer revises already-seen words after the user has edited\n      // them, prefer the user's correction. Advance the shadow transcript so\n      // future genuinely-new suffixes can still stream into the draft.\n      _voiceLastObservedTranscript = spoken;\n      return;\n    }\n\n    _voiceLastObservedTranscript = spoken;\n    final text = _joinVoiceText(baseValue.text, spoken);\n    if (_controller.text == text) return;\n    _controller.value = TextEditingValue(\n      text: text,\n      selection: TextSelection.collapsed(offset: text.length),\n      composing: TextRange.empty,\n    );\n  }\n\n"""
    text = replace_between(
        text,
        "  void _applyVoiceTranscript(String transcript) {\n",
        "  String _joinVoiceText(String base, String transcript) {\n",
        apply_transcript,
        'chat_input_bar/apply voice transcript',
    )

    cancel_voice = """  Future<void> _cancelVoiceInput() async {\n    if (!_ownsVoiceSession) return;\n    _stopVoiceLevelSampling();\n    final asr = widget.asrProvider;\n    final original = _voiceBaseValue;\n    _voiceBaseValue = null;\n    _ownsVoiceSession = false;\n    _finishingVoice = false;\n    _voiceLevels.clear();\n    _resetVoiceTranscriptTracking();\n    if (original != null) _controller.value = original;\n    if (mounted) setState(() {});\n    try {\n      await asr?.cancel();\n    } catch (error) {\n      if (mounted) _reportVoiceFailure(error);\n    }\n  }\n\n"""
    text = replace_between(
        text,
        "  Future<void> _cancelVoiceInput() async {\n",
        "  Future<void> _finishVoiceInput({required bool sendAfter}) async {\n",
        cancel_voice,
        'chat_input_bar/cancel voice',
    )

    finish_voice = """  Future<void> _finishVoiceInput() async {\n    final asr = widget.asrProvider;\n    if (!_ownsVoiceSession || _finishingVoice || asr == null) return;\n    _stopVoiceLevelSampling();\n    _finishingVoice = true;\n    setState(() {});\n\n    try {\n      final transcript = await asr.finish();\n      if (!mounted) return;\n      _applyVoiceTranscript(transcript);\n      final detectedSpeech = transcript.trim().isNotEmpty;\n      _voiceBaseValue = null;\n      _ownsVoiceSession = false;\n      _voiceLevels.clear();\n      _resetVoiceTranscriptTracking();\n      setState(() {});\n      _ensureCaretVisible();\n      if (!detectedSpeech) _reportNoSpeech();\n    } catch (error) {\n      if (!mounted) return;\n      if (_ownsVoiceSession) {\n        _voiceBaseValue = null;\n        _ownsVoiceSession = false;\n        _voiceLevels.clear();\n        _resetVoiceTranscriptTracking();\n        setState(() {});\n      }\n      if (_lastReportedVoiceError == null) _reportVoiceFailure(error);\n    } finally {\n      _finishingVoice = false;\n      if (mounted) setState(() {});\n    }\n  }\n\n"""
    text = replace_between(
        text,
        "  Future<void> _finishVoiceInput({required bool sendAfter}) async {\n",
        "  void _reportNoSpeech() {\n",
        finish_voice,
        'chat_input_bar/finish voice no auto send',
    )

    voice_row = """  /// Recording row stays intentionally compact: cancel, one continuous\n  /// waveform/transcribing surface, and Stop. Sending is only available after\n  /// transcription returns to the normal Composer action row.\n  Widget _buildVoiceRecordingRow(BuildContext context, ThemeData theme) {\n    final l10n = AppLocalizations.of(context)!;\n    final canFinish =\n        widget.asrProvider?.isListening == true && !_finishingVoice;\n    return Row(\n      key: const ValueKey('voice'),\n      children: [\n        _CompactIconButton(\n          tooltip: l10n.chatInputBarVoiceCancelTooltip,\n          icon: Lucide.X,\n          onTap: _finishingVoice ? null : () => unawaited(_cancelVoiceInput()),\n        ),\n        Expanded(\n          child: Padding(\n            padding: const EdgeInsets.only(left: 8, right: 8),\n            child: SizedBox(\n              height: 32,\n              child: AnimatedSwitcher(\n                duration: const Duration(milliseconds: 180),\n                layoutBuilder: (currentChild, previousChildren) => Stack(\n                  fit: StackFit.expand,\n                  alignment: Alignment.center,\n                  children: <Widget>[\n                    ...previousChildren,\n                    if (currentChild != null) currentChild,\n                  ],\n                ),\n                child: _finishingVoice\n                    ? _VoiceTranscribingIndicator(\n                        key: const ValueKey('voice-transcribing-indicator'),\n                        label: l10n.chatInputBarVoiceTranscribing,\n                        color: theme.colorScheme.onSurface.withValues(\n                          alpha: 0.72,\n                        ),\n                      )\n                    : ValueListenableBuilder<int>(\n                        valueListenable: _voiceLevelsVersion,\n                        builder: (context, _, _) => _VoiceWaveform(\n                          key: const ValueKey('voice-waveform'),\n                          levels: _voiceLevels,\n                          color: theme.colorScheme.onSurface.withValues(\n                            alpha: 0.85,\n                          ),\n                        ),\n                      ),\n              ),\n            ),\n          ),\n        ),\n        _CompactIconButton(\n          tooltip: l10n.chatInputBarVoiceStopTooltip,\n          icon: Lucide.Square,\n          onTap: canFinish ? () => unawaited(_finishVoiceInput()) : null,\n          childBuilder: (c) => Center(\n            child: Container(\n              width: 12,\n              height: 12,\n              decoration: BoxDecoration(\n                color: c,\n                borderRadius: BorderRadius.circular(3.5),\n              ),\n            ),\n          ),\n        ),\n      ],\n    );\n  }\n\n"""
    text = replace_between(
        text,
        "  /// Bottom row shown while recording: cancel (X) — waveform — stop — send.\n",
        "  Future<void> _handleSend() async {\n",
        voice_row,
        'chat_input_bar/voice recording row',
    )

    text = replace_once(
        text,
        """    final showVoiceInput =\n        asr != null &&\n        selectedAsrService != null &&\n        asr.canUse(selectedAsrService) &&\n        !asr.isActive;\n    final isDark = theme.brightness == Brightness.dark;\n""",
        """    final showVoiceInput =\n        asr != null &&\n        selectedAsrService != null &&\n        asr.canUse(selectedAsrService) &&\n        !asr.isActive;\n    final voiceTranscriptEditable =\n        _ownsVoiceSession &&\n        !_finishingVoice &&\n        asr?.supportsLiveTranscript == true;\n    final isDark = theme.brightness == Brightness.dark;\n""",
        'chat_input_bar/build live edit flag',
    )

    text = replace_once(
        text,
        """                                            readOnly:\n                                                _composerLocked ||\n                                                _ownsVoiceSession,\n""",
        """                                            readOnly:\n                                                _composerLocked ||\n                                                (_ownsVoiceSession &&\n                                                    !voiceTranscriptEditable),\n""",
        'chat_input_bar/live text field readOnly',
    )

    text = replace_once(
        text,
        """                              // Expand/Collapse icon button (only shown when 3+ lines)\n                              if (showExpandButton)\n""",
        """                              // Fullscreen editing is a separate global surface. Keep\n                              // live voice edits in-place directly above the IME.\n                              if (showExpandButton && !_ownsVoiceSession)\n""",
        'chat_input_bar/hide fullscreen during voice',
    )

    if '_finishVoiceInput(sendAfter:' in text:
        raise SystemExit('chat_input_bar: stale sendAfter voice call remains')

    path.write_text(text, encoding='utf-8')


def patch_asr_widget_tests() -> None:
    path = Path('test/features/home/widgets/chat_input_bar_asr_test.dart')
    text = path.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """  Widget harness({\n    required SettingsProvider settings,\n    required AsrProvider asr,\n    required TextEditingController controller,\n  }) {\n""",
        """  Widget harness({\n    required SettingsProvider settings,\n    required AsrProvider asr,\n    required TextEditingController controller,\n    Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend,\n  }) {\n""",
        'asr_test/harness signature',
    )
    text = replace_once(
        text,
        """            onSend: (_) async => ChatInputSubmissionResult.rejected,\n""",
        """            onSend:\n                onSend ?? (_) async => ChatInputSubmissionResult.rejected,\n""",
        'asr_test/harness send callback',
    )

    new_test = r'''  testWidgets('live ASR remains editable and Stop never auto-sends', (
    tester,
  ) async {
    final settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    final option = SystemAsrOptions(id: 'system-edit-test');
    await settings.setAsrServices(<AsrServiceOptions>[option]);
    final backend = _FakeSystemBackend();
    final asr = AsrProvider(systemService: SystemAsrService(backend: backend));
    final controller = TextEditingController(text: 'draft');
    var sendCalls = 0;
    addTearDown(asr.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      harness(
        settings: settings,
        asr: asr,
        controller: controller,
        onSend: (_) async {
          sendCalls++;
          return ChatInputSubmissionResult.rejected;
        },
      ),
    );
    await tester.tap(find.byTooltip('Voice input'));
    await tester.pump();

    backend.emitTranscript('hello world', false);
    await tester.pump();
    expect(controller.text, 'draft hello world');
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);

    await tester.enterText(
      find.byType(TextField),
      'draft hello brave world',
    );
    await tester.pump();
    backend.emitTranscript('hello world again', false);
    await tester.pump();
    expect(controller.text, 'draft hello brave world again');

    await tester.tap(find.byTooltip('Stop and transcribe to input'));
    await tester.pumpAndSettle();

    expect(sendCalls, 0);
    expect(controller.text, 'draft hello brave world again');
    expect(find.byTooltip('Voice input'), findsOneWidget);
  });

'''
    marker = "  testWidgets('cancelling ASR restores the exact original editing value', (\n"
    if marker not in text:
        raise SystemExit('asr_test/new live edit insertion marker missing')
    text = text.replace(marker, new_test + marker, 1)

    text = replace_once(
        text,
        """    await tester.tap(find.byTooltip('Voice input'));\n    await tester.pump();\n    capture.add(_pcm16(6000));\n""",
        """    await tester.tap(find.byTooltip('Voice input'));\n    await tester.pump();\n    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);\n    capture.add(_pcm16(6000));\n""",
        'asr_test/offline remains readonly',
    )

    path.write_text(text, encoding='utf-8')


patch_asr_provider()
patch_chat_input_bar()
patch_asr_widget_tests()
print('Composer phase 3 editable voice transcription applied successfully')
