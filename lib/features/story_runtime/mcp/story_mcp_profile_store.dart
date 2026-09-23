import '../../../core/services/json_blob_store.dart';
import 'story_mcp_profile.dart';

final class StoryMcpProfileStore extends JsonBlobStore<StoryMcpProfile> {
  StoryMcpProfileStore(super.preferences);

  static const String key = 'story_mcp_profiles_v1';

  @override
  String get storageKey => key;

  @override
  StoryMcpProfile decodeItem(Map<String, dynamic> json) =>
      StoryMcpProfile.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryMcpProfile item) => item.toJson();

  Future<StoryMcpProfile?> readById(String id) async {
    final normalized = id.trim();
    if (normalized.isEmpty) return null;
    for (final item in await readAll()) {
      if (item.id == normalized) return item;
    }
    return null;
  }

  Future<void> upsert(StoryMcpProfile profile) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryMcpProfile>[];
      var replaced = false;
      for (final item in items) {
        if (item.id != profile.id) {
          next.add(item);
        } else if (!replaced) {
          next.add(profile);
          replaced = true;
        }
      }
      if (!replaced) next.add(profile);
      next.sort((a, b) => a.id.compareTo(b.id));
      await writeAll(next);
    });
  }

  Future<bool> remove(String id) {
    return runExclusive(() async {
      final normalized = id.trim();
      if (normalized.isEmpty) return false;
      final items = await readAll();
      final next = items
          .where((item) => item.id != normalized)
          .toList(growable: false);
      if (next.length == items.length) return false;
      await writeAll(next);
      return true;
    });
  }
}

final class StoryMcpProfileSelectionStore
    extends JsonBlobStore<StoryMcpProfileSelection> {
  StoryMcpProfileSelectionStore(super.preferences);

  static const String key = 'story_mcp_profile_selections_v1';

  @override
  String get storageKey => key;

  @override
  StoryMcpProfileSelection decodeItem(Map<String, dynamic> json) =>
      StoryMcpProfileSelection.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryMcpProfileSelection item) =>
      item.toJson();

  Future<StoryMcpProfileSelection> readForConversation(
    String conversationId,
  ) async {
    final id = conversationId.trim();
    if (id.isEmpty) throw ArgumentError.value(conversationId, 'conversationId');
    for (final item in await readAll()) {
      if (item.conversationId == id) return item;
    }
    return StoryMcpProfileSelection(conversationId: id);
  }

  Future<void> select(String conversationId, String? profileId) {
    return runExclusive(() async {
      final id = conversationId.trim();
      if (id.isEmpty) {
        throw ArgumentError.value(conversationId, 'conversationId');
      }
      final normalizedProfile = profileId?.trim();
      final nextSelection = StoryMcpProfileSelection(
        conversationId: id,
        profileId: normalizedProfile == null || normalizedProfile.isEmpty
            ? null
            : normalizedProfile,
      );
      final items = await readAll();
      final next = <StoryMcpProfileSelection>[];
      var replaced = false;
      for (final item in items) {
        if (item.conversationId != id) {
          next.add(item);
        } else if (!replaced) {
          next.add(nextSelection);
          replaced = true;
        }
      }
      if (!replaced) next.add(nextSelection);
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }

  Future<int> clearProfileReferences(String profileId) {
    return runExclusive(() async {
      final normalized = profileId.trim();
      if (normalized.isEmpty) return 0;
      final items = await readAll();
      var cleared = 0;
      final next = <StoryMcpProfileSelection>[
        for (final item in items)
          if (item.profileId == normalized) ...[
            StoryMcpProfileSelection(conversationId: item.conversationId),
          ] else ...[
            item,
          ],
      ];
      for (final item in items) {
        if (item.profileId == normalized) cleared++;
      }
      if (cleared > 0) await writeAll(next);
      return cleared;
    });
  }
}
