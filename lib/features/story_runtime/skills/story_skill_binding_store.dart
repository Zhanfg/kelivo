import '../../../core/services/json_blob_store.dart';
import 'story_skill_models.dart';

abstract interface class StorySkillBindingRepository {
  Future<List<StorySkillBinding>> readForAssistant(String assistantId);

  Future<void> upsert(StorySkillBinding binding);

  Future<void> remove({required String assistantId, required String skillId});
}

/// Persists Assistant <-> Skill bindings and the user's auto-activation choice.
final class StorySkillBindingStore extends JsonBlobStore<StorySkillBinding>
    implements StorySkillBindingRepository {
  StorySkillBindingStore(super.preferences);

  static const String key = 'story_skill_bindings_v1';

  @override
  String get storageKey => key;

  @override
  StorySkillBinding decodeItem(Map<String, dynamic> json) {
    final assistantId = _requiredString(json, 'assistant_id');
    final skillId = _requiredString(json, 'skill_id');
    return StorySkillBinding(
      assistantId: assistantId,
      skillId: skillId,
      enabled: json['enabled'] != false,
      allowAutomaticActivation: json['allow_automatic_activation'] != false,
    );
  }

  @override
  Map<String, dynamic> encodeItem(StorySkillBinding item) => <String, dynamic>{
    'assistant_id': item.assistantId,
    'skill_id': item.skillId,
    'enabled': item.enabled,
    'allow_automatic_activation': item.allowAutomaticActivation,
  };

  @override
  Future<List<StorySkillBinding>> readForAssistant(String assistantId) async {
    final id = _normalizeId(assistantId);
    final result = (await readAll())
        .where((binding) => binding.assistantId == id)
        .toList(growable: false)
      ..sort((a, b) => a.skillId.compareTo(b.skillId));
    return List.unmodifiable(result);
  }

  @override
  Future<void> upsert(StorySkillBinding binding) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StorySkillBinding>[];
      var replaced = false;
      for (final item in items) {
        final same = item.assistantId == binding.assistantId &&
            item.skillId == binding.skillId;
        if (!same) {
          next.add(item);
          continue;
        }
        if (!replaced) {
          next.add(binding);
          replaced = true;
        }
      }
      if (!replaced) next.add(binding);
      next.sort((a, b) {
        final assistant = a.assistantId.compareTo(b.assistantId);
        return assistant != 0 ? assistant : a.skillId.compareTo(b.skillId);
      });
      await writeAll(next);
    });
  }

  @override
  Future<void> remove({
    required String assistantId,
    required String skillId,
  }) {
    return runExclusive(() async {
      final aid = _normalizeId(assistantId);
      final sid = _normalizeId(skillId);
      final items = await readAll();
      final next = items
          .where((item) => item.assistantId != aid || item.skillId != sid)
          .toList(growable: false);
      if (next.length != items.length) await writeAll(next);
    });
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('invalid_story_skill_binding_$key');
  }
  return value.trim();
}

String _normalizeId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, 'id');
  return normalized;
}
