import 'dart:convert';

import '../../../core/database/business_preferences.dart';
import 'story_mvp_prompt_service.dart';

/// Persisted, synchronously readable Story MVP prompt snapshots.
///
/// GenerationController is intentionally synchronous when it constructs a
/// GenerationContext. Story Studio therefore resolves the async Skill/
/// Reference stores ahead of time and stores one compiled prompt per
/// conversation. The send path only performs a BusinessPreferences read.
final class StoryMvpPromptCache {
  StoryMvpPromptCache(this.preferences);

  static const String storageKey = 'story_mvp_prompt_cache_v1';

  final BusinessPreferences preferences;

  String? read({
    required String conversationId,
    String? assistantId,
  }) {
    final id = conversationId.trim();
    if (id.isEmpty) return null;
    final all = _readMap();
    final raw = all[id];
    if (raw is! Map) return null;
    final entry = raw.map((key, value) => MapEntry(key.toString(), value));
    final prompt = (entry['prompt'] ?? '').toString().trim();
    if (prompt.isEmpty) return null;

    final cachedAssistant = (entry['assistant_id'] ?? '').toString().trim();
    final currentAssistant = (assistantId ?? '').trim();
    if (cachedAssistant.isNotEmpty &&
        currentAssistant.isNotEmpty &&
        cachedAssistant != currentAssistant) {
      return null;
    }
    return prompt;
  }

  Future<void> refresh({
    required String conversationId,
    required String assistantId,
  }) async {
    final cid = conversationId.trim();
    final aid = assistantId.trim();
    if (cid.isEmpty) return;

    String? prompt;
    if (aid.isNotEmpty) {
      try {
        prompt = await StoryMvpPromptService(
          preferences,
        ).build(conversationId: cid, assistantId: aid);
      } catch (_) {
        prompt = null;
      }
    }

    final all = _readMap();
    if (prompt == null || prompt.trim().isEmpty) {
      all.remove(cid);
    } else {
      all[cid] = <String, Object?>{
        'assistant_id': aid,
        'prompt': prompt.trim(),
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      };
    }
    await preferences.setString(storageKey, jsonEncode(all));
  }

  Future<void> remove(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) return;
    final all = _readMap();
    if (all.remove(id) != null) {
      await preferences.setString(storageKey, jsonEncode(all));
    }
  }

  Map<String, Object?> _readMap() {
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Object?>{};
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return <String, Object?>{};
    }
  }
}
