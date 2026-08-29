from pathlib import Path

bar = Path('lib/features/home/widgets/chat_input_bar.dart')
b = bar.read_text(encoding='utf-8')

old_fields = """  bool _voicePttLocked = false;
  bool _voicePttCancelArmed = false;
  bool _voicePttReleasePending = false;
"""
new_fields = """  bool _voicePttLocked = false;
  bool _voicePttCancelArmed = false;
  bool _voicePttReleasePending = false;
  Offset? _voicePttOrigin;
"""
if b.count(old_fields) != 1:
    raise SystemExit(f'ptt-origin-field: expected 1 match, found {b.count(old_fields)}')
b = b.replace(old_fields, new_fields, 1)

old_reset = """    _voicePttCancelArmed = false;
    _voicePttReleasePending = false;
  }

  Future<void> _submitVoiceReady() async {
"""
new_reset = """    _voicePttCancelArmed = false;
    _voicePttReleasePending = false;
    _voicePttOrigin = null;
  }

  Future<void> _submitVoiceReady() async {
"""
if b.count(old_reset) != 1:
    raise SystemExit(f'ptt-origin-reset: expected 1 match, found {b.count(old_reset)}')
b = b.replace(old_reset, new_reset, 1)

old_signature = """  void _beginVoicePtt(LongPressStartDetails _) {
"""
new_signature = """  void _beginVoicePtt(LongPressStartDetails details) {
"""
if b.count(old_signature) != 1:
    raise SystemExit(f'ptt-begin-signature: expected 1 match, found {b.count(old_signature)}')
b = b.replace(old_signature, new_signature, 1)

old_begin = """    _voicePttPending = true;
    _voicePttActive = false;
"""
new_begin = """    _voicePttOrigin = details.globalPosition;
    _voicePttPending = true;
    _voicePttActive = false;
"""
if b.count(old_begin) != 1:
    raise SystemExit(f'ptt-origin-begin: expected 1 match, found {b.count(old_begin)}')
b = b.replace(old_begin, new_begin, 1)

old_update = """  void _updateVoicePtt(LongPressMoveUpdateDetails details) {
    if (!_voicePttPending && !_voicePttActive) return;
    final offset = details.offsetFromOrigin;
    final cancel = offset.dx <= -56;
    final lock = !cancel && offset.dy <= -44;
    if (cancel == _voicePttCancelArmed && (!lock || _voicePttLocked)) return;
    setState(() {
      _voicePttCancelArmed = cancel;
      if (lock) _voicePttLocked = true;
    });
  }

  void _endVoicePtt(LongPressEndDetails _) {
    if (_voicePttPending && !_voicePttActive) {
      _voicePttReleasePending = true;
      return;
    }
    if (!_voicePttActive) return;
    if (_voicePttCancelArmed) {
      unawaited(_cancelVoiceInput());
    } else if (!_voicePttLocked) {
      unawaited(_finishVoiceInput());
    }
  }
"""
new_update = """  void _applyVoicePttOffset(Offset offset) {
    if (!_voicePttPending && !_voicePttActive) return;
    final cancel = offset.dx <= -56;
    final lock = !cancel && offset.dy <= -44;
    if (cancel == _voicePttCancelArmed && (!lock || _voicePttLocked)) return;
    setState(() {
      _voicePttCancelArmed = cancel;
      if (lock) _voicePttLocked = true;
    });
  }

  void _updateVoicePtt(LongPressMoveUpdateDetails details) {
    _applyVoicePttOffset(details.offsetFromOrigin);
  }

  void _handleVoicePttPointerMove(PointerMoveEvent event) {
    final origin = _voicePttOrigin;
    if (origin == null || (!_voicePttPending && !_voicePttActive)) return;
    _applyVoicePttOffset(event.position - origin);
  }

  void _completeVoicePttGesture() {
    if (_voicePttPending && !_voicePttActive) {
      _voicePttReleasePending = true;
      return;
    }
    if (!_voicePttActive) return;
    if (_voicePttCancelArmed) {
      _voicePttActive = false;
      unawaited(_cancelVoiceInput());
    } else if (!_voicePttLocked) {
      _voicePttActive = false;
      unawaited(_finishVoiceInput());
    }
  }

  void _handleVoicePttPointerUp(PointerUpEvent _) {
    _completeVoicePttGesture();
  }

  void _endVoicePtt(LongPressEndDetails _) {
    _completeVoicePttGesture();
  }
"""
if b.count(old_update) != 1:
    raise SystemExit(f'ptt-pointer-continuity: expected 1 match, found {b.count(old_update)}')
b = b.replace(old_update, new_update, 1)

old_return = """    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
"""
new_return = """    return Listener(
      onPointerMove: _handleVoicePttPointerMove,
      onPointerUp: _handleVoicePttPointerUp,
      child: SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
"""
if b.count(old_return) != 1:
    raise SystemExit(f'ptt-listener-wrap: expected 1 match, found {b.count(old_return)}')
b = b.replace(old_return, new_return, 1)

old_tail = """      ),
    );
  }
}

class _QueuedInputBanner"""
new_tail = """      ),
      ),
    );
  }
}

class _QueuedInputBanner"""
if b.count(old_tail) != 1:
    raise SystemExit(f'ptt-listener-close: expected 1 match, found {b.count(old_tail)}')
b = b.replace(old_tail, new_tail, 1)
bar.write_text(b, encoding='utf-8')

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
print('Voice shell regression and PTT continuity fixes applied')
