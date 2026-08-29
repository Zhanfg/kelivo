from pathlib import Path

shell = Path('lib/features/home/composer/composer_voice_shell.dart')
text = shell.read_text(encoding='utf-8')

old_state = """                Text(
                  _stateLabel(context),
                  key: const ValueKey('voice-state-label'),
                  style: TextStyle(
"""
new_state = """                KeyedSubtree(
                  key: ValueKey(
                    ready
                        ? 'voice-state-ready'
                        : transcribing
                        ? 'voice-state-transcribing'
                        : locked
                        ? 'voice-state-locked'
                        : pttActive
                        ? 'voice-state-ptt'
                        : 'voice-state-recording',
                  ),
                  child: Text(
                  _stateLabel(context),
                  key: const ValueKey('voice-state-label'),
                  style: TextStyle(
"""
if text.count(old_state) != 1:
    raise SystemExit(f'voice-state-key: expected 1 match, found {text.count(old_state)}')
text = text.replace(old_state, new_state, 1)

old_state_end = """                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 7),
"""
new_state_end = """                    color: cs.onSurface,
                  ),
                ),
                  ),
                const SizedBox(width: 7),
"""
if text.count(old_state_end) != 1:
    raise SystemExit(f'voice-state-key-close: expected 1 match, found {text.count(old_state_end)}')
text = text.replace(old_state_end, new_state_end, 1)

old_service = """                        _MetaRow(label: zh ? '服务' : 'Service', value: serviceName),
"""
new_service = """                        if (serviceName != modelLabel)
                          _MetaRow(label: zh ? '服务' : 'Service', value: serviceName),
"""
if text.count(old_service) != 1:
    raise SystemExit(f'voice-service-dedupe: expected 1 match, found {text.count(old_service)}')
text = text.replace(old_service, new_service, 1)
shell.write_text(text, encoding='utf-8')

test = Path('test/features/home/widgets/chat_input_bar_asr_test.dart')
t = test.read_text(encoding='utf-8')

old_locked = """      expect(find.text('Locked'), findsOneWidget);
"""
new_locked = """      expect(
        find.byKey(const ValueKey('voice-state-locked')),
        findsOneWidget,
      );
"""
if t.count(old_locked) != 1:
    raise SystemExit(f'ptt-locked-assertion: expected 1 match, found {t.count(old_locked)}')
t = t.replace(old_locked, new_locked, 1)

old_local = """    await tester.tap(find.byTooltip('Stop and transcribe to input'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('voice-transcribing-indicator')),
      findsOneWidget,
    );
    expect(find.text('Recognizing…'), findsOneWidget);
    expect(transcriptionCalls, 1);

    await tester.tap(find.byTooltip('Stop and transcribe to input'));
    await tester.pump();
    expect(transcriptionCalls, 1);
"""
new_local = """    await tester.tap(find.byKey(const ValueKey('voice-stop')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('voice-transcribing-indicator')),
      findsOneWidget,
    );
    expect(find.text('Recognizing…'), findsOneWidget);
    expect(transcriptionCalls, 1);

    expect(find.byKey(const ValueKey('voice-stop')), findsNothing);
    expect(transcriptionCalls, 1);
"""
if t.count(old_local) != 1:
    raise SystemExit(f'local-stop-test: expected 1 match, found {t.count(old_local)}')
t = t.replace(old_local, new_local, 1)

test.write_text(t, encoding='utf-8')
print('Voice shell regression fixes applied')
