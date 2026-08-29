import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Context supplied to a Story voice without changing the audible text.
///
/// The current utterance is the full logical speaking unit, not Kelivo's
/// internal TTS chunk. Kelivo remains free to split/prefetch/seek that utterance
/// with its native TtsProvider while every MiMo chunk receives the same stable
/// delivery context.
final class StoryVoiceContextWindow {
  const StoryVoiceContextWindow({
    required this.current,
    this.previous,
    this.next,
    this.sceneHint,
  });

  final String? previous;
  final String current;
  final String? next;
  final String? sceneHint;

  bool get isEmpty =>
      current.trim().isEmpty &&
      (previous?.trim().isEmpty ?? true) &&
      (next?.trim().isEmpty ?? true) &&
      (sceneHint?.trim().isEmpty ?? true);
}

final class StoryVoiceContextCompiler {
  const StoryVoiceContextCompiler._();

  static String instruction(StoryVoiceContextWindow? window) {
    if (window == null || window.isEmpty) return '';
    final parts = <String>[];
    final previous = _bounded(window.previous, 600);
    final current = _bounded(window.current, 1200);
    final next = _bounded(window.next, 600);
    final scene = _bounded(window.sceneHint, 400);
    if (scene != null) parts.add('Scene context: $scene');
    if (previous != null) {
      parts.add('Previous spoken context (do not repeat): $previous');
    }
    if (current != null) {
      parts.add(
        'Current full utterance for delivery context (speak only the supplied synthesis text): $current',
      );
    }
    if (next != null) {
      parts.add('Following context (do not speak yet): $next');
    }
    parts.add(
      'Use the surrounding context only to keep emotion, cadence and continuity natural. Never speak the context labels or repeat neighboring text.',
    );
    return parts.join(' ');
  }

  static String cacheIdentity({
    required String serviceId,
    required String model,
    required String voiceId,
    required String persona,
    required String deliveryInstruction,
    StoryVoiceContextWindow? context,
  }) {
    final canonical = jsonEncode(<String, Object?>{
      'service': serviceId.trim(),
      'model': model.trim(),
      'voice': voiceId.trim(),
      'persona': persona.trim(),
      'delivery': deliveryInstruction.trim(),
      'previous': context?.previous?.trim() ?? '',
      'current': context?.current.trim() ?? '',
      'next': context?.next?.trim() ?? '',
      'scene': context?.sceneHint?.trim() ?? '',
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

String? _bounded(String? value, int maxChars) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}
