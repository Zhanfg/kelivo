import '../../../core/services/json_blob_store.dart';
import 'story_narrative_profile.dart';

final class StoryNarrativeProfileStore extends JsonBlobStore<StoryNarrativeProfile> {
  StoryNarrativeProfileStore(super.preferences);

  static const String key = 'story_narrative_profiles_v1';

  @override
  String get storageKey => key;

  @override
  StoryNarrativeProfile decodeItem(Map<String, dynamic> json) =>
      StoryNarrativeProfile.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryNarrativeProfile item) => item.toJson();

  Future<StoryNarrativeProfile?> readForConversation(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) throw ArgumentError.value(conversationId, 'conversationId');
    for (final item in await readAll()) {
      if (item.conversationId == id) return item;
    }
    return null;
  }

  Future<StoryNarrativeProfile> readOrDefault(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) throw ArgumentError.value(conversationId, 'conversationId');
    return await readForConversation(id) ??
        StoryNarrativeProfile(conversationId: id);
  }

  Future<void> upsert(StoryNarrativeProfile profile) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryNarrativeProfile>[];
      var replaced = false;
      for (final item in items) {
        if (item.conversationId == profile.conversationId) {
          if (!replaced) {
            next.add(profile);
            replaced = true;
          }
        } else {
          next.add(item);
        }
      }
      if (!replaced) next.add(profile);
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }
}
