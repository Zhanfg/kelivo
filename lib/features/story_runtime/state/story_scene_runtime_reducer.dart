import '../models/story_runtime_models.dart';
import 'story_scene_runtime_state.dart';

/// Applies one parsed Story turn to persisted scene state.
///
/// Runtime state is authoritative. The model proposes only sparse semantic
/// deltas that cannot be derived locally; this reducer validates and applies
/// those deltas without turning the prose into a duplicated state dump.
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
  final relationships = <String, StoryRelationshipEdge>{
    for (final edge in current.relationships) edge.key: edge,
  };
  var availableChoices = <StoryChoice>[...current.availableChoices];
  var changed =
      current.worldTreeId != worldTreeId || current.worldlineId != worldlineId;

  for (final event in turn.events) {
    final metadata = event.metadata;

    if (event.type == StoryEventType.sceneTransition) {
      final result = _applyScenePatch(
        sceneId: sceneId,
        location: location,
        timeLabel: timeLabel,
        pov: pov,
        participants: participants,
        patch: metadata,
        replaceParticipants: true,
      );
      sceneId = result.sceneId;
      location = result.location;
      timeLabel = result.timeLabel;
      pov = result.pov;
      participants = result.participants;
      if (result.changed) changed = true;
    }

    final rawScenePatch = metadata['scene_patch'];
    if (rawScenePatch is Map) {
      final patch = Map<String, Object?>.from(rawScenePatch);
      final result = _applyScenePatch(
        sceneId: sceneId,
        location: location,
        timeLabel: timeLabel,
        pov: pov,
        participants: participants,
        patch: patch,
      );
      sceneId = result.sceneId;
      location = result.location;
      timeLabel = result.timeLabel;
      pov = result.pov;
      participants = result.participants;
      if (result.changed) changed = true;
    }

    if (_applyRelationshipPatch(relationships, metadata['relationship_patch'])) {
      changed = true;
    }

    if (event.type == StoryEventType.actionResult &&
        availableChoices.isNotEmpty) {
      // A user action consumes the previous decision point. A later choice_set
      // in the same turn may establish the next valid set.
      availableChoices = <StoryChoice>[];
      changed = true;
    }
    if (event.type == StoryEventType.choiceSet &&
        !_sameChoices(availableChoices, event.choices)) {
      availableChoices = List<StoryChoice>.unmodifiable(event.choices);
      changed = true;
    }

    // Character ids are internal continuity identities. Observing a character
    // in the current turn keeps them active unless scene_patch explicitly
    // removes them.
    final characterId = event.actor.characterId?.trim();
    if (characterId != null &&
        characterId.isNotEmpty &&
        participants.add(characterId)) {
      changed = true;
    }

    for (final item
        in _stringList(metadata['open_loops_add']) ?? const <String>[]) {
      if (!openLoops.contains(item)) {
        openLoops.add(item);
        changed = true;
      }
    }
    final closed =
        (_stringList(metadata['open_loops_close']) ?? const <String>[]).toSet();
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
    relationships: relationships.values.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key)),
    availableChoices: List<StoryChoice>.unmodifiable(availableChoices),
    continuityState: Map<String, Object?>.unmodifiable(continuity),
    serialState: Map<String, Object?>.unmodifiable(serial),
    revision: changed ? current.revision + 1 : current.revision,
  );
}

_ScenePatchResult _applyScenePatch({
  required String? sceneId,
  required String? location,
  required String? timeLabel,
  required String pov,
  required Set<String> participants,
  required Map<String, Object?> patch,
  bool replaceParticipants = false,
}) {
  var nextSceneId = sceneId;
  var nextLocation = location;
  var nextTimeLabel = timeLabel;
  var nextPov = pov;
  var nextParticipants = <String>{...participants};
  var changed = false;

  final suppliedSceneId = _string(patch['scene_id']);
  final suppliedLocation = _string(patch['location']);
  final suppliedTime = _string(patch['time_label']);
  final suppliedPov = _string(patch['pov']);
  final suppliedParticipants = _stringList(patch['participant_character_ids']);

  if (suppliedSceneId != null && suppliedSceneId != nextSceneId) {
    nextSceneId = suppliedSceneId;
    changed = true;
  }
  if (suppliedLocation != null && suppliedLocation != nextLocation) {
    nextLocation = suppliedLocation;
    changed = true;
  }
  if (suppliedTime != null && suppliedTime != nextTimeLabel) {
    nextTimeLabel = suppliedTime;
    changed = true;
  }
  if (suppliedPov != null && suppliedPov != nextPov) {
    nextPov = suppliedPov;
    changed = true;
  }

  if (suppliedParticipants != null && replaceParticipants) {
    final replacement = suppliedParticipants.toSet();
    if (!_sameSet(nextParticipants, replacement)) {
      nextParticipants = replacement;
      changed = true;
    }
  } else {
    for (final item in suppliedParticipants ?? const <String>[]) {
      if (nextParticipants.add(item)) changed = true;
    }
  }

  for (final item in _stringList(patch['participant_add']) ?? const <String>[]) {
    if (nextParticipants.add(item)) changed = true;
  }
  final remove =
      (_stringList(patch['participant_remove']) ?? const <String>[]).toSet();
  if (remove.isNotEmpty) {
    final before = nextParticipants.length;
    nextParticipants.removeWhere(remove.contains);
    if (nextParticipants.length != before) changed = true;
  }

  return _ScenePatchResult(
    sceneId: nextSceneId,
    location: nextLocation,
    timeLabel: nextTimeLabel,
    pov: nextPov,
    participants: nextParticipants,
    changed: changed,
  );
}

bool _applyRelationshipPatch(
  Map<String, StoryRelationshipEdge> target,
  Object? rawPatch,
) {
  if (rawPatch is! List) return false;
  var changed = false;
  for (final item in rawPatch) {
    if (item is! Map) continue;
    final map = Map<String, Object?>.from(item);
    final from = _string(map['from']);
    final to = _string(map['to']);
    final rawDelta = map['delta'];
    if (from == null || to == null || from == to || rawDelta is! Map) continue;

    final delta = <String, double>{};
    for (final entry in rawDelta.entries) {
      final axis = entry.key.toString().trim();
      final value = entry.value;
      if (axis.isEmpty || value is! num || !value.isFinite) continue;
      final normalized = value.toDouble().clamp(-1.0, 1.0).toDouble();
      if (normalized != 0) delta[axis] = normalized;
    }
    if (delta.isEmpty) continue;

    final key = '$from>$to';
    final before = target[key] ??
        StoryRelationshipEdge(fromId: from, toId: to);
    final after = before.applyDelta(delta);
    if (!_sameDoubleMap(before.dimensions, after.dimensions)) {
      target[key] = after;
      changed = true;
    }
  }
  return changed;
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

bool _sameChoices(List<StoryChoice> left, List<StoryChoice> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    final a = left[i];
    final b = right[i];
    if (a.id != b.id ||
        a.label != b.label ||
        a.submitText != b.submitText ||
        a.metadata.toString() != b.metadata.toString()) {
      return false;
    }
  }
  return true;
}

bool _sameDoubleMap(Map<String, double> left, Map<String, double> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
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

final class _ScenePatchResult {
  const _ScenePatchResult({
    required this.sceneId,
    required this.location,
    required this.timeLabel,
    required this.pov,
    required this.participants,
    required this.changed,
  });

  final String? sceneId;
  final String? location;
  final String? timeLabel;
  final String pov;
  final Set<String> participants;
  final bool changed;
}
