import 'story_reference_analysis_parser.dart';

/// Rejects derived profiles that appear to copy distinctive source wording.
///
/// This is a local post-check, not a semantic copyright classifier. It catches
/// accidental verbatim carry-over before a profile becomes callable.
final class StoryReferenceLeakGuard {
  const StoryReferenceLeakGuard({
    this.cjkWindow = 12,
    this.wordWindow = 6,
  });

  final int cjkWindow;
  final int wordWindow;

  StoryReferenceLeakCheck check({
    required String sourceText,
    required StoryReferenceAnalysisSnapshot analysis,
  }) {
    final source = _normalize(sourceText);
    if (source.isEmpty) return const StoryReferenceLeakCheck.safe();

    final cjkNgrams = _cjkNgrams(source, cjkWindow);
    final wordNgrams = _wordNgrams(source, wordWindow);
    for (final field in analysis.allTextFields) {
      final candidate = _normalize(field);
      if (candidate.isEmpty) continue;

      final cjkMatch = _firstCjkOverlap(candidate, cjkNgrams, cjkWindow);
      if (cjkMatch != null) {
        return StoryReferenceLeakCheck.blocked(
          reasonCode: 'source_phrase_overlap_cjk',
          matchedFragment: cjkMatch,
        );
      }

      final wordMatch = _firstWordOverlap(candidate, wordNgrams, wordWindow);
      if (wordMatch != null) {
        return StoryReferenceLeakCheck.blocked(
          reasonCode: 'source_phrase_overlap_words',
          matchedFragment: wordMatch,
        );
      }
    }
    return const StoryReferenceLeakCheck.safe();
  }
}

final class StoryReferenceLeakCheck {
  const StoryReferenceLeakCheck.safe()
    : blocked = false,
      reasonCode = null,
      matchedFragment = null;

  const StoryReferenceLeakCheck.blocked({
    required this.reasonCode,
    required this.matchedFragment,
  }) : blocked = true;

  final bool blocked;
  final String? reasonCode;

  /// Diagnostic only. Do not persist or send this fragment to the Story model.
  final String? matchedFragment;
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[“”"‘’`]+'), '')
    .trim();

Set<String> _cjkNgrams(String source, int window) {
  if (window <= 0) return const <String>{};
  final compact = source.replaceAll(RegExp(r'\s+'), '');
  final runes = compact.runes.toList(growable: false);
  if (runes.length < window) return const <String>{};
  final result = <String>{};
  for (var i = 0; i <= runes.length - window; i++) {
    final fragment = String.fromCharCodes(runes.sublist(i, i + window));
    if (_containsCjk(fragment)) result.add(fragment);
  }
  return result;
}

Set<String> _wordNgrams(String source, int window) {
  if (window <= 0) return const <String>{};
  final words = source
      .split(RegExp(r'[^\p{L}\p{N}_]+', unicode: true))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.length < window) return const <String>{};
  return {
    for (var i = 0; i <= words.length - window; i++)
      words.sublist(i, i + window).join(' '),
  };
}

String? _firstCjkOverlap(
  String candidate,
  Set<String> sourceNgrams,
  int window,
) {
  if (sourceNgrams.isEmpty || window <= 0) return null;
  final compact = candidate.replaceAll(RegExp(r'\s+'), '');
  final runes = compact.runes.toList(growable: false);
  if (runes.length < window) return null;
  for (var i = 0; i <= runes.length - window; i++) {
    final fragment = String.fromCharCodes(runes.sublist(i, i + window));
    if (_containsCjk(fragment) && sourceNgrams.contains(fragment)) {
      return fragment;
    }
  }
  return null;
}

String? _firstWordOverlap(
  String candidate,
  Set<String> sourceNgrams,
  int window,
) {
  if (sourceNgrams.isEmpty || window <= 0) return null;
  final words = candidate
      .split(RegExp(r'[^\p{L}\p{N}_]+', unicode: true))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.length < window) return null;
  for (var i = 0; i <= words.length - window; i++) {
    final fragment = words.sublist(i, i + window).join(' ');
    if (sourceNgrams.contains(fragment)) return fragment;
  }
  return null;
}

bool _containsCjk(String value) => RegExp(
  r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]',
).hasMatch(value);
