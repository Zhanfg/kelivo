import '../../../core/services/json_blob_store.dart';
import 'story_world_tree_models.dart';

abstract interface class StoryWorldTreeRepository {
  Future<StoryWorldTreeState?> read(String worldTreeId);
  Future<StoryWorldTreeState?> readForConversation(String conversationId);
  Future<void> upsert(StoryWorldTreeState state);
  Future<void> remove(String worldTreeId);
}

final class StoryWorldTreeStore extends JsonBlobStore<StoryWorldTreeState>
    implements StoryWorldTreeRepository {
  StoryWorldTreeStore(super.preferences);

  static const String key = 'story_world_trees_v1';

  @override
  String get storageKey => key;

  @override
  StoryWorldTreeState decodeItem(Map<String, dynamic> json) =>
      StoryWorldTreeState.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryWorldTreeState item) => item.toJson();

  @override
  Future<StoryWorldTreeState?> read(String worldTreeId) async {
    final id = _requiredId(worldTreeId, 'worldTreeId');
    for (final item in await readAll()) {
      if (item.worldTreeId == id) return item;
    }
    return null;
  }

  @override
  Future<StoryWorldTreeState?> readForConversation(
    String conversationId,
  ) async {
    final id = _requiredId(conversationId, 'conversationId');
    for (final item in await readAll()) {
      if (item.worldlineForConversation(id) != null) return item;
    }
    return null;
  }

  @override
  Future<void> upsert(StoryWorldTreeState state) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryWorldTreeState>[];
      var replaced = false;
      for (final item in items) {
        if (item.worldTreeId != state.worldTreeId) {
          next.add(item);
        } else if (!replaced) {
          next.add(state);
          replaced = true;
        }
      }
      if (!replaced) next.add(state);
      next.sort((a, b) => a.worldTreeId.compareTo(b.worldTreeId));
      await writeAll(next);
    });
  }

  @override
  Future<void> remove(String worldTreeId) {
    return runExclusive(() async {
      final id = _requiredId(worldTreeId, 'worldTreeId');
      final items = await readAll();
      final next = items
          .where((item) => item.worldTreeId != id)
          .toList(growable: false);
      if (next.length != items.length) await writeAll(next);
    });
  }
}

String _requiredId(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name);
  return normalized;
}
