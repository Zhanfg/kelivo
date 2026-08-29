from pathlib import Path

path = Path('lib/features/home/widgets/chat_input_bar.dart')
text = path.read_text(encoding='utf-8')

old_model = """      StepAsrOptions value => value.model,
    };
  }
"""
new_model = """      StepAsrOptions value => value.model,
      _ => service.name,
    };
  }
"""
if text.count(old_model) != 1:
    raise SystemExit(f'voice-model-switch: expected 1 match, found {text.count(old_model)}')
text = text.replace(old_model, new_model, 1)

old_language = """      StepAsrOptions value => value.language,
    };
    if (raw.trim().isEmpty || raw.trim().toLowerCase() == 'auto') {
"""
new_language = """      StepAsrOptions value => value.language,
      _ => '',
    };
    if (raw.trim().isEmpty || raw.trim().toLowerCase() == 'auto') {
"""
if text.count(old_language) != 1:
    raise SystemExit(f'voice-language-switch: expected 1 match, found {text.count(old_language)}')
text = text.replace(old_language, new_language, 1)

old_reasoning = """                                                        onLongPress:
                                                            _composerLocked
                                                            ? null
                                                            : widget
                                                                  .onSelectModel,
                                                        childBuilder:
"""
new_reasoning = """                                                        onLongPress:
                                                            _composerLocked
                                                            ? null
                                                            : widget
                                                                  .onSelectModel,
                                                        allowLongPressOnDesktop:
                                                            isMobileLayout,
                                                        childBuilder:
"""
if text.count(old_reasoning) != 1:
    raise SystemExit(f'reasoning-longpress-usage: expected 1 match, found {text.count(old_reasoning)}')
text = text.replace(old_reasoning, new_reasoning, 1)

path.write_text(text, encoding='utf-8')
print('Voice shell analyzer fix applied')
