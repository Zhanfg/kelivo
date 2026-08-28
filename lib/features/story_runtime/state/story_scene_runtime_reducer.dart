import '../models/story_runtime_models.dart';
import 'story_scene_runtime_state.dart';

/// Applies one parsed Story turn to persisted scene state.
///
/// The reducer is pure so Story response parsing can be tested without relying
/// on legacy preference storage. Unknown/ill-typed metadata is ignored rather
/// than poisoning a completed assistant turn.
StorySceneRuntimeState reduceStoryTurnIntoScene({
  required StorySceneRuntimeState current,
  required StoryTurn turn,
  required String worldTreeId,
  required String worldlineId,
}) {
  var sceneId = current.sceneId;
  var location = current.location;
  var timeLabel = current.timeLabel;
  var pov = current.pov;
  var participants = <String>{...current.participantCharacterIds};
  final openLoops = <String>[...current.openLoops];
  final continuity = <String, Object?>{...current.continuityState};
  final serial = <String, Object?>{...current.serialState};
  var changed = current.worldTreeId != worldTreeId ||
      current.worldlineId != worldlineId;

  for (final event in turn.events) {
    final metadata = event.metadata;

    if (event.type == StoryEventType.sceneTransition) {
      final nextSceneId = _string(metadata['scene_id']);
      final nextLocation = _string(metadata['location']);
      final nextTime = _string(metadata['time_label']);
      final nextPov = _string(metadata['pov']);
      final suppliedParticipants = _stringList(metadata['participant_character_ids']);

      if (nextSceneId != null && nextSceneId != sceneId) {
        sceneId = nextSceneId;
        changed = true;
      }
      if (nextLocation != null && nextLocation != location) {
        location = nextLocation;
        changed = true;
      }
      if (nextTime != null && nextTime != timeLabel) {
        timeLabel = nextTime;
        changed = true;
      }
      if (nextPov != null && nextPov != pov) {
        pov = nextPov;
        changed = true;
      }
      if (suppliedParticipants != null) {
        final next = suppliedParticipants.toSet();
        if (!_sameSet(participants, next)) {
          participants = next;
          changed = true;
        }
      }
    }

    // Character ids are internal continuity identities. Observing a character
    // in the current turn is enough to keep them in the active scene unless a
    // later scene_transition explicitly replaces the participant set.
    final characterId = event.actor.characterId?.trim();
    if (characterId != null &&
        characterId.isNotEmpty &&
        participants.add(characterId)) {
      changed = true;
    }

    for (final item in _stringList(metadata['open_loops_add']) ?? const <String>[]) {
      if (!openLoops.contains(item)) {
        openLoops.add(item);
        changed = true;
      }
    }
    final closed = (_stringList(metadata['open_loops_close']) ?? const <String>[])
        .toSet();
    if (closed.isNotEmpty) {
      final before = openLoops.length;
      openLoops.removeWhere(closed.contains);
      if (openLoops.length != before) changed = true;
    }

    if (_applyPatch(continuity, metadata['continuity_patch'])) changed = true;
    if (_applyPatch(serial, metadata['serial_patch'])) changed = true;
  }

  return current.copyWith(
    worldTreeId: worldTreeId,
    worldlineId: worldlineId,
    sceneId: sceneId,
    location: location,
    timeLabel: timeLabel,
    participantCharacterIds: participants.toList(growable: false)..sort(),
    pov: pov,
    openLoops: List<String>.unmodifiable(openLoops),
    continuityState: Map<String, Object?>.unmodifiable(continuity),
    serialState: Map<String, Object?>.unmodifiable(serial),
    revision: changed ? current.revision + 1 : current.revision,
  );
}

bool _applyPatch(Map<String, Object?> target, Object? rawPatch) {
  if (rawPatch is! Map) return false;
  var changed = false;
  for (final entry in rawPatch.entries) {
    final key = entry.key?.toString().trim() ?? '';
    if (key.isEmpty) continue;
    final value = entry.value;
    if (value == null) {
      if (target.remove(key) != null) changed = true;
      continue;
    }
    if (!target.containsKey(key) || target[key] != value) {
      target[key] = value;
      changed = true;
    }
  }
  return changed;
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String>? _stringList(Object? value) {
  if (value is! List) return null;
  final result = <String>[];
  final seen = <String>{};
  for (final item in value) {
    final normalized = _string(item);
    if (normalized != null && seen.add(normalized)) result.add(normalized);
  }
  return result;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
