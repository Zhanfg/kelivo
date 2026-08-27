import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'story_reference_models.dart';

/// Paragraph-aware deterministic chunking for reference-text analysis.
final class StoryReferenceChunker {
  const StoryReferenceChunker({
    this.targetChars = 10000,
    this.maxChars = 14000,
    this.overlapChars = 700,
  }) : assert(targetChars > 0),
       assert(maxChars >= targetChars),
       assert(overlapChars >= 0 && overlapChars < targetChars);

  final int targetChars;
  final int maxChars;
  final int overlapChars;

  List<StoryReferenceChunk> chunk({
    required String documentId,
    required String text,
  }) {
    final normalized = normalizeReferenceText(text);
    if (normalized.isEmpty) return const <StoryReferenceChunk>[];

    final paragraphs = normalized
        .split(RegExp(r'\n{2,}'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList(growable: false);

    final blocks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) blocks.add(value);
      buffer.clear();
    }

    for (final paragraph in paragraphs) {
      if (paragraph.length > maxChars) {
        flush();
        blocks.addAll(_splitOversizeParagraph(paragraph));
        continue;
      }
      final separator = buffer.isEmpty ? 0 : 2;
      if (buffer.length + separator + paragraph.length > targetChars &&
          buffer.isNotEmpty) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(paragraph);
      if (buffer.length >= maxChars) flush();
    }
    flush();

    final withOverlap = <String>[];
    for (var i = 0; i < blocks.length; i++) {
      final current = blocks[i];
      if (i == 0 || overlapChars == 0) {
        withOverlap.add(current);
        continue;
      }
      final previousTail = _safeTail(blocks[i - 1], overlapChars);
      final merged = previousTail.isEmpty
          ? current
          : '$previousTail\n\n$current';
      withOverlap.add(
        merged.length <= maxChars ? merged : _safeTail(merged, maxChars),
      );
    }

    return List.unmodifiable([
      for (var index = 0; index < withOverlap.length; index++)
        () {
          final chunkText = withOverlap[index];
          final hash = sha256.convert(utf8.encode(chunkText)).toString();
          return StoryReferenceChunk(
            id: '$documentId:$index:${hash.substring(0, 12)}',
            documentId: documentId,
            index: index,
            text: chunkText,
            contentHash: hash,
          );
        }(),
    ]);
  }

  List<String> _splitOversizeParagraph(String paragraph) {
    final sentences = paragraph.split(
      RegExp(r'(?<=[。！？!?\.])\s*'),
    );
    final result = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) result.add(value);
      buffer.clear();
    }

    for (final sentence in sentences) {
      final value = sentence.trim();
      if (value.isEmpty) continue;
      if (value.length > maxChars) {
        flush();
        var start = 0;
        while (start < value.length) {
          final end = (start + maxChars).clamp(0, value.length);
          result.add(value.substring(start, end));
          start = end;
        }
        continue;
      }
      final separator = buffer.isEmpty ? 0 : 1;
      if (buffer.length + separator + value.length > targetChars &&
          buffer.isNotEmpty) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(value);
    }
    flush();
    return result;
  }
}

String normalizeReferenceText(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[\t\u00A0]+'), ' ')
      .replaceAll(RegExp(r' +\n'), '\n')
      .replaceAll(RegExp(r'\n +'), '\n')
      .replaceAll(RegExp(r'\n{4,}'), '\n\n\n')
      .trim();
}

String _safeTail(String value, int maxChars) {
  if (maxChars <= 0 || value.isEmpty) return '';
  if (value.length <= maxChars) return value;
  var start = value.length - maxChars;
  if (start > 0 &&
      start < value.length &&
      _isLowSurrogate(value.codeUnitAt(start)) &&
      _isHighSurrogate(value.codeUnitAt(start - 1))) {
    start++;
  }
  return value.substring(start);
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
