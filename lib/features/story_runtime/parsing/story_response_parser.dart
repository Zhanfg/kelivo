import 'dart:convert';

import '../models/story_runtime_models.dart';

const String storyEventsCommentStart = '<!--KELIVO_STORY_EVENTS';
const String storyEventsCommentEnd = 'KELIVO_STORY_EVENTS-->';

final class StoryParsedResponse {
  const StoryParsedResponse({required this.visibleText, required this.turn});

  final String visibleText;
  final StoryTurn turn;
}

/// Strict parser for Story Mode's stable v1 response envelope.
///
/// The parser is deliberately defensive because model output is untrusted UI
/// input. It preserves event order, bounds payload size and rejects actor/type
/// combinations that could blur the second-person SELF boundary.
final class StoryResponseParser {
  const StoryResponseParser({
    this.maxEvents = 64,
    this.maxTextSpansPerEvent = 32,
    this.maxChoicesPerSet = 16,
    this.maxSpanChars = 8192,
    this.maxTotalTextChars = 65536,
    this.maxTimeout = const Duration(minutes: 5),
  });

  final int maxEvents;
  final int maxTextSpansPerEvent;
  final int maxChoicesPerSet;
  final int maxSpanChars;
  final int maxTotalTextChars;
  final Duration maxTimeout;

  /// Parses a normal reader-visible story followed by a hidden HTML comment
  /// carrying the structured event envelope.
  ///
  /// Markdown renderers hide the comment while streaming. Once finalized the
  /// host removes it from ChatMessage.content and stores [turn] in a sidecar.
  StoryParsedResponse parseEmbedded(String raw, {required String turnId}) {
    final end = raw.lastIndexOf(storyEventsCommentEnd);
    final start = end < 0
        ? -1
        : raw.lastIndexOf(storyEventsCommentStart, end);
    if (start < 0 || end < 0 || end < start) {
      throw const StoryResponseParseException('embedded_events_missing');
    }
    final jsonStart = start + storyEventsCommentStart.length;
    final eventJson = raw.substring(jsonStart, end).trim();
    if (eventJson.isEmpty) {
      throw const StoryResponseParseException('embedded_events_empty');
    }
    final trailing = raw.substring(end + storyEventsCommentEnd.length).trim();
    if (trailing.isNotEmpty) {
      throw const StoryResponseParseException('content_after_embedded_events');
    }
    final visible = raw.substring(0, start).trimRight();
    if (visible.trim().isEmpty) {
      throw const StoryResponseParseException('visible_story_missing');
    }
    return StoryParsedResponse(
      visibleText: visible,
      turn: parse(eventJson, turnId: turnId),
    );
  }

  StoryTurn parse(String raw, {required String turnId}) {
    final normalizedTurnId = turnId.trim();
    if (normalizedTurnId.isEmpty) {
      throw const StoryResponseParseException('invalid_turn_id');
    }

    final source = _stripJsonFence(raw);
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw StoryResponseParseException('invalid_json', detail: error.message);
    }

    final root = _asStringMap(decoded, code: 'root_not_object');
    final version = root['version'];
    if (version is! num ||
        version.isNaN ||
        version.isInfinite ||
        version != 1) {
      throw const StoryResponseParseException('unsupported_version');
    }

    final rawEvents = root['events'];
    if (rawEvents is! List || rawEvents.isEmpty) {
      throw const StoryResponseParseException('events_missing');
    }
    if (rawEvents.length > maxEvents) {
      throw const StoryResponseParseException('too_many_events');
    }

    var totalTextChars = 0;
    final events = <StoryEvent>[];
    for (var index = 0; index < rawEvents.length; index++) {
      final eventMap = _asStringMap(rawEvents[index], code: 'event_not_object');
      final parsed = _parseEvent(
        eventMap,
        eventId: '${normalizedTurnId}_e$index',
        onTextChars: (count) {
          totalTextChars += count;
          if (totalTextChars > maxTotalTextChars) {
            throw const StoryResponseParseException('text_budget_exceeded');
          }
        },
      );
      events.add(parsed);
    }

    return StoryTurn(id: normalizedTurnId, events: List.unmodifiable(events));
  }

  StoryEvent _parseEvent(
    Map<String, Object?> map, {
    required String eventId,
    required void Function(int count) onTextChars,
  }) {
    final type = _parseEventType(_requiredString(map, 'type'));
    final actor = _parseActor(map['actor']);
    _validateActorForType(type, actor);

    final text = _parseTextSpans(map['text'], onTextChars: onTextChars);
    final choices = _parseChoices(map['choices']);

    if (type == StoryEventType.choiceSet && choices.isEmpty) {
      throw const StoryResponseParseException('choice_set_without_choices');
    }
    if (type != StoryEventType.choiceSet && choices.isNotEmpty) {
      throw const StoryResponseParseException('choices_on_non_choice_event');
    }

    final timeout = _parseTimeout(map['timeout_ms']);
    final timeoutActionId = _optionalTrimmedString(map['timeout_action_id']);

    if (timeoutActionId != null && timeout == null) {
      throw const StoryResponseParseException('timeout_action_without_timeout');
    }
    if (timeoutActionId != null &&
        choices.isNotEmpty &&
        timeoutActionId != 'silence' &&
        !choices.any((choice) => choice.id == timeoutActionId)) {
      throw const StoryResponseParseException('unknown_timeout_action');
    }

    final metadata = _optionalObject(map['metadata'], code: 'invalid_metadata');

    return StoryEvent(
      id: eventId,
      type: type,
      actor: actor,
      text: List.unmodifiable(text),
      choices: List.unmodifiable(choices),
      timeout: timeout,
      timeoutActionId: timeoutActionId,
      metadata: Map.unmodifiable(metadata),
    );
  }

  StoryActorRef _parseActor(Object? value) {
    final actor = _asStringMap(value, code: 'actor_not_object');
    final type = _requiredString(actor, 'type');
    final characterId = _optionalTrimmedString(actor['character_id']);

    switch (type) {
      case 'self':
        if (characterId != null) {
          throw const StoryResponseParseException('self_has_character_id');
        }
        return const StoryActorRef.self();
      case 'world':
        if (characterId != null) {
          throw const StoryResponseParseException('world_has_character_id');
        }
        return const StoryActorRef.world();
      case 'character':
        if (characterId == null) {
          throw const StoryResponseParseException('character_id_missing');
        }
        return StoryActorRef.character(characterId);
      default:
        throw StoryResponseParseException('unknown_actor_type', detail: type);
    }
  }

  List<StoryTextSpan> _parseTextSpans(
    Object? value, {
    required void Function(int count) onTextChars,
  }) {
    if (value == null) return const <StoryTextSpan>[];
    if (value is! List) {
      throw const StoryResponseParseException('text_not_array');
    }
    if (value.length > maxTextSpansPerEvent) {
      throw const StoryResponseParseException('too_many_text_spans');
    }

    final spans = <StoryTextSpan>[];
    for (final item in value) {
      final map = _asStringMap(item, code: 'text_span_not_object');
      final text = _requiredString(map, 'text', trim: false);
      if (text.length > maxSpanChars) {
        throw const StoryResponseParseException('text_span_too_large');
      }
      onTextChars(text.length);

      spans.add(
        StoryTextSpan(
          text,
          effect: _parseTextEffect(_optionalTrimmedString(map['effect'])),
          decoration: _parseTextDecoration(
            _optionalTrimmedString(map['decoration']),
          ),
          motion: _parseTextMotion(_optionalTrimmedString(map['motion'])),
        ),
      );
    }
    return spans;
  }

  List<StoryChoice> _parseChoices(Object? value) {
    if (value == null) return const <StoryChoice>[];
    if (value is! List) {
      throw const StoryResponseParseException('choices_not_array');
    }
    if (value.length > maxChoicesPerSet) {
      throw const StoryResponseParseException('too_many_choices');
    }

    final ids = <String>{};
    final choices = <StoryChoice>[];
    for (final item in value) {
      final map = _asStringMap(item, code: 'choice_not_object');
      final id = _requiredString(map, 'id');
      if (!ids.add(id)) {
        throw const StoryResponseParseException('duplicate_choice_id');
      }
      final label = _requiredString(map, 'label');
      final submitText = _optionalTrimmedString(map['submit_text']);
      final metadata = _optionalObject(
        map['metadata'],
        code: 'invalid_choice_metadata',
      );
      choices.add(
        StoryChoice(
          id: id,
          label: label,
          submitText: submitText,
          metadata: Map.unmodifiable(metadata),
        ),
      );
    }
    return choices;
  }

  Duration? _parseTimeout(Object? value) {
    if (value == null) return null;
    if (value is! num || value.isNaN || value.isInfinite) {
      throw const StoryResponseParseException('invalid_timeout');
    }
    final millis = value.toInt();
    if (value != millis || millis <= 0 || millis > maxTimeout.inMilliseconds) {
      throw const StoryResponseParseException('timeout_out_of_range');
    }
    return Duration(milliseconds: millis);
  }
}

final class StoryResponseParseException implements Exception {
  const StoryResponseParseException(this.code, {this.detail});

  final String code;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StoryResponseParseException($code)'
      : 'StoryResponseParseException($code: $detail)';
}

StoryEventType _parseEventType(String value) => switch (value) {
  'narration' => StoryEventType.narration,
  'dialogue' => StoryEventType.dialogue,
  'action' => StoryEventType.action,
  'expression' => StoryEventType.expression,
  'scene_transition' => StoryEventType.sceneTransition,
  'choice_set' => StoryEventType.choiceSet,
  'runtime_notice' => StoryEventType.runtimeNotice,
  _ => throw StoryResponseParseException('unknown_event_type', detail: value),
};

void _validateActorForType(StoryEventType type, StoryActorRef actor) {
  switch (type) {
    case StoryEventType.narration:
    case StoryEventType.sceneTransition:
    case StoryEventType.runtimeNotice:
      if (!actor.isWorld) {
        throw const StoryResponseParseException('world_event_actor_mismatch');
      }
    case StoryEventType.dialogue:
    case StoryEventType.expression:
    case StoryEventType.action:
      if (actor.isWorld) {
        throw const StoryResponseParseException('actor_event_mismatch');
      }
    case StoryEventType.choiceSet:
      if (!actor.isSelf) {
        throw const StoryResponseParseException('choice_actor_mismatch');
      }
  }
}

StoryTextEffect _parseTextEffect(String? value) => switch (value) {
  null || 'normal' => StoryTextEffect.normal,
  'emphasis' => StoryTextEffect.emphasis,
  'horror' => StoryTextEffect.horror,
  'warning' => StoryTextEffect.warning,
  'whisper' => StoryTextEffect.whisper,
  'distorted' => StoryTextEffect.distorted,
  'corrupted' => StoryTextEffect.corrupted,
  'memory' => StoryTextEffect.memory,
  'unknown' => StoryTextEffect.unknown,
  _ => StoryTextEffect.unknown,
};

StoryTextDecoration _parseTextDecoration(String? value) => switch (value) {
  null || 'none' => StoryTextDecoration.none,
  'underline' => StoryTextDecoration.underline,
  'wavy_underline' => StoryTextDecoration.wavyUnderline,
  'strikethrough' => StoryTextDecoration.strikethrough,
  _ => StoryTextDecoration.none,
};

StoryTextMotion _parseTextMotion(String? value) => switch (value) {
  null || 'none' => StoryTextMotion.none,
  'jitter' => StoryTextMotion.jitter,
  'flicker' => StoryTextMotion.flicker,
  'glitch' => StoryTextMotion.glitch,
  _ => StoryTextMotion.none,
};

Map<String, Object?> _asStringMap(Object? value, {required String code}) {
  if (value is! Map) throw StoryResponseParseException(code);
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw StoryResponseParseException(code);
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _optionalObject(Object? value, {required String code}) {
  if (value == null) return const <String, Object?>{};
  return _asStringMap(value, code: code);
}

String _requiredString(
  Map<String, Object?> map,
  String key, {
  bool trim = true,
}) {
  final value = map[key];
  if (value is! String) {
    throw StoryResponseParseException('missing_$key');
  }
  final result = trim ? value.trim() : value;
  if (result.isEmpty) {
    throw StoryResponseParseException('missing_$key');
  }
  return result;
}

String? _optionalTrimmedString(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const StoryResponseParseException('invalid_optional_string');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _stripJsonFence(String raw) {
  var source = raw.trim();
  if (!source.startsWith('```')) return source;

  final firstLineEnd = source.indexOf('\n');
  if (firstLineEnd == -1 || !source.endsWith('```')) return source;

  final fence = source.substring(0, firstLineEnd).trim().toLowerCase();
  if (fence != '```' && fence != '```json') return source;
  source = source.substring(firstLineEnd + 1, source.length - 3).trim();
  return source;
}
