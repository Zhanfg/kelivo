// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../utils/app_directories.dart';
import 'story_reference_chunker.dart';
import 'story_reference_models.dart';
import 'story_reference_store.dart';
import 'story_reference_text_extractor.dart';

typedef StoryReferenceRootResolver = Future<Directory> Function();

final class StoryReferenceImportResult {
  const StoryReferenceImportResult({
    required this.document,
    required this.chunks,
    required this.deduplicated,
  });

  final StoryReferenceDocument document;
  final List<StoryReferenceChunk> chunks;
  final bool deduplicated;
}

/// Imports source fiction into the local Reference Library.
///
/// Only normalized text is retained for re-analysis. The callable runtime asset
/// remains a derived StyleProfile; normal Story turns never read the whole book.
final class StoryReferenceImportService {
  StoryReferenceImportService({
    required StoryReferenceDocumentRepository repository,
    StoryReferenceTextExtractor extractor = const StoryReferenceTextExtractor(),
    StoryReferenceChunker chunker = const StoryReferenceChunker(),
    StoryReferenceRootResolver? appDataRootResolver,
  }) : _repository = repository,
       _extractor = extractor,
       _chunker = chunker,
       _appDataRootResolver =
           appDataRootResolver ?? AppDirectories.getAppDataDirectory;

  final StoryReferenceDocumentRepository _repository;
  final StoryReferenceTextExtractor _extractor;
  final StoryReferenceChunker _chunker;
  final StoryReferenceRootResolver _appDataRootResolver;

  Future<StoryReferenceImportResult> importFile({
    required String path,
    String? title,
    String? mime,
    String? language,
  }) async {
    final extracted = await _extractor.extract(path: path, mime: mime);
    final resolvedTitle =
        _normalizeTitle(title) ??
        _normalizeTitle(extracted.suggestedTitle) ??
        'Reference';
    final fileName = path.replaceAll('\\', '/').split('/').last.trim();
    return _persist(
      text: extracted.text,
      title: resolvedTitle,
      sourceKind: StoryReferenceSourceKind.file,
      sourceFileName: fileName.isEmpty ? null : fileName,
      mime: extracted.mime,
      language: language,
    );
  }

  Future<StoryReferenceImportResult> importPastedText({
    required String text,
    required String title,
    String? language,
  }) async {
    final normalized = normalizeReferenceText(text);
    if (normalized.isEmpty) {
      throw const StoryReferenceImportException('source_text_empty');
    }
    return _persist(
      text: normalized,
      title: _normalizeTitle(title) ?? 'Reference',
      sourceKind: StoryReferenceSourceKind.pastedText,
      mime: 'text/plain',
      language: language,
    );
  }

  Future<StoryReferenceImportResult> _persist({
    required String text,
    required String title,
    required StoryReferenceSourceKind sourceKind,
    required String mime,
    String? sourceFileName,
    String? language,
  }) async {
    final normalized = normalizeReferenceText(text);
    final hash = sha256.convert(utf8.encode(normalized)).toString();
    final existing = await _repository.findByContentHash(hash);
    if (existing != null) {
      return StoryReferenceImportResult(
        document: existing,
        chunks: _chunker.chunk(documentId: existing.id, text: normalized),
        deduplicated: true,
      );
    }

    final id = 'ref_${hash.substring(0, 24)}';
    final chunks = _chunker.chunk(documentId: id, text: normalized);
    final root = await _appDataRootResolver();
    final libraryDir = Directory('${root.path}/story_reference_library/$id');
    await libraryDir.create(recursive: true);
    final normalizedFile = File('${libraryDir.path}/normalized.txt');
    await normalizedFile.writeAsString(normalized, flush: true);

    final document = StoryReferenceDocument(
      id: id,
      title: title,
      sourceKind: sourceKind,
      contentHash: hash,
      normalizedRelativePath: 'story_reference_library/$id/normalized.txt',
      characterCount: normalized.length,
      chunkCount: chunks.length,
      importedAtMs: DateTime.now().millisecondsSinceEpoch,
      sourceFileName: sourceFileName,
      mime: mime,
      language: _normalizeTitle(language),
    );

    try {
      await _repository.upsert(document);
    } catch (_) {
      try {
        await libraryDir.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }

    return StoryReferenceImportResult(
      document: document,
      chunks: chunks,
      deduplicated: false,
    );
  }

  Future<String> readNormalizedText(StoryReferenceDocument document) async {
    final root = await _appDataRootResolver();
    final relative = document.normalizedRelativePath;
    if (!_isSafeRelativePath(relative)) {
      throw const StoryReferenceImportException('unsafe_library_path');
    }
    final file = File('${root.path}/$relative');
    if (!await file.exists()) {
      throw const StoryReferenceImportException('library_text_missing');
    }
    return normalizeReferenceText(await file.readAsString());
  }

  Future<void> deleteDocument(String documentId) async {
    final document = await _repository.readById(documentId);
    if (document == null) return;
    await _repository.remove(document.id);

    final root = await _appDataRootResolver();
    final relative = document.normalizedRelativePath;
    if (!_isSafeRelativePath(relative)) return;
    final normalizedFile = File('${root.path}/$relative');
    final parent = normalizedFile.parent;
    try {
      if (await parent.exists()) await parent.delete(recursive: true);
    } catch (_) {}
  }
}

String? _normalizeTitle(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _isSafeRelativePath(String value) {
  if (value.isEmpty || value.startsWith('/') || value.startsWith('\\')) {
    return false;
  }
  final normalized = value.replaceAll('\\', '/');
  return !normalized.split('/').contains('..') &&
      normalized.startsWith('story_reference_library/');
}
