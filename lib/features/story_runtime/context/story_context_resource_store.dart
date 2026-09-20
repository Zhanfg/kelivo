import '../../../core/services/json_blob_store.dart';
import 'story_context_resources.dart';

abstract interface class StoryContextResourceRepository {
  Future<StoryContextResources> readOrDefault(String conversationId);

  Future<void> upsert(StoryContextResources resources);

  Future<bool> remove(String conversationId);
}

final class StoryContextResourceStore extends JsonBlobStore<StoryContextResources>
    implements StoryContextResourceRepository {
  StoryContextResourceStore(super.preferences);

  static const String key = 'story_context_resources_v1';

  @override
  String get storageKey => key;

  @override
  StoryContextResources decodeItem(Map<String, dynamic> json) =>
      StoryContextResources.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryContextResources item) => item.toJson();

  @override
  Future<StoryContextResources> readOrDefault(String conversationId) async {
    final id = _requiredId(conversationId);
    for (final item in await readAll()) {
      if (item.conversationId == id) return item;
    }
    return StoryContextResources(conversationId: id);
  }

  @override
  Future<void> upsert(StoryContextResources resources) {
    return runExclusive(() async {
      final id = _requiredId(resources.conversationId);
      final normalized = StoryContextResources(
        conversationId: id,
        activePersonaId: resources.activePersonaId,
        personas: List.unmodifiable(resources.personas),
        quickReplies: List.unmodifiable(resources.quickReplies),
        regexRules: List.unmodifiable(resources.regexRules),
        dataBankEntries: List.unmodifiable(resources.dataBankEntries),
      );
      final items = await readAll();
      final next = <StoryContextResources>[];
      var replaced = false;
      for (final item in items) {
        if (item.conversationId != id) {
          next.add(item);
        } else if (!replaced) {
          next.add(normalized);
          replaced = true;
        }
      }
      if (!replaced) next.add(normalized);
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }

  @override
  Future<bool> remove(String conversationId) {
    return runExclusive(() async {
      final id = _requiredId(conversationId);
      final items = await readAll();
      final next = items
          .where((item) => item.conversationId != id)
          .toList(growable: false);
      if (next.length == items.length) return false;
      await writeAll(next);
      return true;
    });
  }
}

String _requiredId(String value) {
  final id = value.trim();
  if (id.isEmpty) throw ArgumentError.value(value, 'conversationId');
  return id;
}
