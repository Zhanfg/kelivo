import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../../../core/services/chat/document_text_extractor.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'story_reference_chunker.dart';

final class StoryReferenceExtractedText {
  const StoryReferenceExtractedText({
    required this.text,
    required this.mime,
    this.suggestedTitle,
  });

  final String text;
  final String mime;
  final String? suggestedTitle;
}

/// Extracts common novel/document formats for Reference Library import.
///
/// TXT/Markdown/PDF/DOCX reuse Kelivo's existing document extractor. EPUB gets
/// a dedicated spine-aware reader so a zipped book is never decoded as plain
/// UTF-8 bytes.
final class StoryReferenceTextExtractor {
  const StoryReferenceTextExtractor({
    this.maxSourceBytes = 256 * 1024 * 1024,
    this.maxExtractedChars = 50 * 1024 * 1024,
  });

  final int maxSourceBytes;
  final int maxExtractedChars;

  Future<StoryReferenceExtractedText> extract({
    required String path,
    String? mime,
  }) async {
    final resolved = SandboxPathResolver.resolveForIo(path);
    if (resolved == null) {
      throw const StoryReferenceImportException('source_path_unavailable');
    }
    final file = File(resolved);
    if (!await file.exists()) {
      throw const StoryReferenceImportException('source_file_missing');
    }
    final stat = await file.stat();
    if (stat.size > maxSourceBytes) {
      throw const StoryReferenceImportException('source_file_too_large');
    }

    final effectiveMime = _resolveMime(resolved, mime);
    final StoryReferenceExtractedText extracted;
    if (effectiveMime == 'application/epub+zip') {
      extracted = await compute(_extractEpubTask, resolved);
    } else {
      final text = await DocumentTextExtractor.extractResolved(
        path: resolved,
        mime: effectiveMime,
      );
      extracted = StoryReferenceExtractedText(
        text: text,
        mime: effectiveMime,
        suggestedTitle: _fileStem(resolved),
      );
    }

    final normalized = normalizeReferenceText(extracted.text);
    if (normalized.isEmpty || normalized.startsWith('[[')) {
      throw const StoryReferenceImportException('source_text_empty');
    }
    if (normalized.length > maxExtractedChars) {
      throw const StoryReferenceImportException('extracted_text_too_large');
    }
    return StoryReferenceExtractedText(
      text: normalized,
      mime: extracted.mime,
      suggestedTitle: extracted.suggestedTitle,
    );
  }
}

final class StoryReferenceImportException implements Exception {
  const StoryReferenceImportException(this.code, {this.detail});

  final String code;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StoryReferenceImportException($code)'
      : 'StoryReferenceImportException($code: $detail)';
}

StoryReferenceExtractedText _extractEpubTask(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final byName = <String, ArchiveFile>{
      for (final file in archive.files) _normalizeArchivePath(file.name): file,
    };

    final container = byName['META-INF/container.xml'];
    if (container == null) {
      throw const StoryReferenceImportException('epub_container_missing');
    }
    final containerXml = XmlDocument.parse(
      utf8.decode(_readArchiveBytes(container), allowMalformed: true),
    );
    final rootFile = containerXml.descendants
        .whereType<XmlElement>()
        .firstWhere(
          (element) => element.name.local == 'rootfile',
          orElse: () => throw const StoryReferenceImportException(
            'epub_rootfile_missing',
          ),
        );
    final opfPath = rootFile.getAttribute('full-path')?.trim();
    if (opfPath == null || opfPath.isEmpty) {
      throw const StoryReferenceImportException('epub_rootfile_missing');
    }
    final normalizedOpfPath = _normalizeArchivePath(opfPath);
    final opfFile = byName[normalizedOpfPath];
    if (opfFile == null) {
      throw const StoryReferenceImportException('epub_package_missing');
    }
    final opf = XmlDocument.parse(
      utf8.decode(_readArchiveBytes(opfFile), allowMalformed: true),
    );
    final opfDir = normalizedOpfPath.contains('/')
        ? normalizedOpfPath.substring(0, normalizedOpfPath.lastIndexOf('/') + 1)
        : '';

    String? title;
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'title') {
        final value = element.innerText.trim();
        if (value.isNotEmpty) {
          title = value;
          break;
        }
      }
    }

    final manifest = <String, String>{};
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'item') continue;
      final id = element.getAttribute('id')?.trim();
      final href = element.getAttribute('href')?.trim();
      if (id == null || id.isEmpty || href == null || href.isEmpty) continue;
      manifest[id] = _normalizeArchivePath('$opfDir$href');
    }

    final spine = <String>[];
    for (final element in opf.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'itemref') continue;
      final idref = element.getAttribute('idref')?.trim();
      if (idref != null && idref.isNotEmpty) spine.add(idref);
    }

    final buffer = StringBuffer();
    final paths = spine.isNotEmpty
        ? [for (final id in spine) if (manifest[id] != null) manifest[id]!]
        : manifest.values.toList(growable: false);

    for (final itemPath in paths) {
      final entry = byName[itemPath];
      if (entry == null || !entry.isFile) continue;
      final raw = utf8.decode(
        _readArchiveBytes(entry),
        allowMalformed: true,
      );
      final text = _extractXhtmlText(raw);
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(text);
    }

    return StoryReferenceExtractedText(
      text: buffer.toString(),
      mime: 'application/epub+zip',
      suggestedTitle: title ?? _fileStem(path),
    );
  } on StoryReferenceImportException {
    rethrow;
  } catch (error) {
    throw StoryReferenceImportException(
      'epub_extract_failed',
      detail: error.toString(),
    );
  }
}

List<int> _readArchiveBytes(ArchiveFile file) {
  final bytes = file.readBytes();
  if (bytes == null) {
    throw StoryReferenceImportException(
      'epub_entry_unreadable',
      detail: file.name,
    );
  }
  return bytes;
}

String _extractXhtmlText(String raw) {
  try {
    final document = XmlDocument.parse(raw);
    const blockTags = <String>{
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'p',
      'blockquote',
      'li',
    };
    final parts = <String>[];
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (!blockTags.contains(element.name.local.toLowerCase())) continue;
      final text = element.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) parts.add(text);
    }
    if (parts.isNotEmpty) return parts.join('\n\n');
  } catch (_) {}

  // Some EPUBs contain HTML that is not strict XML. This fallback is used only
  // for text extraction and never executed as markup.
  return raw
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _resolveMime(String path, String? explicit) {
  final normalized = explicit?.trim().toLowerCase();
  if (normalized != null && normalized.isNotEmpty) {
    if (normalized == 'application/epub+zip') return normalized;
    if (normalized == 'application/pdf') return normalized;
    if (normalized ==
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
      return normalized;
    }
    if (normalized == 'application/msword') return normalized;
    if (normalized.startsWith('text/')) return normalized;
  }

  final lower = path.toLowerCase();
  if (lower.endsWith('.epub')) return 'application/epub+zip';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return 'text/markdown';
  }
  return 'text/plain';
}

String _normalizeArchivePath(String value) {
  final segments = <String>[];
  for (final raw in value.replaceAll('\\', '/').split('/')) {
    final segment = _safeDecodeComponent(raw).trim();
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

String _safeDecodeComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

String _fileStem(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return (dot > 0 ? name.substring(0, dot) : name).trim();
}
