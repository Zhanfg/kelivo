import '../../../core/services/json_blob_store.dart';
import 'story_voice_routing.dart';

final class StoryVoiceRoutingStore
    extends JsonBlobStore<StoryVoiceRoutingState> {
  StoryVoiceRoutingStore(super.preferences);

  static const String key = 'story_voice_routing_v1';

  @override
  String get storageKey => key;

  @override
  StoryVoiceRoutingState decodeItem(Map<String, dynamic> json) =>
      StoryVoiceRoutingState.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryVoiceRoutingState item) => item.toJson();

  Future<StoryVoiceRoutingState> readOrDefault(String worldTreeId) async {
    final id = worldTreeId.trim();
    if (id.isEmpty) throw ArgumentError.value(worldTreeId, 'worldTreeId');
    for (final item in await readAll()) {
      if (item.worldTreeId == id) return item;
    }
    return StoryVoiceRoutingState(worldTreeId: id);
  }

  Future<void> upsertState(StoryVoiceRoutingState state) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryVoiceRoutingState>[];
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

  Future<StoryVoiceAssignment> upsertCharacterAssignment({
    required String worldTreeId,
    required StoryVoiceAssignment assignment,
  }) async {
    final current = await readOrDefault(worldTreeId);
    final nextAssignments = <StoryVoiceAssignment>[];
    var replaced = false;
    for (final item in current.assignments) {
      final sameIdentity =
          item.characterId == assignment.characterId &&
          item.worldlineId == assignment.worldlineId;
      if (!sameIdentity) {
        nextAssignments.add(item);
      } else if (!replaced) {
        nextAssignments.add(assignment);
        replaced = true;
      }
    }
    if (!replaced) nextAssignments.add(assignment);
    nextAssignments.sort((a, b) {
      final character = a.characterId.compareTo(b.characterId);
      if (character != 0) return character;
      return (a.worldlineId ?? '').compareTo(b.worldlineId ?? '');
    });
    await upsertState(
      StoryVoiceRoutingState(
        worldTreeId: current.worldTreeId,
        narrator: current.narrator,
        assignments: List.unmodifiable(nextAssignments),
      ),
    );
    return assignment;
  }

  /// Promote/refine a recurring character without changing its stable id.
  ///
  /// The voice stays on the same service/voice unless the caller explicitly
  /// supplies an override. This prevents an NPC becoming important from
  /// sounding like a different person merely because its runtime role changed.
  Future<StoryVoiceAssignment> promoteCharacter({
    required String worldTreeId,
    required String characterId,
    String? worldlineId,
    String? ttsServiceId,
    String? voiceId,
    String? personaDescription,
    String? modelOverride,
  }) async {
    final state = await readOrDefault(worldTreeId);
    final existing = state.resolveCharacter(
      characterId,
      worldlineId: worldlineId,
    );
    if (existing == null &&
        ((ttsServiceId ?? '').trim().isEmpty ||
            (voiceId ?? '').trim().isEmpty)) {
      throw StateError('story_voice_promotion_requires_initial_voice');
    }
    final next = existing == null
        ? StoryVoiceAssignment(
            characterId: characterId,
            ttsServiceId: ttsServiceId!.trim(),
            voiceId: voiceId!.trim(),
            personaDescription: personaDescription?.trim() ?? '',
            modelOverride: modelOverride?.trim().isEmpty == true
                ? null
                : modelOverride?.trim(),
            worldlineId: worldlineId,
            revision: 1,
          )
        : existing.copyWith(
            ttsServiceId: ttsServiceId?.trim().isNotEmpty == true
                ? ttsServiceId!.trim()
                : existing.ttsServiceId,
            voiceId: voiceId?.trim().isNotEmpty == true
                ? voiceId!.trim()
                : existing.voiceId,
            personaDescription:
                personaDescription ?? existing.personaDescription,
            modelOverride: modelOverride?.trim().isNotEmpty == true
                ? modelOverride!.trim()
                : existing.modelOverride,
            revision: existing.revision + 1,
          );
    return upsertCharacterAssignment(
      worldTreeId: worldTreeId,
      assignment: next,
    );
  }
}
