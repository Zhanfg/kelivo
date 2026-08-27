import '../models/story_runtime_models.dart';
import 'story_response_parser.dart';

final class StoryReadableProjection {
  const StoryReadableProjection({
    required this.turn,
    required this.markdown,
  });

  final StoryTurn turn;
  final String markdown;
}

/// Parses a finalized Story response and projects it into readable Markdown.
///
/// This is deliberately presentation-light. It is the compatibility layer used
/// when the dedicated Story renderer is unavailable or a Story conversation is
/// converted back to normal Chat. Stable/internal character ids are never
/// printed as visible speaker names.
StoryReadableProjection? tryProjectStoryReadable(
  String raw, {
  required String turnId,
}) {
  try {
    final turn = const StoryResponseParser().parse(raw, turnId: turnId);
    return StoryReadableProjection(
      turn: turn,
      markdown: storyTurnToReadableMarkdown(turn),
    );
  } on StoryResponseParseException {
    return null;
  } on FormatException {
    return null;
  }
}

/// Returns text safe for Kelivo's existing assistant Markdown renderer.
///
/// When a streaming payload is recognizably the beginning of Story JSON but is
/// not complete enough to parse, an empty string is returned so protocol JSON
/// does not flash in the chat bubble. Non-Story text is returned unchanged.
String projectStoryReadableOrOriginal(
  String raw, {
  required String turnId,
  bool streaming = false,
}) {
  final projected = tryProjectStoryReadable(raw, turnId: turnId);
  if (projected != null) return projected.markdown;
  if (streaming && looksLikeStoryEnvelopePrefix(raw)) return '';
  return raw;
}

bool looksLikeStoryEnvelopePrefix(String raw) {
  var source = raw.trimLeft();
  if (source.startsWith('```json')) {
    source = source.substring('```json'.length).trimLeft();
  } else if (source.startsWith('```')) {
    source = source.substring(3).trimLeft();
  }
  if (!source.startsWith('{')) return false;
  final compact = source.replaceAll(RegExp(r'\s+'), '');
  if (compact.startsWith('{"version":1,"events"')) return true;
  const canonical = '{"version":1,"events":[';
  if (canonical.startsWith(compact) && compact.length >= 5) return true;
  return false;
}

String storyTurnToReadableMarkdown(StoryTurn turn) {
  final blocks = <String>[];
  for (final event in turn.events) {
    final text = _eventText(event);
    switch (event.type) {
      case StoryEventType.narration:
        if (text.isNotEmpty) blocks.add(text);
      case StoryEventType.dialogue:
        if (text.isEmpty) continue;
        final displayName = _visibleActorName(event);
        if (displayName == null) {
          blocks.add('> $text');
        } else {
          blocks.add('> **${_escapeMarkdown(displayName)}**\n>\n> $text');
        }
      case StoryEventType.action:
      case StoryEventType.expression:
        if (text.isNotEmpty) blocks.add('*$text*');
      case StoryEventType.sceneTransition:
        if (text.isNotEmpty) blocks.add('---\n\n*$text*\n\n---');
      case StoryEventType.choiceSet:
        if (event.choices.isNotEmpty) {
          blocks.add(
            event.choices
                .map((choice) => '- **${_escapeMarkdown(choice.label)}**')
                .join('\n'),
          );
        }
      case StoryEventType.runtimeNotice:
        if (text.isNotEmpty) blocks.add('> ℹ️ $text');
    }
  }
  return blocks.join('\n\n').trim();
}

String _eventText(StoryEvent event) =>
    event.text.map(_spanMarkdown).join().trim();

String _spanMarkdown(StoryTextSpan span) {
  final escaped = _escapeMarkdown(span.text);
  var text = switch (span.effect) {
    StoryTextEffect.emphasis => '**$escaped**',
    StoryTextEffect.whisper || StoryTextEffect.memory => '*$escaped*',
    StoryTextEffect.horror ||
    StoryTextEffect.warning ||
    StoryTextEffect.distorted ||
    StoryTextEffect.corrupted => '**$escaped**',
    StoryTextEffect.normal || StoryTextEffect.unknown => escaped,
  };
  text = switch (span.decoration) {
    StoryTextDecoration.strikethrough => '~~$text~~',
    StoryTextDecoration.none ||
    StoryTextDecoration.underline ||
    StoryTextDecoration.wavyUnderline => text,
  };
  return text;
}

String? _visibleActorName(StoryEvent event) {
  if (event.actor.isWorld) return null;
  final metadata = event.metadata;
  for (final key in const <String>['display_name', 'speaker_name', 'name']) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  // Never surface characterId: it is runtime identity, not player-visible text.
  return event.actor.isSelf ? null : null;
}

String _escapeMarkdown(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('*', '\\*')
    .replaceAll('_', '\\_')
    .replaceAll('`', '\\`');
