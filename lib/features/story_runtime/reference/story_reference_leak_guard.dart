import 'story_reference_analysis_parser.dart';

/// Rejects derived profiles that appear to copy distinctive source wording.
///
/// This is a local post-check, not a semantic copyright classifier. It catches
/// accidental verbatim carry-over before a profile becomes callable without
/// building an O(book-length) set of substring objects in memory.
final class StoryReferenceLeakGuard {
  const StoryReferenceLeakGuard({
    this.eastAsianWindow = 16,
    this.wordWindow = 8,
  });

  final int eastAsianWindow;
  final int wordWindow;

  StoryReferenceLeakCheck check({
    required String sourceText,
    required StoryReferenceAnalysisSnapshot analysis,
  }) {
    final source = _normalize(sourceText);
    if (source.isEmpty) return const StoryReferenceLeakCheck.safe();
    final compactSource = source.replaceAll(RegExp(r'\s+'), '');
    final sourceWords = ' ${_latinWords(source).join(' ')} ';

    for (final field in analysis.allTextFields) {
      final candidate = _normalize(field);
      if (candidate.isEmpty) continue;

      final exact = _exactCandidateOverlap(candidate, source);
      if (exact != null) {
        return StoryReferenceLeakCheck.blocked(
          reasonCode: 'source_phrase_overlap_exact',
          matchedFragment: exact,
        );
      }

      final eastAsianMatch = _sampledEastAsianOverlap(
        candidate,
        compactSource,
        eastAsianWindow,
      );
      if (eastAsianMatch != null) {
        return StoryReferenceLeakCheck.blocked(
          reasonCode: 'source_phrase_overlap_east_asian',
          matchedFragment: eastAsianMatch,
        );
      }

      final wordMatch = _sampledWordOverlap(candidate, sourceWords, wordWindow);
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

String? _exactCandidateOverlap(String candidate, String source) {
  final runeCount = candidate.runes.length;
  final wordCount = _latinWords(candidate).length;
  if (runeCount >= 24 || wordCount >= 10) {
    if (source.contains(candidate)) return candidate;
  }
  return null;
}

String? _sampledEastAsianOverlap(
  String candidate,
  String compactSource,
  int window,
) {
  if (window <= 0) return null;
  final compact = candidate.replaceAll(RegExp(r'\s+'), '');
  final runes = compact.runes.toList(growable: false);
  if (runes.length < window || !_containsEastAsian(compact)) return null;

  for (final start in _sampleStarts(runes.length, window)) {
    final fragment = String.fromCharCodes(runes.sublist(start, start + window));
    if (_containsEastAsian(fragment) && compactSource.contains(fragment)) {
      return fragment;
    }
  }
  return null;
}

String? _sampledWordOverlap(
  String candidate,
  String sourceWords,
  int window,
) {
  if (window <= 0) return null;
  final words = _latinWords(candidate);
  if (words.length < window) return null;
  for (final start in _sampleStarts(words.length, window)) {
    final fragment = words.sublist(start, start + window).join(' ');
    if (sourceWords.contains(' $fragment ')) return fragment;
  }
  return null;
}

List<int> _sampleStarts(int length, int window) {
  final maxStart = length - window;
  if (maxStart <= 0) return const <int>[0];
  final middle = maxStart ~/ 2;
  final values = <int>{0, middle, maxStart}.toList(growable: false)..sort();
  return values;
}

List<String> _latinWords(String value) => value
    .replaceAll(RegExp(r'[^a-z0-9_]+'), ' ')
    .split(' ')
    .where((word) => word.isNotEmpty)
    .toList(growable: false);

bool _containsEastAsian(String value) => RegExp(
  r'[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uAC00-\uD7AF\uF900-\uFAFF]',
).hasMatch(value);
