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
    final previous = _bounded(window.previous, 220);
    final next = _bounded(window.next, 140);
    final scene = _bounded(window.sceneHint, 220);
    if (scene != null) parts.add('Scene context: $scene');
    if (previous != null) {
      parts.add('Previous spoken context (do not repeat): $previous');
    }
    if (next != null) {
      parts.add('Following context (do not speak yet): $next');
    }
    if (parts.isEmpty) return '';
    parts.add(
      'Use this hidden surrounding context only for emotion, cadence and continuity. Speak only the supplied synthesis text; never read or repeat the context.',
    );
    return parts.join(' ');
  }

  static StoryVoiceContextWindow forChunk({
    required List<String> chunks,
    required int index,
    StoryVoiceContextWindow? outerContext,
  }) {
    if (index < 0 || index >= chunks.length) {
      throw RangeError.index(index, chunks, 'index');
    }
    return StoryVoiceContextWindow(
      previous: index > 0 ? chunks[index - 1] : outerContext?.previous,
      current: chunks[index],
      next: index + 1 < chunks.length ? chunks[index + 1] : outerContext?.next,
      sceneHint: outerContext?.sceneHint,
    );
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
