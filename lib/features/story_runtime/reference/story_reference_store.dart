import '../../../core/services/json_blob_store.dart';
import 'story_reference_models.dart';

abstract interface class StoryReferenceDocumentRepository {
  Future<List<StoryReferenceDocument>> readAll();
  Future<StoryReferenceDocument?> readById(String id);
  Future<StoryReferenceDocument?> findByContentHash(String contentHash);
  Future<void> upsert(StoryReferenceDocument document);
  Future<void> remove(String id);
}

final class StoryReferenceDocumentStore
    extends JsonBlobStore<StoryReferenceDocument>
    implements StoryReferenceDocumentRepository {
  StoryReferenceDocumentStore(super.preferences);

  static const String key = 'story_reference_documents_v1';

  @override
  String get storageKey => key;

  @override
  StoryReferenceDocument decodeItem(Map<String, dynamic> json) =>
      StoryReferenceDocument.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryReferenceDocument item) => item.toJson();

  @override
  Future<StoryReferenceDocument?> readById(String id) async {
    final normalized = _requiredId(id);
    for (final item in await readAll()) {
      if (item.id == normalized) return item;
    }
    return null;
  }

  @override
  Future<StoryReferenceDocument?> findByContentHash(String contentHash) async {
    final normalized = _requiredId(contentHash);
    for (final item in await readAll()) {
      if (item.contentHash == normalized) return item;
    }
    return null;
  }

  @override
  Future<void> upsert(StoryReferenceDocument document) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryReferenceDocument>[];
      var replaced = false;
      for (final item in items) {
        if (item.id == document.id) {
          if (!replaced) {
            next.add(document);
            replaced = true;
          }
          continue;
        }
        next.add(item);
      }
      if (!replaced) next.add(document);
      next.sort((a, b) => b.importedAtMs.compareTo(a.importedAtMs));
      await writeAll(next);
    });
  }

  @override
  Future<void> remove(String id) {
    return runExclusive(() async {
      final normalized = _requiredId(id);
      final items = await readAll();
      final next = items.where((item) => item.id != normalized).toList();
      if (next.length != items.length) await writeAll(next);
    });
  }
}

abstract interface class StoryReferenceProfileRepository {
  Future<List<StoryReferenceStyleProfile>> readAll();
  Future<StoryReferenceStyleProfile?> readById(String id);
  Future<List<StoryReferenceStyleProfile>> readForDocument(String documentId);
  Future<void> upsert(StoryReferenceStyleProfile profile);
  Future<void> remove(String id);
}

final class StoryReferenceProfileStore
    extends JsonBlobStore<StoryReferenceStyleProfile>
    implements StoryReferenceProfileRepository {
  StoryReferenceProfileStore(super.preferences);

  static const String key = 'story_reference_profiles_v1';

  @override
  String get storageKey => key;

  @override
  StoryReferenceStyleProfile decodeItem(Map<String, dynamic> json) =>
      StoryReferenceStyleProfile.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryReferenceStyleProfile item) =>
      item.toJson();

  @override
  Future<StoryReferenceStyleProfile?> readById(String id) async {
    final normalized = _requiredId(id);
    for (final item in await readAll()) {
      if (item.id == normalized) return item;
    }
    return null;
  }

  @override
  Future<List<StoryReferenceStyleProfile>> readForDocument(
    String documentId,
  ) async {
    final normalized = _requiredId(documentId);
    return List.unmodifiable(
      (await readAll()).where((item) => item.documentId == normalized),
    );
  }

  @override
  Future<void> upsert(StoryReferenceStyleProfile profile) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryReferenceStyleProfile>[];
      var replaced = false;
      for (final item in items) {
        if (item.id == profile.id) {
          if (!replaced) {
            next.add(profile);
            replaced = true;
          }
          continue;
        }
        next.add(item);
      }
      if (!replaced) next.add(profile);
      next.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      await writeAll(next);
    });
  }

  @override
  Future<void> remove(String id) {
    return runExclusive(() async {
      final normalized = _requiredId(id);
      final items = await readAll();
      final next = items.where((item) => item.id != normalized).toList();
      if (next.length != items.length) await writeAll(next);
    });
  }
}

String _requiredId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, 'id');
  return normalized;
}
