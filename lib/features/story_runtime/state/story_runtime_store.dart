import '../../../core/database/business_preferences.dart';
import '../../../core/services/json_blob_store.dart';
import 'story_runtime_state.dart';

/// Versioned Story Mode state keyed by conversation id.
///
/// This deliberately uses Kelivo's existing business-preference repository
/// instead of adding fields to Conversation/Hive/Drift during the foundation
/// phase. Story Mode can therefore remain opt-in without changing Chat Mode's
/// persistence contract.
final class StoryRuntimeStore extends JsonBlobStore<StoryRuntimeSessionState> {
  StoryRuntimeStore(BusinessPreferences preferences) : super(preferences);

  static const String key = 'story_runtime_sessions_v1';

  @override
  String get storageKey => key;

  @override
  StoryRuntimeSessionState decodeItem(Map<String, dynamic> json) =>
      StoryRuntimeSessionState.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryRuntimeSessionState item) => item.toJson();

  Future<StoryRuntimeSessionState?> readForConversation(
    String conversationId,
  ) async {
    final id = _normalizeConversationId(conversationId);
    final items = await readAll();
    for (final item in items) {
      if (item.conversationId == id) return item;
    }
    return null;
  }

  Future<StoryRuntimeSessionState> readOrDefault(
    String conversationId,
  ) async {
    final id = _normalizeConversationId(conversationId);
    return await readForConversation(id) ??
        StoryRuntimeSessionState(conversationId: id);
  }

  Future<void> upsert(StoryRuntimeSessionState state) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryRuntimeSessionState>[];
      var replaced = false;
      for (final item in items) {
        if (item.conversationId != state.conversationId) {
          next.add(item);
          continue;
        }
        if (!replaced) {
          next.add(state);
          replaced = true;
        }
      }
      if (!replaced) next.add(state);
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }

  Future<void> setEnabled(String conversationId, bool enabled) {
    return runExclusive(() async {
      final id = _normalizeConversationId(conversationId);
      final items = await readAll();
      final next = <StoryRuntimeSessionState>[];
      var replaced = false;
      for (final item in items) {
        if (item.conversationId != id) {
          next.add(item);
          continue;
        }
        if (!replaced) {
          next.add(item.copyWith(enabled: enabled));
          replaced = true;
        }
      }
      if (!replaced) {
        next.add(
          StoryRuntimeSessionState(conversationId: id, enabled: enabled),
        );
      }
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }

  Future<void> removeForConversation(String conversationId) {
    return runExclusive(() async {
      final id = _normalizeConversationId(conversationId);
      final items = await readAll();
      final next = items
          .where((item) => item.conversationId != id)
          .toList(growable: false);
      if (next.length == items.length) return;
      await writeAll(next);
    });
  }
}

String _normalizeConversationId(String value) {
  final id = value.trim();
  if (id.isEmpty) throw ArgumentError.value(value, 'conversationId');
  return id;
}
