import 'story_response_parser.dart';

/// Removes Kelivo's machine-only Story trailer from user-visible text.
///
/// This deliberately recognizes only Kelivo's own marker. An incomplete trailer
/// is hidden as soon as its start marker appears, so streaming or an interrupted
/// response cannot leak protocol JSON into Chat/Story renderers.
String stripKelivoStoryProtocol(String input) {
  final start = input.indexOf(storyEventsCommentStart);
  if (start < 0) return input;

  final end = input.indexOf(storyEventsCommentEnd, start);
  if (end < 0) return input.substring(0, start).trimRight();

  final after = end + storyEventsCommentEnd.length;
  return (input.substring(0, start) + input.substring(after)).trimRight();
}

bool containsKelivoStoryProtocol(String input) =>
    input.contains(storyEventsCommentStart);
