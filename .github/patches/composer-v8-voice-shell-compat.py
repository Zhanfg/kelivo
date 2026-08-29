from pathlib import Path

path = Path('lib/features/home/widgets/chat_input_bar.dart')
text = path.read_text(encoding='utf-8')

current = """                                            if (showVoiceInput) ...[
                                              _CompactIconButton(
                                                tooltip: AppLocalizations.of(
                                                  context,
                                                )!.chatInputBarVoiceInputTooltip,
                                                icon: Lucide.Mic,
                                                active: _voiceSettingsExpanded,
                                                onTap:
                                                    _composerLocked ||
                                                        widget.loading
                                                    ? null
                                                    : settings
                                                          .asrServices
                                                          .isEmpty
                                                    ? () => unawaited(
                                                        _openVoiceServicesSettings(),
                                                      )
                                                    : selectedVoiceServiceUsable
                                                    ? () => unawaited(
                                                        _startVoiceInput(),
                                                      )
                                                    : _toggleInlineVoiceSettings,
                                                onLongPress:
                                                    _composerLocked ||
                                                        widget.loading
                                                    ? null
                                                    : settings
                                                          .asrServices
                                                          .isEmpty
                                                    ? () => unawaited(
                                                        _openVoiceServicesSettings(),
                                                      )
                                                    : _toggleInlineVoiceSettings,
                                                allowLongPressOnDesktop:
                                                    isMobileLayout,
                                              ),
                                              const SizedBox(width: 8),
                                            ],
"""
legacy_anchor = """                                            if (showVoiceInput) ...[
                                              _CompactIconButton(
                                                tooltip: AppLocalizations.of(
                                                  context,
                                                )!.chatInputBarVoiceInputTooltip,
                                                icon: Lucide.Mic,
                                                active: _voiceSettingsExpanded,
                                                onTap:
                                                    _composerLocked ||
                                                        widget.loading
                                                    ? null
                                                    : selectedVoiceServiceUsable
                                                    ? () => unawaited(
                                                        _startVoiceInput(),
                                                      )
                                                    : _toggleInlineVoiceSettings,
                                                onLongPress:
                                                    _composerLocked ||
                                                        widget.loading
                                                    ? null
                                                    : _toggleInlineVoiceSettings,
                                                allowLongPressOnDesktop:
                                                    isMobileLayout,
                                              ),
                                              const SizedBox(width: 8),
                                            ],
"""
if text.count(current) != 1:
    raise SystemExit(f'voice-mic-compat: expected 1 match, found {text.count(current)}')
path.write_text(text.replace(current, legacy_anchor, 1), encoding='utf-8')
print('Voice shell compatibility anchor applied')
